#How to sign in users to your cluster (Authentication+Authorization)

As an administrator
1. Prepare authorization part
	- role + rolebinding for the group that user belongs to 
	- ex: make platform-engineers group inside that rolebinding
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: platform-engineer(or any name)
  namespace: saleor1
rules:
  - apiGroups: [""]
    resources:
      - pods
      - services
      - configmaps
    verbs:
      - get
      - list
      - watch
  - apiGroups: ["apps"]
    resources:
      - deployments
      - replicasets
    verbs:
      - get
      - list
      - watch

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: platform-engineers
  namespace: saleor1
subjects:
  - kind: Group
    name: platform-engineers
    apiGroup: rbac.authorization.k8s.io
roleRef:
    kind: Role
    name: platform-engineer
    apiGroup: rbac.authorization.k8s.io
```

2. prepare authentication part:
	- generate a private key using openssl with length=4096
		```bash
		openssl genrsa -out ca.key 4096
		```
	- Create a certificate using that private key in order to share it with other users.
	```bash
	openssl req -x509 \
	-new \
	-nodes \
	-key ca.key \
	-sha256 \
	-days 825 \
	-out ca.crt \
	-subj "/CN=kubernetes OIDC"
	#notes 
	-nodes -> dont encrypt the ca.key so that you need password to decrypt it when using this certification by other users.
	-sha256 -> this is the encryption algorithm
	-subj -> this will create the custom name in order to check when varifying this certification.
	  
	```

- now let's generate a private key for KeyCloak(the webapp that will handle OIDC )
```bash
openssl genrsa -out keycloak.key 2048 
# why using 2048 length
	- this is the standard for that key you can use 4096 it will work perfect
```
- then create the config that keycloak needs in order to sign the cert with Certificate Authority for the kubernetes that we generate above(ca.crt)
- open any editor in my case:(neovim)
	- nvim keycloak.cnf
```bash
[req]
distinguished_name = req_distinguished_name
req_extensions = req_ext
prompt = no
[req_distinguished_name]
CN = keycloak.local

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = keycloak.local
```
- then create Certificate signing request (CSR)in order to sign it with the Certificate authority of the cluster that we created before a while (ca.crt)
```bash
openssl req \
-new \
-key keycloak.key \
-out keycloak.csr \
-config keycloak.cnf
```
- now sign this csr with the CA-> generate keycloak.crt
```bash
openssl x509 \
-req  \
-in keycloak.csr \
-CA ca.crt \
-CAkey ca.key \
-CAcreateserial \
-out keycloak.crt \
-days 825 \
-sha256 \
-extensions req_ext \
-extfile keycloak.cnf 

```
- now test it in order to see this line "DNS:keycloak.local"
```bash
openssl x509 \
-in keycloak.crt \
-text \
-noout | grep -A2 "Subject AlternativeName"
```
- then on your machine open /etc/hosts and make this in order to use : keycloak.local instead of 127.0.0.1 
```bash
echo "127.0.0.1 keycloak.local  >> /etc/hosts"
#then test
getent hosts keycloak.local
```
- now prepare keycloak 
	- use docker container with ephemeral database in development mode while in production mode use proper TLS/database configuration. 
	- https://www.keycloak.org/getting-started/getting-started-kube
```bash
docker run -d \
  --name keycloak \
  --network kind \
  --network-alias keycloak \
  -p 8443:8443 \
  -e KC_BOOTSTRAP_ADMIN_USERNAME=admin \
  -e KC_BOOTSTRAP_ADMIN_PASSWORD=admin \
  -v "$PWD/certs:/opt/keycloak/certs:ro" \
  quay.io/keycloak/keycloak:26.7.4 \
  start-dev \
  --hostname=https://keycloak.local:8443 \
  --https-certificate-file=keycloak.crt \
  --https-certificate-key-file=keycloak.key\
  --https-port=8443

# now we attatched the key,certificate that we created in order to make it sign the the JWT to our kubelogin on the cluster.
```
- now test keycloak with our CA that we generated in order to see whether it will assign to us a JWT or not;
```bash 
curl \
  --cacert certs/ca.crt \
  https://keycloak.local:8443/realms/master/.well-known/openid-configuration
#output will contain these keywords
{
  "issuer": "...",
  "authorization_endpoint": "...",
  "token_endpoint": "...",
  "jwks_uri": "..."
}

```
- now open keycloak on your browser
```bash
https://keycloak.local:8443
#Log in
admin 
admin
```
- create Realm(tanent)
```bash
Realm name:
kubernetes
```
- create user
```
Users
  ↓
Create user
Username: Noah
Password: anysecureone
Temporary = OFF

```
- create group
```bash
In Keycloak:


Groups
   ↓
Create group
```

Create:

```text
platform-engineers
```

Then put the user that we created above in it:

```text
Noah
```
- then make a client 
```bash
Client ID: kubernetes
Name: kubernetes
vaild redirct URIs: http://127.0.0.1:8000/*
web origins: http://127.0.0.1:8000/
Authentication flow : on  at standard flow
```

--
- Now go to control-plane and do the following
```bash
docker cp \
  ca.crt \
  my-cluster-control-plane:/etc/kubernetes/pki/oidc-ca.crt

#varify the issuer and the signture of that certificate on control-plane
docker exec control-plane-name \
  openssl x509 \
  -in /etc/kubernetes/pki/oidc-ca.crt \
  -noout \
  -subject \
  -issuer \
  -fingerprint -sha256
  #the output should be = on your local machine run 
  openssl x509 \
