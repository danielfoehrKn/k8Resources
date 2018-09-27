#!/usr/bin/env bash

# Prerequisites
# Important:
#  1) Please initalize the VMS/Nodes with a service account that has the roles to access the Cloud SQL Instance (Cloud SQL Admin & Compute Admin & Kubernetes Engine Admin) -> otherwise the backend pod is unable to access the Cloud SQL Instance - http 403 forbidden
#  2) When executing from Linux sub system on windows directory - convert to unix lin endings first ( sudo apt-get install dos2unix     -- then use command dos2unix [file] on linux)
#  3) Linux make sure to be executable: chmod u+x setup.sh


# ensure environment is prepared
if [ -f ./backend/catalania_secret.txt ] && [ -f ./backend/db_password.txt ] && [ -f ./backend/db_username.txt ]
then
    echo "Necessary files for the backend deployment exist"
else
    echo "Please create all 3 files: catalania_secret.txt (Tomcat options and env. variables e.g -XshowSettings -XX:+UnlockExperimentalVMOptions -XX:+UseCGroupMemoryLimitForHeap -DTOMCAT_PASSWORD=<YourPw> -DTOMCAT_USERNAME=admin  -DTOMCAT_ALLOW_REMOTE_MANAGEMENT=1
)  && db_password.txt (only containing password e.g <pw>) && db_username.txt (e.g admin) -> match in Cloud SQL"
    exit 1
fi

kubectl create clusterrolebinding cluster-admin-binding \
  --clusterrole cluster-admin \
  --user Daniel.fit95@gmail.com

# For all setup commands: fail script after a failed command
#set -e;

# create secrets being used in backend.yaml
kubectl create secret generic pod-options --from-file=catalania-opts=./backend/catalania_secret.txt
kubectl create secret generic db-secret --from-file=username=./backend/db_username.txt --from-file=password=./backend/db_password.txt

# create java backend deployment & cluster_ip service
kubectl apply -f ./backend/backend.yaml

# create Frontend
kubectl apply -f ./frontend/frontend.yaml

## create mongoDB - setup before Githubbot & Goanalyzer that are using the db
kubectl apply -f ./mongodb/storageClass.yaml
kubectl apply -f ./mongodb/statefulMongoSet.yaml
# fails if correct clusterrole binding for your user is not present
kubectl apply -f ./mongodb/mongoRbac.yaml
kubectl apply -f ./mongodb/headlessMongoService.yaml

# create Github Bot
kubectl apply -f ./githubBot/githubBot.yaml

# create GoAnalyzer
kubectl apply -f ./goanalyzer/goanalyzer.yaml


#Setup nginx ingress controller
kubectl apply -f ./charts/manifests/nginx-ingress/templates/clusterrole.yaml
kubectl apply -f ./charts/manifests/nginx-ingress/templates/role.yaml
kubectl apply -f ./charts/manifests/nginx-ingress/templates/serviceaccount.yaml
kubectl apply -f ./charts/manifests/nginx-ingress/templates/clusterrolebinding.yaml
kubectl apply -f ./charts/manifests/nginx-ingress/templates/rolebinding.yaml
kubectl apply -f ./charts/manifests/nginx-ingress/templates/default-backend-deployment.yaml
kubectl apply -f ./charts/manifests/nginx-ingress/templates/default-backend-service.yaml
kubectl apply -f ./charts/manifests/nginx-ingress/templates/controller-configmap.yaml
kubectl apply -f ./charts/manifests/nginx-ingress/templates/controller-deployment.yaml
kubectl apply -f ./charts/manifests/nginx-ingress/templates/controller-service.yaml

# ALTERNATIVE: Setup ingress controller with helm
# helm init --service-account helm
#helm install stable/nginx-ingress --debug --name nginx-ingress-controller --set rbac.create=true

kubectl rollout status deployment nginx-ingress-controller

