Simple heroku app with a bash script for capturing heroku database backups, compressing, encrypting and copying to a remote server. Deploy this as a separate app within heroku and schedule the script to backup your production databases which exist within another heroku project.

## Installation


First, clone this project, then change directory into the newly created directory:

```
git clone https://github.com/BoletoSimples/heroku-database-offsite-backups.git
cd heroku-database-offsite-backups
```

Create a project on heroku.

```
heroku create my-database-backups
```
Add the heroku-buildpack-cli:

```
heroku buildpacks:add https://github.com/heroku/heroku-buildpack-cli -a  my-database-backups
```

Add the heroku-buildpack-apy:

```
heroku buildpacks:add https://github.com/heroku/heroku-buildpack-apt -a  my-database-backups
```

Next push this project to your heroku projects git repository.

```
heroku git:remote -a my-database-backups
git push heroku master
```

Now we need to set some environment variables in order to get the heroku cli working properly using the [heroku-buildpack-cli](https://github.com/heroku/heroku-buildpack-cli).

```
heroku config:add HEROKU_API_KEY=`heroku auth:token` -a my-database-backups
```

This creates a token that will quietly expire in one year. To create a long-lived authorization token instead, do this:

```
heroku config:add HEROKU_API_KEY=`heroku authorizations:create -S -d my-database-backups` -a my-database-backups
```

We recommend to create a specific user on Heroku and give permissions to that user to all apps you want to backup. Eg: backup@yourcompany.com

Next we need to add the server and path where we would like to store our database backups:

```
heroku config:add TARGET_SERVER_PATH=root@server-host:/path_to_backup -a my-database-backups
```

Then we need to add the ssh key to be used to connect to remote server.

```
heroku config:add SSH_KEY="`cat myssh.key`" -a my-database-backups
```

We also need to configure the Encryption. Set the encryption key to be used on final backup files.

```
heroku config:add ENCRYPTION_KEY="`openssl rand -base64 32`" -a my-database-backups
```

ATTENTION: Remember to save this key on your password manager, otherwise you will not be able to recover the backup file!

You can skip encryption by setting NOENCRYPT="true".

Finally, we need to add heroku scheduler and call [backup.sh](https://github.com/BoletoSimples/heroku-database-offsite-backups/blob/master/bin/backup.sh) on a regular interval with the appropriate database and app.

```
heroku addons:create scheduler -a my-database-backups
```

Now open it up, in your browser with:

```
heroku addons:open scheduler -a my-database-backups
```

And add the following command to run as often as you like:

```
/app/bin/backup.sh
```

Install heroku-pg-extras if needed:

```
heroku plugins:install heroku-pg-extras --app=my-database-backups
```

You need to setup [heroku's scheduled backups](https://devcenter.heroku.com/articles/heroku-postgres-backups#scheduling-backups) on all your apps. This script do not capute backups, it only download the latest available backup made by Heroku scheduled backup.
### Optional

You can add a `HEARTBEAT_URL` to the script so a request gets sent every time a backup is made. All you have to do is add the variable value like:

```
heroku config:add HEARTBEAT_URL=https://hearbeat.url -a my-database-backups
```

You can specify the apps you want to backup, instead of backing up all available apps for the user whose token was used.

```
heroku config:add APPS=app-name-1,app-name-2 -a my-database-backups
```

#### Tip

The default timezone is `UTC`. To use your [preferred timezone](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones) in the filename timestamp, set the `TZ` variable when calling the command:

```
TZ=America/Los_Angeles /app/bin/backup.sh
```

### Source

This project was forked from [https://github.com/kbaum/heroku-database-backups](https://github.com/kbaum/heroku-database-backups)

Many thanks for [Karl Baum](https://github.com/kbaum), the author for the original script.