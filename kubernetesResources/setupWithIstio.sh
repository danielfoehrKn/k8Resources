#!/usr/bin/env bash


kubectl create clusterrolebinding cluster-admin-binding \
  --clusterrole cluster-admin \
  --user Daniel.fit95@gmail.com

kubectl create namespace istio-system
kubectl apply -f ./charts/manifests/istio/istio.yaml

# create secret for kiali dashboard
kubectl apply -f ./charts/manifests/istio/kiali_dashboard_secret.yaml

# needed for istio sidecar injector
kubectl label namespace default istio-injection=enabled

while [ -z "$INGRESS_HOST" ]
do
    sleep 5
    INGRESS_HOST=$(kubectl get service istio-ingressgateway -n istio-system -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
    echo "Istio Ingress-Gateway: LoadBalancer Endpoint is still creating $INGRESS_HOST"
done

export INGRESS_HOST
export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
export SECURE_INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="https")].port}')
export GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT


# create secrets being used in backend.yaml
kubectl create secret generic pod-options --from-file=catalania-opts=./backend/catalania_secret.txt
kubectl create secret generic db-secret --from-file=username=./backend/db_username.txt --from-file=password=./backend/db_password.txt

# create java backend deployment & cluster_ip service
kubectl apply -f ./backend/backend.yaml
kubectl apply -f ./istio/mysqlDeployment.yaml

# Needed that backend can make egress connection to google cloud to authenticate with service Account && to for the jdbc TCP traffic to CloudSQL
kubectl apply -f ./istio/backend-cloudSQL-serviceEntry.yaml

## create mongoDB - no istio sidecar
kubectl apply -f ./mongodb/storageClass.yaml
kubectl apply -f ./mongodb/statefulMongoSet.yaml
# fails if correct clusterrole binding for your user is not present
kubectl apply -f ./mongodb/mongoRbac.yaml
kubectl apply -f ./mongodb/headlessMongoService.yaml

# needed that istio services can access mesh internal non-istio services
kubectl apply -f ./istio/mongo-destination-rule.yaml

# create GoAnalyzer -- needs to be setup before Github bot - somehow otherwise the bot cannot connect to the db
kubectl apply -f ./goanalyzer/goanalyzer.yaml
kubectl rollout status deployment goanalyzer-deployment

# verify connected to db
GO_POD_NAME=$(kubectl get pod -l app=goanalyzer  -o jsonpath="{.items[0].metadata.name}")
echo "Verify that GoAnalyzer is connected to db"
kubectl logs $GO_POD_NAME go
read -p "Press enter to continue"

# create Github Bot
kubectl apply -f ./githubBot/githubBot.yaml

# verify connected to db
BOT_POD_NAME=$(kubectl get pod -l app=githubbot  -o jsonpath="{.items[0].metadata.name}")
echo "Verify that GithubBot is connected to db - delete pod after the script if there was an error"
kubectl logs $BOT_POD_NAME bot
read -p "Press enter to continue"


# create Frontend
kubectl apply -f ./frontend/frontend.yaml

# create istio Gateway and Virtual Service that creates routes for frontend, githubbot and goAnalyzer
kubectl apply -f ./istio/frontend-gateway.yaml
kubectl apply -f ./istio/outside-facing-virtual-service.yaml

# check if frontend reachable via http
while true
do
    if curl "http://$GATEWAY_URL/"  | grep DOCTYPE
    then
        echo "Frontend service successfully reached - Gateway and Virtual Service // Envoys correctly configured. Route: http://$GATEWAY_URL/"
        break
    else
        echo "Frontend not reached yet..."
        sleep 5
    fi
done


# check if github bot reachable via http
while true
do
    if curl "http://$GATEWAY_URL/github"  | grep DOCTYPE
    then
        echo "Github Bot service successfully reached - Route: http://$GATEWAY_URL/github "
        break
    else
        echo "Github Bot not reached yet..."
        sleep 5
    fi
done


# check that GoAnalyzer is reachable
while true
do
    # Expecting report to return an empty array - bad when returrs Error: EOF -> then see MongoDB in OneNote
    if curl "http://$GATEWAY_URL/analyzer/report"  | grep []
    then
        echo "GoAnalyzer service successfully reached - Route: http://$GATEWAY_URL/analyzer/report "
        break
    else
        echo "GoAnalyzer not reached yet..."
        sleep 5
    fi
done

# Setup TLS for Gateway with self signed cert
    # -->  The secret must be called istio-ingressgateway-certs in the istio-system namespace, or it will not be mounted and available to the Istio gateway.

#kubectl create -n istio-system secret tls istio-ingressgateway-certs --key ./istio/selfSignedCertificate/mtls-go-example/3_application/private/httpbin.example.com.key.pem --cert ./istio/selfSignedCertificate/mtls-go-example/3_application/certs/httpbin.example.com.cert.pem

# validate that response is successful
#curl -v -HHost:httpbin.example.com --resolve httpbin.example.com:443:35.187.56.24 --cacert ./istio/selfSignedCertificate/mtls-go-example/2_intermediate/certs/ca-chain.cert.pem https://httpbin.example.com:443/status/418



# &&&&&     PROBLEMS   &&&&&&&&&&&&

# FIX Setup error when githubbot cannot connect to mongo db
# nake sure to connect to leader here
#kubectl exec -it  mongo-set-0 mongo mongo
## create db "github"
#use github