while [ -z "$LB_INGRESS_IPS" ]
do
    sleep 5
    LB_INGRESS_IPS=$(kubectl get service nginx-ingress-controller -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
    echo "LoadBalancer Endpoint still creating $LB_INGRESS_IPS"
done

echo "Please register this IP-Address for the desired domain. Then continue script: $LB_INGRESS_IPS "
read -p "Press enter to continue"


# check if default backend is being returned when pinging the endpoint
while [ "$DEFAULT_BACKEND_RESPONSE" != "default backend - 404" ]
do
    sleep 5
    echo "Waiting for default backend response from domain.."
    DEFAULT_BACKEND_RESPONSE=$(curl https://k8blackwater-auto.ddnsking.com/ --insecure)
    echo "Response: $DEFAULT_BACKEND_RESPONSE"
done

# kubectl apply -f ./ingress/nginxIngressControllerDeploymentRBAC.yaml
echo "Setting up ingress route (no SSL)"
kubectl apply -f ./ingress/selfSignedCertificates/ingress_no_ssl.yaml

while true
do
    if curl -s https://k8blackwater-auto.ddnsking.com/ --insecure | grep "<!DOCTYPE html>"
    then
        echo "Frontend service successfully routed by ingress controller"
        break
    else
        echo "Frontend not reached yet..."
        sleep 5
    fi
done

echo "Setting up cert manager"

# create service account "helm" with admin privs to be used by the cert-manager
kubectl apply -f ./helm/create-helm-service-account.yaml
# TODO check if necessary -> rbac of helm also creates heml serviuce account but sets it to cert-admin instead of cluster admin

# Setup Cert-manager
kubectl apply -f ./charts/manifests/cert-manager/templates/certificate-crd.yaml
kubectl apply -f ./charts/manifests/cert-manager/templates/clusterissuer-crd.yaml
kubectl apply -f ./charts/manifests/cert-manager/templates/issuer-crd.yaml
kubectl apply -f ./charts/manifests/cert-manager/templates/serviceaccount.yaml
kubectl apply -f ./charts/manifests/cert-manager/templates/rbac.yaml
kubectl apply -f ./charts/manifests/cert-manager/templates/deployment.yaml

# ALTERNATIVE: setup cert-manager with helm
#helm install \
#    --name cert-manager \
#    --namespace kube-system\
#    stable/cert-manager
# kubectl rollout status deployment tiller-deploy -n=kube-system

#create specific LetsEncrypt Issuer
kubectl apply -f ./cert-manager/issuerLetsEncrypt.yaml

# delete old ingress! & create the new one with the cert manager stuff
kubectl apply -f ./ingress/ingress.yaml

kubectl apply -f ./cert-manager/certificateLetsEncrypt.yaml

#check for https
while true
do
    # curl checks the SSL cert and will return
    if curl -s https://k8blackwater-auto.ddnsking.com/ | grep "<!DOCTYPE html>"
    then
        echo "HTTPS working for domain"
        break
    else
        echo "HTTPS not working yet for domain ..."
        sleep 5
    fi
done

echo "Executing: 'kubectl describe certificate' : "
kubectl describe certificate
read -p "Press enter to continue"

CERT_MANAGER_POD_NAME=$(kubectl get pod -l app=cert-manager  -o jsonpath="{.items[0].metadata.name}")
echo "Verify logs of cert-manager pod $CERT_MANAGER_POD_NAME"
kubectl logs $CERT_MANAGER_POD_NAME
read -p "Press enter to continue"


# check if mongoDB has been set up correctly
echo "Checking MongoDB setup"
kubectl get statefulSet -o wide
read -p "Press enter to continue"


echo "Checking logs of mongo-sidecar container"
kubectl logs mongo-set-0 mongo-sidecar
read -p "Press enter to continue"

echo "Checking mongo console in one mongo container"
kubectl exec -it  mongo-set-0 mongo mongo
show dbs
read -p "Press enter to continue"


echo "Checking status of githubbot."
GITHUBBOT_POD_NAME=$(kubectl get pod -l app=githubbot  -o jsonpath="{.items[0].metadata.name}")
kubectl logs $GITHUBBOT_POD_NAME
read -p "Make sure that connection to mongo db is successfull. Press enter to continue"

echo "Checking status of goanalyzer."
GOANALYZER_POD_NAME=$(kubectl get pod -l app=goanalyzer  -o jsonpath="{.items[0].metadata.name}")
kubectl logs $GOANALYZER_POD_NAME
read -p "Make sure that connection to mongo db is successfull. Press enter to continue"

echo "Checking if tomcat of backend deployment is reachable by ssh into githubbot pod and wget on backend-service dns name"
kubectl exec -it $GITHUBBOT_POD_NAME /bin/sh
wget backend-service:8080
cat index.html
read -p "Make sure that index.html of Tomcat Server is visible"

echo "Checking if backend pod is connected to db"
wget backend-service:8080/echo/api/status
cat status
wget backend-service:8080/echo/api/db
cat db
read -p "Make sure that the status is 'Db up and running' - in case of error check the logs of the backend pod for further details"

read -p "Alright that should be it. Now go ahead and register a Github.com Repository, add a Webhook to loadbalancer:8080/github and create an issue."