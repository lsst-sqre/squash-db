# squash-db

The SQuaSH DB microservice provides a persistent installation of `mariadb` for SQuaSH.

![SQuaSH DB microservice](squash-db.png)

# Requirements

There's no additional requirements for deploying `squash-db`, however the service is meant to be used with the [squash-api](https://github.com/lsst-sqre/squash-api) and operations like database migration or test data loading must be done from the [squash-api](https://github.com/lsst-sqre/squash-api) using Django's `manage.py`.

## Kubernetes deployment

Assuming you have `kubectl` configured to access your GCE cluster, you can deploy `squash-db` using:

```
  echo <database password> > passwd.txt
  make deployment
```

The [Kubernetes deployment](kubernetes/deployment.yaml) uses the official [`mariadb:10.3`](https://hub.docker.com/_/mariadb/) image. The
database password provided in `passwd.txt` is stored as a secret and passed to the container through the `MYSQL_ROOT_PASSWORD` environment variable. [Customized configuration](kubernetes/mysql) 
for mysql is added through a `configmap`. Finally, the persistent volume for the database is automatically created through a [volume claim](kubernetes/persistent_volume_claim.yaml).  

The environment variable `MYSQL_DATABASE` is used to create the `qadb` database used by SQuaSH during the container initialization.

## Debugging

You can inspect the deployment using:

```
kubectl describe deployment squash-db
``` 

and the `mariadb` container logs using:

```
kubectl logs deployment/squash-db mariadb
```

There is no `Cluster IP` for this service, port 3306 is target to the `squash-db` pod using the label selector. 
`squash-api` is able to ping and connect to `squash-db` pod and the image include some debug tools like `mysql` and `netcat`.

You can open a terminal inside the `squash-api` pod and connect to the database.

```
kubectl exec -it <squash-api pod> -c api /bin/bash

mysql -hsquash-db -uroot -p<database password>
```

## Scheduling periodic database backups

For database backups we use [kube-backup](https://github.com/lsst-sqre/kube-backup) which provides a utility container to back up files and databases from other containers.

There's a Kubernetes [Cron Job configuration](https://github.com/lsst-sqre/squash-db/kubernetes/squash-db-backup.yaml) to schedule backup jobs daily. It's meant to work only in the `squash-prod` namespace.  
In order to create the required secret for `kube-backup` you have to set the following environment variables:

```
export AWS_ACCESS_KEY_ID=<your AWS credentials>
export AWS_SECRET_ACCESS_KEY=<your AWS credentials>
export S3_BUCKET=<the S3 bucket URI to where we want to store the database backups>
export SLACK_WEBHOOK=<the Slack webhook URL for the #dm-square-status channel>
```

and then type `make squash_db_backup`.

Output example:

```bash

$ make squash-db-backup
Creating backup secret
kubectl delete --ignore-not-found=true secrets squash-db-backup
secret "squash-db-backup" deleted
kubectl create secret generic squash-db-backup \
        --from-literal=AWS_ACCESS_KEY_ID=*******
        --from-literal=AWS_SECRET_ACCESS_KEY=******* \
        --from-literal=S3_BUCKET=******* \
        --from-literal=SLACK_WEBHOOK=******** 
secret "squash-db-backup" created
Schedule periodic backups for squash-db
kubectl delete --ignore-not-found=true cronjob squash-db-backup
cronjob "squash-db-backup" deleted
kubectl create -f kubernetes/squash-db-backup.yaml
cronjob "squash-db-backup" created
```

## Restoring a copy of the current SQuaSH's production database


You can get a copy from the current production database from
AWS S3 (you will need your AWS credentials). 

Note that this procedure will change once we switch over to the new production deployment, see [DM-11486](https://jira.lsstcorp.org/browse/DM-11486).
This can be done opening a terminal inside the `squash-db` or `squash-api` pods.

```
aws s3 cp s3://jenkins-prod-qadb.lsst.codes-backups/qadb/latest.sql.gz .
gzip -d latest.sql.gz

kubectl cp latest.sql <squash-db pod>:/
kubectl exec -it <squash-db pod> /bin/bash
 
mysql -uroot -p<passwd> qadb < latest.sql
 
# The following is nedeed since the name of the django app changed 
# from 'dashboard' to 'api' in the current implementation. 
 
mysql -uroot -p<passwd> qadb -e "RENAME TABLE dashboard_job to api_job, dashboard_measurement to api_measurement, dashboard_metric to api_metric, dashboard_versionedpackage to api_versionedpackage"

```
