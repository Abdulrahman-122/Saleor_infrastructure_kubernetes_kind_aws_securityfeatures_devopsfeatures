# Saleor_infrastructure_kubernetes_kind_aws_securityfeatures_devopsfeatures
- <img width="1197" height="797" alt="image" src="https://github.com/user-attachments/assets/0250acd7-4f64-44d6-b276-b9a0688e8f56" />

# How to build this infrastructure???

1. understand the main idea
```
we trying to build a cluster with control plane and many of nodes (probably 2)
and we need to apply these features in order to understand Kubernetes deeply

# Saleor DevOps Project — Completed Features

## Application & Containers

- 🟢 ✅ Saleor GraphQL backend containerized
- 🟢 ✅ Saleor Dashboard containerized
- 🟢 ✅ PostgreSQL deployed in Kubernetes
- 🟢 ✅ Redis service configured
- 🟢 ✅ Docker images built and published to Docker Hub
- 🟢 ✅ GraphQL API and Dashboard exposed through Kubernetes Services

## Kubernetes & AWS

- 🟢 ✅ Local multi-node Kubernetes cluster using kind
- 🟢 ✅ AWS EKS cluster created
- 🟢 ✅ EKS worker node group configured
- 🟢 ✅ Kubernetes namespaces used to organize workloads
- 🟢 ✅ PostgreSQL StatefulSet deployed
- 🟢 ✅ PersistentVolumeClaim created and bound
- 🟢 ✅ PostgreSQL persistent-volume initialization issue resolved
- 🟢 ✅ AWS EBS CSI driver troubleshooting completed
- 🟢 ✅ AWS LoadBalancer Services/manifests applied

## CI/CD & Infrastructure

- 🟢 ✅ GitHub Actions CI workflows
- 🟢 ✅ Backend linting with Ruff
- 🟢 ✅ Backend type checking with mypy
- 🟢 ✅ Backend automated tests with pytest
- 🟢 ✅ Docker image build and publishing workflow
- 🟢 ✅ Terraform-based AWS infrastructure work

## Monitoring & Networking

- 🟢 ✅ Prometheus and Grafana monitoring work
- 🟢 ✅ Grafana dashboard work for Saleor Production
- 🟢 ✅ Kubernetes metrics and PromQL exploration
- 🟢 ✅ NGINX Gateway Fabric and Gateway API experiments
- 🟢 ✅ Kubernetes RBAC and ServiceAccount labs
- 🟢 ✅ Kubernetes NetworkPolicy experiments
- 🟢 ✅ DNS, routing and service-connectivity troubleshooting
Implemented / Worked On
- 🟢 ✅ Kubernetes authentication and authorization concepts and configuration
- 🟢 ✅ RBAC using Roles, ClusterRoles, RoleBindings and ClusterRoleBindings
- 🟢 ✅ ServiceAccounts and permissions testing
- 🟢 ✅ Remote Kubernetes API access experiments using Tailscale
- 🟢 ✅ Konnectivity troubleshooting and investigation
- 🟢 ✅ Keycloak deployment and HTTPS certificate configuration attempts
- 🟢 ✅ Konnectivity server and agent connectivity — investigated, but end-to-end health needs confirmation
- 🟢 ✅ Keycloak OIDC authentication — configuration underway; successful login and token issuance still need verification
- 🟢 ✅ Keycloak-backed Kubernetes authorization — requires verified identity claims and RBAC bindings
- 🟢 ✅ Encryption at rest for Kubernetes Secrets — needs confirmation that API-server encryption is configured and working
- 🟢 ✅ remote user access with individual identities and least-privilege permissions

```

3. Build the encryption at rest feature
```
what we are trying to do -> is to encrypt the data on etcd ( as api server store everything on it) so we need to encrypt everything in case other persons came to our cluster so that they can't do anything
steps:
----
=>generate an encryption key (on your control plane) write
# head -c 32 /dev/urandom | base64
=>create the encryption configurations
#mkdir -p /etc/kubernetes/enc
#chmod  700 /etc/kubernetes/enc
#nvim /etc/kubernetes/enc.yml
-copy the following
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
-----
resources:
  - resources:
      - secrets
      - configmaps

    providers:
      - aesgcm:
          keys:
            - name: key1
              secret: YOUR_BASE64_KEY_HERE

      - identity: {}
-----
-> protect enc.yml
#chmod 600 /etc/kubernetes/enc/enc.yml
#now open kube-apiserver and do the following
Under the command arguments, add:

```yaml
- --encryption-provider-config=/etc/kubernetes/enc/enc.yaml
Under `volumeMounts:` add:

```yaml
- name: encryption-config
  mountPath: /etc/kubernetes/enc
  readOnly: true
```

And under `volumes:` add:

```yaml
- name: encryption-config
  hostPath:
    path: /etc/kubernetes/enc
    type: DirectoryOrCreate
```

Conceptually:

```yaml
containers:
- command:
  - kube-apiserver
  ...
  - --encryption-provider-config=/etc/kubernetes/enc/enc.yaml

  volumeMounts:
  ...
  - name: encryption-config
    mountPath: /etc/kubernetes/enc
    readOnly: true

volumes:
...
- name: encryption-config
  hostPath:
    path: /etc/kubernetes/enc
    type: DirectoryOrCreate

#now varify the encryption is added to the server
#if you had config.yml or secret.yml
# you will need to apply them again or even replace the data inside kube-apiserver with the newer configurations by running the following (everything will be wrote again)
# kubectl get secrets --all-namespaces -o json | kubectl replace -f -


#now to make sure that your data is encrypted
#install etcdctl cli
 # apt-get update && apt-get install -y etcd-client
#now see the data
# ETCDCTL_API=3 etcdctl \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  get /registry/secrets/saleor1/api-secret
The output should contain something similar to:

```text
k8s:enc:aesgcm:v1:key1:
#seimilar for configmaps
ETCDCTL_API=3 etcdctl \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  get /registry/configmaps/saleor1/api-config


```
- you will see something like this
<img width="536" height="115" alt="image" src="https://github.com/user-attachments/assets/655e727f-f93c-481f-ac72-c211068c454c" />


5. Build the konnectivity server (in order to apply secure the connection between the server and the agents on every node
```
go to this file i made all the stuff about this there: 
```
7. Install metrics-server + VPA(vertical pod autoscaler)
8. Build the helm release
9. for aws how to build the cluster on it

notes:
