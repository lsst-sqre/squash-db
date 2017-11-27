# squash-db

The SQuaSH DB microservice provides a persistent installation of `mariadb` for SQuaSH.

![SQuaSH DB microservice](squash-db.png)

# Requirements

There's no additional requirements for deploying `squash-db`, however the service is meant to be used with the [squash-api](https://github.com/lsst-sqre/squash-api) and operations like database migration or test data loading must be done from the [squash-api](https://github.com/lsst-sqre/squash-api) using Django's `manage.py`.

## Kubernetes deployment

Assuming you have `kubectl` configured to access your GKE cluster, you can deploy `squash-db` using:

```
  cd squash-db
  make passwd.txt
  make deployment
```

The [Kubernetes deployment](kubernetes/deployment.yaml) uses the official [`mariadb:10.3`](https://hub.docker.com/_/mariadb/) image. The
database password provided in `passwd.txt` is stored as a secret and passed to the container through the `MYSQL_ROOT_PASSWORD` environment variable. [Customized configuration](kubernetes/mysql) 
for mysql is added through a `configmap`. Finally, the persistent volume for the database is automatically created through a [volume claim](kubernetes/persistent_volume_claim.yaml).  

The environment variable `MYSQL_DATABASE` is used to create the `qadb` database during the container initialization.

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

## Scheduling periodic backups

For database back ups we use [kube-backup](https://github.com/lsst-sqre/kube-backup) which provides a utility container to back up files and databases from other containers.

The Kubernetes [Cron Job configuration](https://github.com/lsst-sqre/squash-db/kubernetes/squash-db-backup.yaml) will schedule backup jobs daily. It's meant to work only in the `squash-prod` namespace.  

In order to create the required secret you have to set the following environment variables:

```
export AWS_ACCESS_KEY_ID=<your AWS credentials>
export AWS_SECRET_ACCESS_KEY=<your AWS credentials>
export S3_BUCKET=jenkins-prod-qadb.lsst.codes-backups
export SLACK_WEBHOOK=<the Slack webhook URL for the #dm-square-status channel>
```

then create the `squash-db-backup` job using:

```
make squash-db-backup
```

Output example:

```bash
$ make squash-db-backup
Creating backup secret
kubectl delete --ignore-not-found=true secrets squash-db-backup
secret "squash-db-backup" deleted
kubectl create secret generic squash-db-backup \
        --from-literal=AWS_ACCESS_KEY_ID=*******
        --from-literal=AWS_SECRET_ACCESS_KEY=******* \
        --from-literal=S3_BUCKET=jenkins-prod-qadb.lsst.codes-backups\
        --from-literal=SLACK_WEBHOOK=******** 
secret "squash-db-backup" created
Schedule periodic backups for squash-db
kubectl delete --ignore-not-found=true cronjob squash-db-backup
cronjob "squash-db-backup" deleted
kubectl create -f kubernetes/squash-db-backup.yaml
cronjob "squash-db-backup" created
```

If needed you can run the `kube-backup` container manually, e.g:
 
```bash
kubectl run --attach --rm  --restart=Never --image=lsstsqre/kube-backup:latest squash-db-backup -- --task=backup-mysql-exec --namespace=squash-prod --secret=squash-db-backup --pod=<squash-db pod> --container=mariadb
```

Output example:

```bash
$ kubectl run --attach --rm  --restart=Never --image=lsstsqre/kube-backup:latest squash-db-backup -- --task=backup-mysql-exec --namespace=squash-prod --secret=squash-db-backup --pod=squash-db-64cb9ccf-7l5h6 --container=mariadb
---
If you don't see a command prompt, try pressing enter.
Pod 'squash-db-64cb9ccf-7l5h6' has 1 containers: mariadb
Specified container 'mariadb' found in pod 'squash-db-64cb9ccf-7l5h6'
Fetched S3 bucket name from 'squash-db-backup' secret
Fetched AWS credientials from 'squash-db-backup' secret
No database specified, getting database name from environment of container 'mariadb'
Backing up MySQL database 'qadb' from container 'mariadb' in pod 'squash-db-64cb9ccf-7l5h6' to 's3://jenkins-prod-qadb.lsst.codes-backups/squash-prod/20171106-2208/squash-db-64cb9ccf-7l5h6-mariadb-qadb-20171106-2208.gz'
Backed up MySQL database 'qadb' from container 'mariadb' in pod 'squash-db-64cb9ccf-7l5h6' to 's3://jenkins-prod-qadb.lsst.codes-backups/squash-prod/20171106-2208/squash-db-64cb9ccf-7l5h6-mariadb-qadb-20171106-2208.gz'
Done
```


## Restoring a back up copy of the production database

You can get a copy of the production database from the daily back ups (see above).

```
aws s3 ls s3://jenkins-prod-qadb.lsst.codes-backups/squash-prod/
aws s3 cp s3://jenkins-prod-qadb.lsst.codes-backups/squash-prod/<YYYYMMDD-HHMM>/squash-db-mariadb-qadb-<YYYYMMDD-HHMM>.gz .
 
kubectl cp squash-db-mariadb-qadb-<YYYYMMDD-HHMM>.gz <squash-db pod>:/
 
kubectl exec -it <squash-db pod> /bin/bash
gzip -d squash-db-mariadb-qadb-<YYYYMMDD-HHMM>.gz 
 
mysql -uroot -p<passwd> qadb < squash-db-mariadb-qadb-<YYYYMMDD-HHMM>
```
