all:
MYSQL_CONFIG = kubernetes/mysql
MYSQL_PASSWD = passwd.txt
LOCAL_VOLUME_CONFIG = kubernetes/local_volume.yaml
PERSISTENT_VOLUME_CLAIM_CONFIG = kubernetes/persistent_volume_claim.yaml
DEPLOYMENT_CONFIG = kubernetes/deployment.yaml
SERVICE_CONFIG = kubernetes/service.yaml
DB_BACKUP_CONFIG = kubernetes/squash-db-backup.yaml

$(MYSQL_PASSWD):
	@echo "Enter a password for the SQuaSH DB:"
	@read MYSQL_PASSWD; \
	echo $$MYSQL_PASSWD | tr -d '\n' > $(MYSQL_PASSWD)

mysql-secret: $(MYSQL_PASSWD)
	@echo "Creating secret for squash-db password..."
	kubectl delete --ignore-not-found=true secrets mysql-passwd
	kubectl create secret generic mysql-passwd --from-file=$(MYSQL_PASSWD)

configmap: $(MYSQL_CONFIG)
	@echo "Creating config map for specific mysql configuration..."
	kubectl delete --ignore-not-found=true configmap mysql-conf
	kubectl create configmap mysql-conf --from-file=$(MYSQL_CONFIG)

service:
	@echo "Creating service..."
	kubectl delete --ignore-not-found=true services squash-db
	kubectl create -f $(SERVICE_CONFIG)

deployment: service mysql-secret configmap
	@echo "Creating deployment..."

	kubectl delete --ignore-not-found=true PersistentVolume mysql-volume-1
	@if [ "${LOCAL_VOLUME}" = "true" ]; then\
	    echo "Creating a local persistent volume ...";\
	    kubectl create -f $(LOCAL_VOLUME_CONFIG);\
	fi

	kubectl delete --ignore-not-found=true PersistentVolumeClaim mysql-volume-claim
	kubectl create -f $(PERSISTENT_VOLUME_CLAIM_CONFIG)

	kubectl delete --ignore-not-found=true deployment squash-db
	kubectl create -f $(DEPLOYMENT_CONFIG)

backup-secret: check-aws-creds check-s3-bucket check-slack-webhook
	@echo "Creating backup secret"
	kubectl delete --ignore-not-found=true secrets squash-db-backup
	kubectl create secret generic squash-db-backup \
        --from-literal=AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} \
        --from-literal=AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} \
        --from-literal=S3_BUCKET=${S3_BUCKET} \
        --from-literal=SLACK_WEBHOOK=${SLACK_WEBHOOK}

squash-db-backup:  backup-secret
	@echo "Schedule periodic backups for squash-db"
	kubectl delete --ignore-not-found=true cronjob squash-db-backup
	kubectl create -f $(DB_BACKUP_CONFIG)

check-aws-creds:
	@if [ -z ${AWS_ACCESS_KEY_ID} ]; \
	then echo "Error: AWS_ACCESS_KEY_ID is undefined."; \
       exit 1; \
    fi
	@if [ -z ${AWS_SECRET_ACCESS_KEY} ]; \
    then echo "Error: AWS_SECRET_ACCESS_KEY is undefined."; \
       exit 1; \
    fi

check-s3-bucket:
	@if [ -z ${S3_BUCKET} ]; \
	then echo "Error: S3_BUCKET is undefined."; \
       exit 1; \
    fi

check-slack-webhook:
	@if [ -z "${SLACK_WEBHOOK}" ]; \
	then echo "Error: SLACK_WEBHOOK is undefined."; \
       exit 1; \
    fi

clean:
	rm $(MYSQL_PASSWD)


