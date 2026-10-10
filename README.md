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
- https://github.com/Abdulrahman-122/Saleor_infrastructure_kubernetes_kind_aws_securityfeatures_devopsfeatures/blob/main/konnectivity-server.md

7. Install metrics-server + VPA(vertical pod autoscaler)
- for metrics server (install this chart and install that metrics-server according to this file) https://artifacthub.io/packages/helm/metrics-server/metrics-server
- for vpa do the following steps
  - clone the vpa repo:git clone https://github.com/kubernetes/autoscaler.git
  - then go to vertical-pod-autoscaler: cd autoscaler/vertical-pod-autoscaler
  - install vpa: ./hack/vpa-up.sh
  - now test: kubectl get vpa 
9. Build the helm release
  - in case you want to helm install directly : just do => helm install name-of-release . --namespace  any-namespace
  - in case you need to updrade the helm on a file -> helm upgrade name-of-release   path-of-chart    -f  path-to-file

10. for aws how to build the cluster on it
```
go to aws-cluster folder and do the following
# i will assume you will use the free-eligible tier so i just used the free resources for me
-> provision the cluster
# eksctl create cluster cluster-name -f  aws-cluster/k8s/eksctl_cluster.yaml
#now the cluster will work but some addons maybe not as you didn't associate the proper IAM roles
in this case:
Run these commands:

```
kubectl get nodes -o wide
```


aws eks describe-cluster \
  --name saleor-clust \
  --region us-east-1 \
  --query 'cluster.{Status:status,Version:version}' \
  --output table

aws eks describe-addon \
  --cluster-name saleor-clust \
  --addon-name aws-ebs-csi-driver \
  --region us-east-1 \
  --query 'addon.{Status:status,Version:addonVersion,Issues:health.issues}' \
  --output json

```

First, install the EKS Pod Identity Agent:

```
eksctl create addon \
  --cluster saleor-clust \
  --region us-east-1 \
  --name eks-pod-identity-agent
```

If it already exists, inspect it rather than trying to create it again:

```
aws eks describe-addon \
  --cluster-name saleor-clust \
  --addon-name eks-pod-identity-agent \
  --region us-east-1 \
  --query 'addon.status' \
  --output text

aws eks describe-addon \
  --cluster-name saleor-clust \
  --addon-name aws-ebs-csi-driver \
  --region us-east-1 \
  --query 'addon.{Status:status,Version:addonVersion,Issues:health.issues}' \
  --output json
set the role for the nodes
ROLE_ARN=$(aws eks describe-nodegroup \
  --cluster-name saleor-clust \
  --nodegroup-name saleor-workers \
  --region us-east-1 \
  --query 'nodegroup.nodeRole' \
  --output text)

ROLE_NAME="${ROLE_ARN##*/}"

echo "$ROLE_NAME"

aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy

#restarrt thee ebs controller
kubectl rollout restart deployment/ebs-csi-controller \
  -n kube-system

#how to solve the problem of Load balancer on aws
First check whether your EKS cluster has an OIDC issuer:

```
aws eks describe-cluster \
  --name saleor-clust \
  --region us-east-1 \
  --query 'cluster.identity.oidc.issuer' \
  --output text
```

If it returns a URL, continue to the IAM policy step. If it returns `None`, associate an OIDC provider:

```
eksctl utils associate-iam-oidc-provider \
  --cluster saleor-clust \
  --region us-east-1 \
  --approve
```

Next, download the controller's official IAM policy:

```
curl -o iam_policy.json \
  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.14.1/docs/install/iam_policy.json
```

Check whether you already have this policy:

```
aws iam list-policies \
  --scope Local \
  --query "Policies[?PolicyName=='AWSLoadBalancerControllerIAMPolicy'].Arn" \
  --output text
```

If that returns no ARN, create the policy:

```
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json
```

If it returns an ARN, reuse that ARN rather than creating a duplicate. You can retrieve your AWS account ID with:

```
aws sts get-caller-identity --query Account --output text
```

Create the controller's dedicated Kubernetes service account and IAM role, replacing `YOUR_ACCOUNT_ID` with your account ID:

```
eksctl create iamserviceaccount \
  --cluster saleor-clust \
  --region us-east-1 \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn arn:aws:iam::YOUR_ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve
```

If this service account already exists, inspect it before rerunning the command; you may need to use `--override-existing-serviceaccounts`.

Install the controller using Helm:

```
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks

helm upgrade --install aws-load-balancer-controller \
  eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=saleor-clust \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --version 1.14.0
```

Verify the deployment:

```
kubectl get deployment aws-load-balancer-controller -n kube-system
kubectl logs deployment/aws-load-balancer-controller -n kube-system --tail=50
```

You want the deployment to become available, with its replicas ready.

aws elbv2 describe-load-balancers \
  --region us-east-1 \
  --query 'LoadBalancers[].{Name:LoadBalancerName,DNS:DNSName,Scheme:Scheme,Type:Type,State:State.Code}' \
  --output table

aws elbv2 describe-load-balancers \
  --region us-east-1 \
  --query 'LoadBalancers[].{Name:LoadBalancerName,DNS:DNSName,Scheme:Scheme,Type:Type,State:State.Code}' \
  --output table













