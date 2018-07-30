# Project Overview

This Repository contains all the API resources for the k8 cluster.


# Certificate Issue Flow 

![overview](https://raw.githubusercontent.com/jetstack/cert-manager/v0.2.3/docs/high-level-overview.png)

The Project uses the [Cert-manager](https://cert-manager.readthedocs.io/en/latest/reference/index.html) to issue X.509 Certificates for the custom domain exposed by the Gce external Loadbalancer & Nginx Ingress Controller

In more detail (if I understood correctly):
![slide1](https://user-images.githubusercontent.com/33809186/43423031-8b794406-944b-11e8-8784-a74d3188018b.PNG)

