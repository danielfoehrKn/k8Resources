#!/usr/bin/env bash

kubectl delete secret pod-options
kubectl delete secret db-secret

kubectl delete service backend-service
kubectl delete service frontend-service

kubectl delete deployment frontend-deployment
kubectl delete deployment backend-deployment

# delete nginx
kubectl delete clusterrole nginx-ingress
kubectl delete role nginx-ingress
kubectl delete serviceaccount nginx-ingress
kubectl delete clusterrolebinding nginx-ingress
kubectl delete rolebinding nginx-ingress
kubectl delete deployment nginx-ingress-default-backend
kubectl delete service nginx-ingress-default-backend
kubectl delete configmap nginx-ingress-controller
kubectl delete service nginx-ingress-controller
kubectl delete deployment nginx-ingress-controller
kubectl delete secret nginx-ingress-token-xfzkn

# delete cert-manager
kubectl delete serviceaccount helm
kubectl delete clusterrole cert-manager
kubectl delete clusterrolebinding cert-manager
kubectl delete deployment cert-manager
kubectl delete issuer letsencrypt-production-issuer
kubectl delete ingress frontend-ingress
kubectl delete ingress cm-acme-http-solver-hpzvz
kubectl delete certificate letsencrypt-production-cert
kubectl delete customresourcedefinition certificates.certmanager.k8s.io
kubectl delete customresourcedefinition clusterissuers.certmanager.k8s.io
kubectl delete customresourcedefinition issuers.certmanager.k8s.io

kubectl delete secret letsencrypt-production-cert-secret
kubectl delete secret letsencrypt-production-issuer-secret




# In case helm was used: Remove Tiller from cluster to clean install it later
#helm del --purge cert-manager
#helm del --purge nginx-ingress
#helm reset --force

kubectl delete clusterrolebinding cluster-admin-binding

# In case helm was used:

#kubectl -n kube-system delete deployment tiller-deploy
# kubectl delete clusterrolebinding helm
# kubectl -n kube-system delete serviceaccount helm


