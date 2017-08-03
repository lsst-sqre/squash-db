# squash-db
Persistent installation of MariaDB on Kubernetes for SQuaSH

## The squash-db microservice

The SQuaSH DB microservice provides a `MariaDB 10.3` installation using a [persistent volume in GKE](kubernetes/gke-volume.yaml). There's also a mount point
to store customized mysql configuration.

![SQuaSH DB microservice](squash-db.png)


This service is meant to be used with the[squash-api](https://github.com/lsst-sqre/squash-api) and[squash-bokeh](https://github.com/lsst-sqre/squash-bokeh) microservices.
## Deployment steps 

Provision a Kubernetes cluster in GKE, and then deploy `squash-db` microservice using:

```
echo <database password> > passwd.txt
make deployment
```

You can get the host and port for the service with:

```
kubectl get service squash-db
```

NOTE: for local deployment with `minikube` there's the option of using a [local persistent volume](kubernetes/local_volume.yaml). If using `minikube` make the deployment with:
 
```
echo <database password> > passwd.txt
MINIKUBE=true make deployment
```

The[Kubernetes deployment](kubernetes/deployment.yaml) uses the official [`mariadb:10.3`](https://hub.docker.com/_/mariadb/) image. The
database password you provide in `passwd.txt` is stored as a secret (aslo used by other microservices, like the `squash-api`)[Customized configuration](kubernetes/mysql/squash-db.cnf) 
for mysql is added through a configmap. Finally, the persistent volume for the database is previously created, and then[claimed during the deployment](kubernetes/persistent_volume_claim.yaml).  

## Diagnostics

You can inspect the deployment using:

```
kubectl describe deployment squash-db
``` 

and the `mariadb` container logs using:

```
kubectl logs deployment/squash-db mariadb
```

## Restoring a copy of SQuaSH's production database

For local tests it's useful to restore a copy of the production SQuaSH database. Currently, you can get that from AWS S3 backups (you will need your AWS credentials):

```
aws s3 cp s3://jenkins-prod-qadb.lsst.codes-backups/qadb/latest.sql.gz .
gzip -d latest.sql.gz
    
mysql -h <host> --port <port> -u root -p <passwd> -e "CREATE DATABASE qadb"
mysql -h <host> --port <port> -u root -p <passwd> qadb < latest.sql
```