-in ca.crt \
-text \
-noout 

----
# put this on the control plane
echo "172.19.0.5      keycloak.local" >>/etc/hosts
#check
getent hosts keycloak.local

---
# now check JWT from control-plane
curl \ --cacert /etc/kubernetes/pki/oidc-ca.crt \ https://keycloak.local:8443/realms/kubernetes/protocol/openid-connect/certs
#output must contain issuer,signture....

---
#now configure kube-apiserver to trust JWT that came from keycloak when a user hit login on it 
vi /etc/kubernetes/manifests/kube-apiserver.yaml
#put these under commands
--oidc-issuer-url=https://keycloak.local:8443/realms/kubernetes
--oidc-client-id=kubernetes
--oidc-username-claim=preferred_username
--oidc-groups-claim=groups
--oidc-ca-file=/etc/kubernetes/pki/oidc-ca.crt

#then make odic-ca.crt accessable by kube-apiserver in order to review JWT that came to it with it 
#at the same file put these  under volumeMounts
volumeMounts: 
- mountPath: /etc/kubernetes/pki/oidc-ca.crt 
  name: oidc-ca 
  readOnly: true
#then put these under volumes
volumes:
- hostPath:
    path: /etc/kubernetes/pki/oidc-ca.crt
    type: File
  name: oidc-ca
# kube-apiserver will do the following

```
<img width="372" height="427" alt="image" src="https://github.com/user-attachments/assets/5a43436e-a218-40f2-8764-51e789979393" />

--
- now i will use tailscale to open the cluster for accessing users from remote locations 
- so that you need to install tailscale if you want to build this lab while the other users don't need it 
- to install it as an admin 
	- install it for your device package manager
	- in my case: 
		- yum install tailscale (on my arch machine)
	- then login to it : tailscale up
	- then add your device to tailscale
	- then now you can access tailscale from konsole: tailscale ip
```bash
sudo tailscale serve --tcp=6443 tcp://127.0.0.1:portofyourcontrolplane
#how to find port:
docker inspect controlplanename | grep "Ports"
# now the port will be open publically
# for any user who want to access
# now move ca.crt from control-plane to the local machine in order to give it to the user
docker cp \
  my-cluster-control-plane:/etc/kubernetes/pki/ca.crt \
  /tmp/kubernetes-ca.crt
#then move it to the user machine
scp kubernetes-ca.crt user@ipadd:~/k8s/
#also move ca.crt on your local machine that you created above to the user machine
scp ca.crt user@ipadd:~/k8s/
#then test from user machine 
curl \
  --cacert oidc-ca.crt \
  https://keycloak.local:8443/realms/kubernetes/.well-known/openid-configuration
#this should return a JWks contain issuer,signiture...

---
#now make kubeconfig-user that contain the whole configuration in order to make it connect to the cluster.
vi remote-kubeconfig.yaml
#then add theses
apiVersion: v1
kind: Config

clusters:
- name: remote-kind
  cluster:
    server: https://archlinux.tail2992f3.ts.net:6443
    certificate-authority: ~/k8s/kubernetes-ca.crt
    tls-server-name: kubernetes

users:
- name: adam
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1
      interactiveMode: Never
      command: kubectl
      args:
      - oidc-login
      - get-token
      - --oidc-issuer-url=https://keycloak.local:8443/realms/kubernetes
      - --oidc-client-id=kubernetes
      - --oidc-redirect-url=http://127.0.0.1:8000
      - --listen-address=127.0.0.1:8000
      - --grant-type=authcode
      - --certificate-authority=~/k8s/oidc-ca.crt

contexts:
- name: adam-remote
  context:
    cluster: remote-kind
    user: adam
    namespace: saleor1

current-context: adam-remote

# test the connection from the remote machine
KUBECONFIG=~/k8s-oidc-lab/remote-kubeconfig.yaml \ kubectl config get-contexts
#should return adam-remote (name of the cluster)
#then 
kubectl --kubeconfig=remote-kubeconfig.yaml get pods 
kubectl --kubeconfig=remote-kubeconfig.yaml get deploy 
kubectl --kubeconfig=remote-kubeconfig.yaml get services 
kubectl --kubeconfig=remote-kubeconfig.yaml get pods -n kube-system #this should return error-forbidden
 
```

The authentication flow will eventually be:

```text
kubectl
   │
   │ "I need a token"
   ▼
kubelogin
   │
   │ Browser
   ▼
Keycloak
   │
   │ JWT / ID token
   ▼
kubelogin
   │
   │ Bearer token
   ▼
Tailscale
   │
   ▼
kube-apiserver
   │
   ├── Verify issuer
   ├── Verify signature
   ├── Verify expiration
   ├── Verify audience
   ├── Extract username
   └── Extract groups
             │
             ▼
           RBAC
             │
             ▼
       Kubernetes resource
```

- some commands you may need while you are working on this lab:

```bash
kubectl config view --minify   #to see your cluster info
kubectl --kubeconfig=ahmed-kubeconfig \
  get pods -n saleor1  #in order to login as another user on the cluster
  openssl verify -CAfile ca.crt keycloak.crt #in order to check whther there are matching between CA,keycloak certs or not 
  #output: must be
  # keycloak.crt: OK
sudo nohup tailscale serve --tcp=6443 tcp://127.0.0.1:43839 > /dev/null 2>&1 &
- to run tailscale in the background
== 
(sudo tailscale serve --bg --tcp=6443 tcp://127.0.0.1:43839)
```

- references:
	- https://www.keycloak.org/guides
	- https://tailscale.com/
