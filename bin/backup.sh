#!/bin/bash

# terminate script as soon as any command fails
set -e

date2stamp () {
  if [[ `uname` == 'Darwin' ]]; then
    date -jf '%Y-%m-%d' "$1" '+%s'
  else
    date --utc --date "$1" +%s
  fi
}

dateDiff (){
    case $1 in
        -s)   sec=1;      shift;;
        -m)   sec=60;     shift;;
        -h)   sec=3600;   shift;;
        -d)   sec=86400;  shift;;
        *)    sec=86400;;
    esac
    dte1=$(date2stamp $1)
    dte2=$(date2stamp $2)
    diffSec=$((dte2-dte1))
    if ((diffSec < 0)); then abs=-1; else abs=1; fi
    echo $((diffSec/sec*abs))
}

if [[ -z "$APPS" ]]; then
  echo "Missing APPS variable which must be set to the name of your apps where the db is located, separated by comma"
  echo "Getting list of all available apps ..."
  APPS=$(heroku apps | awk '{print $1;}' | sed 's/[^a-zA-Z0-9-]//g' | sed  '/^$/d' | tr -s '\n' ',')
  echo "Available apps: $APPS"
fi

if [[ -z "$TARGET_SERVER_PATH" ]]; then
  echo "Missing TARGET_SERVER_PATH variable which must be set the scp path on the target server, eg: user@host:/destinantion_path/"
  exit 1
fi

if [[ -z "$NOENCRYPT" ]]; then
  if [[ -z "$ENCRYPTION_KEY" ]]; then
    echo "Missing ENCRYPTION_KEY variable which must be set with the password used to encrypt backup"
    exit 1
  fi
fi

if [[ ! -f "backup.key" ]]; then
  if [[ -z "$SSH_KEY" ]]; then
    echo "Missing SSH_KEY variable which must be set with the ssh key to be used to connect to target server"
    exit 1
  fi
fi

if ! type "ccrypt" > /dev/null; then
  echo "Command ccrypt not found. You have to install this package before continuing."
  exit 1
fi

if [[ ! -f "backup.key" ]]; then
  echo "Saving SSH key from \$SSH_KEY to backup.key ... "
  echo "$SSH_KEY" > backup.key
  chmod 600 backup.key
fi

IFS=',' # space is set as delimiter
read -ra ADDR <<< "$APPS" # str is read into an array as tokens separated by IFS
for APP in "${ADDR[@]}"; do # access each element of array

  echo "Starting Backup of $APP"
  echo "-----------------------------"

  echo "Checking latest backup of $APP ..."
  BACKUP_INFO=$(heroku pg:backups -a $APP)
  BACKUP_INFO=$(echo $BACKUP_INFO | sed -n '2p')
  if [[ "$BACKUP_INFO" == *"No backups."* ]]; then
    echo "No database backups available. Skipping ..."
    continue
  fi
  BACKUP_INFO=$(heroku pg:backups:info -a $APP)
  FINISHED=$(echo $BACKUP_INFO | sed -n '4p')
  FINISHED_DATE=${FINISHED:18:10}
  FINISHED_TIME=${FINISHED:29:8}
  TODAY=$(date '+%Y-%m-%d')
  DIFF=$(dateDiff -d "$FINISHED_DATE" "$TODAY")
  echo "  Last backup was generated at $FINISHED_DATE $FINISHED_TIME"
  if [[ $DIFF > 2 ]]; then
    echo "  WARNING! Last backup was generated more than 3 days ago."
  fi

  LATEST_FILE_NAME="latest-${APP}.dump"
  if [[ `uname` == 'Darwin' ]]; then
    FINAL_FILE_NAME="$(date -jf '%Y-%m-%d %H:%M:%S' "$FINISHED_DATE $FINISHED_TIME" +"%Y-%m-%d_%H-%M_UTC_")${APP}.dump"
  else
    FINAL_FILE_NAME="$(date --date "$FINISHED_DATE $FINISHED_TIME" +"%Y-%m-%d_%H-%M_UTC_")${APP}.dump"
  fi

  echo "Backup file : $FINAL_FILE_NAME"

  echo "Checking if backup already exists ..."
  IFS=':'
  read -ra SSH_SPLIT <<< "$TARGET_SERVER_PATH"
  SSH_SERVER=${SSH_SPLIT[0]}
  SSH_PATH=${SSH_SPLIT[1]}

  EXISTS=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i backup.key $SSH_SERVER ls $SSH_PATH | grep $FINAL_FILE_NAME | wc -l | tr -d ' ')
  if [[ $EXISTS == "1" ]]; then
    echo "  Backup already exists in remote server. Skipping ..."
    continue
  fi

  if [[ ! -f $LATEST_FILE_NAME ]]; then
    echo "Downloading latest backup of $APP to $LATEST_FILE_NAME ... "
    curl -s -o $LATEST_FILE_NAME `heroku pg:backups:url --app $APP`
  fi
  TMP_FILE_NAME=$LATEST_FILE_NAME

  if [[ -z "$NOGZIP" ]]; then
    echo "Compressing $TMP_FILE_NAME ... "
    gzip -f $TMP_FILE_NAME
    FINAL_FILE_NAME="$FINAL_FILE_NAME.gz"
    TMP_FILE_NAME=$TMP_FILE_NAME.gz
  fi

  if [[ -z "$NOENCRYPT" ]]; then
    echo "Encrypting $TMP_FILE_NAME ... "
    ccencrypt -f -K $ENCRYPTION_KEY $TMP_FILE_NAME
    FINAL_FILE_NAME="$FINAL_FILE_NAME.cpt"
    TMP_FILE_NAME=$TMP_FILE_NAME.cpt
  fi

  echo "Renaming $TMP_FILE_NAME to $FINAL_FILE_NAME ... "
  mv $TMP_FILE_NAME $FINAL_FILE_NAME

  echo "Uploading $FINAL_FILE_NAME to $TARGET_SERVER_PATH ... "
  scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q -i backup.key $FINAL_FILE_NAME $TARGET_SERVER_PATH

  echo "Removing $FINAL_FILE_NAME ... "
  rm $FINAL_FILE_NAME

  echo "Backup of $APP complete"
done

if [[ -f "backup.key" ]]; then
  echo "Removing backup.key ... "
  rm backup.key
fi

if [[ -n "$HEARTBEAT_URL" ]]; then
  echo "Sending a request to the specified HEARTBEAT_URL that the backup was created"
  curl $HEARTBEAT_URL
  echo "heartbeat complete"
fi
