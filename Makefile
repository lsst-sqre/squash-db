all:
MYSQL_CONFIG = kubernetes/mysql
MYSQL_PASSWD = passwd.txt
LOCAL_VOLUME_CONFIG = kubernetes/local_volume.yaml
PERSISTENT_VOLUME_CLAIM_CONFIG = kubernetes/persistent_volume_claim.yaml
DEPLOYMENT_CONFIG = kubernetes/deployment.yaml
SERVICE_CONFIG = kubernetes/service.yaml

secret: $(MYSQL_PASSWD)
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

deployment: service secret configmap
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


clean:
	rm $(MYSQL_PASSWD)


