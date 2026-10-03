<img width="565" height="742" alt="image" src="https://github.com/user-attachments/assets/0e4d1404-ea67-4da0-be7e-d1b891ee6f8b" />

```bash
#go into the control-plane of your cluster
docker exec -it  control-plane-name bash
#create konnectivity server and add permission on it
mkdir -p /etc/kubernetes/konnectivity-server
chmod 700 /etc/kubernetes/konnectivity-server

#create the konnectivity server certificate
1. generate a private key,custom signing request key
openssl req \
  -subj "/CN=system:konnectivity-server" \
  -new \
  -newkey rsa:2048 \
  -noenc \
  -out konnectivity.csr \
  -keyout konnectivity.key
2.Sign that csr with CA of your cluster
openssl x509 \
  -req \
  -in konnectivity.csr \
  -CA /etc/kubernetes/pki/ca.crt \
  -CAkey /etc/kubernetes/pki/ca.key \
  -CAcreateserial \
  -out konnectivity.crt \
  -days 375 \
  -sha256

3.change modes
chmod 600 konnectivity.key
chmod 644 konnectivity.crt
chmod 644 konnectivity.csr
4. varify that your konnectivity.crt is accepted by CA
openssl verify \
  -CAfile /etc/kubernetes/pki/ca.crt \
  /etc/kubernetes/konnectivity-server/konnectivity.crt
5.check its identity (look at CN it must == that one you entered above we you generated the keys)
openssl x509 \
  -in /etc/kubernetes/konnectivity-server/konnectivity.crt \
  -noout \
  -subject \
  -issuer
6.create konnectivity server kubeconfig in order to be able to access this cluster as this user(konnectivity-user) and get pods according to the identity that we added to you(clusterrole)-> system:auth-delegator 
#get the server url 
SERVER="$(
  kubectl \
    --kubeconfig=/etc/kubernetes/admin.conf \
    config view \
    -o jsonpath='{.clusters[0].cluster.server}'
)"

echo "$SERVER"

#create the cluster part 

kubectl \
  --kubeconfig=/etc/kubernetes/konnectivity-server.conf \
  config set-cluster kubernetes \
  --server="$SERVER" \
  --certificate-authority=/etc/kubernetes/pki/ca.crt \
  --embed-certs=true
#create the credential part of that 
kubectl \
  --kubeconfig=/etc/kubernetes/konnectivity-server.conf \
  config set-credentials system:konnectivity-server \
  --client-certificate=/etc/kubernetes/konnectivity-server/konnectivity.crt \
  --client-key=/etc/kubernetes/konnectivity-server/konnectivity.key \
  --embed-certs=true
#create the context part of that cubeconfig
kubectl \
  --kubeconfig=/etc/kubernetes/konnectivity-server.conf \
  config set-context system:konnectivity-server@kubernetes \
  --cluster=kubernetes \
  --user=system:konnectivity-server 
  
# test that context that you created using kubeconfig (if it 's switched to that context -> then your work is correct)
kubectl \
  --kubeconfig=/etc/kubernetes/konnectivity-server.conf \
  config use-context system:konnectivity-server@kubernetes
# add permissions to that generated file 
chmod 600 /etc/kubernetes/konnectivity-server.conf
#test another way
kubectl \
  --kubeconfig=/etc/kubernetes/konnectivity-server.conf \
  auth whoami
#output: system:konnectivity-server

#note: to return to your context
#kubectl config view (look at cluster name and put after set-context the name in my case -> kubernetes-admin@mycluster)
#kubectl \
#--kubeconfig=/etc/kubernetes/admin.conf
#set-context kubernets-admin@mycluster 

#find your control-plane IP
CONTROL_PLANE_IP="$(
  kubectl get node "$CONTROL_PLANE_NODE" \
    -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}'
)"

```

- now create the rbac: 
```bash
nvim /etc/kubernetes/konnectivity-rbac.yaml
---

apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:konnectivity-server
  labels:
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: Reconcile
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: system:konnectivity-server

---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: konnectivity-agent
  namespace: kube-system
  labels:
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: Reconcile
---
#apply it
kubectl apply -f /etc/kubernetes/konnectivity-rbac.yaml

```

- create (egress-selector in order to move apply the connection usign gRPC between konnectivity-server,UDS(unique domain socket))
```bash
nvim /etc/kubernetes/egress-selector-config.yml
---
apiVersion: apiserver.k8s.io/v1beta1
kind: EgressSelectorConfiguration

egressSelections:
- name: cluster
  connection:
    proxyProtocol: GRPC
    transport:
      uds:
        udsName: /etc/kubernetes/konnectivity-server/konnectivity-server.socket
```
- create the connectivity server static pod
```bash
nvim /etc/kubernetes/konnectivity-server.yaml

---
apiVersion: v1
kind: Pod

metadata:
  name: konnectivity-server
  namespace: kube-system

spec:
  priorityClassName: system-cluster-critical

  hostNetwork: true

  containers:
  - name: konnectivity-server
    image: registry.k8s.io/kas-network-proxy/proxy-server:v0.0.37

    command:
    - /proxy-server

    args:
    - --logtostderr=true
    - --uds-name=/etc/kubernetes/konnectivity-server/konnectivity-server.socket
    - --delete-existing-uds-file
    - --cluster-cert=/etc/kubernetes/pki/apiserver.crt
    - --cluster-key=/etc/kubernetes/pki/apiserver.key
    - --mode=grpc
    - --server-port=0
    - --agent-port=8132
    - --admin-port=8133
    - --health-port=8134
    - --agent-namespace=kube-system
    - --agent-service-account=konnectivity-agent
    - --kubeconfig=/etc/kubernetes/konnectivity-server.conf
    - --authentication-audience=system:konnectivity-server

    livenessProbe:
      httpGet:
        scheme: HTTP
        host: 127.0.0.1
        port: 8134
        path: /healthz
      initialDelaySeconds: 30
      timeoutSeconds: 60

    ports:
    - name: agentport
      containerPort: 8132
      hostPort: 8132

    - name: adminport
      containerPort: 8133
      hostPort: 8133

    - name: healthport
      containerPort: 8134
      hostPort: 8134

    volumeMounts:
    - name: k8s-certs
      mountPath: /etc/kubernetes/pki
      readOnly: true

    - name: kubeconfig
      mountPath: /etc/kubernetes/konnectivity-server.conf
      readOnly: true

    - name: konnectivity-uds
      mountPath: /etc/kubernetes/konnectivity-server
      readOnly: false

  volumes:
  - name: k8s-certs
    hostPath:
      path: /etc/kubernetes/pki

  - name: kubeconfig
    hostPath:
      path: /etc/kubernetes/konnectivity-server.conf
      type: File

  - name: konnectivity-uds
    hostPath:
      path: /etc/kubernetes/konnectivity-server
      type: DirectoryOrCreate


```

- create the connectivity agent Daemonset
```bash
apiVersion: apps/v1
kind: DaemonSet

metadata:
  name: konnectivity-agent
  namespace: kube-system
  labels:
    k8s-app: konnectivity-agent

spec:
  selector:
    matchLabels:
      k8s-app: konnectivity-agent

  template:
    metadata:
      labels:
        k8s-app: konnectivity-agent

    spec:
      priorityClassName: system-cluster-critical

      tolerations:
      - key: CriticalAddonsOnly
        operator: Exists

      - key: node-role.kubernetes.io/control-plane  #this is important in order to run the agent on the control plane
        operator: Exists
        effect: NoSchedule

      serviceAccountName: konnectivity-agent

      containers:
      - name: konnectivity-agent
        image: registry.k8s.io/kas-network-proxy/proxy-agent:v0.0.37

        command:
        - /proxy-agent

        args:
        - --logtostderr=true
        - --ca-cert=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        - --proxy-server-host=${CONTROL_PLANE_IP}
        - --proxy-server-port=8132
        - --admin-server-port=8133
        - --health-server-port=8134
        - --service-account-token-path=/var/run/secrets/tokens/konnectivity-agent-token

        volumeMounts:
        - name: konnectivity-agent-token
          mountPath: /var/run/secrets/tokens

        livenessProbe:
          httpGet:
            port: 8134
            path: /healthz
          initialDelaySeconds: 15
          timeoutSeconds: 15

      volumes:
      - name: konnectivity-agent-token
        projected:
          sources:
          - serviceAccountToken:
              path: konnectivity-agent-token
              audience: system:konnectivity-server

---
kubectl apply -f /etc/kubernetes/konnectivity-agent.yaml
kubectl rollout status daemonset/konnectivity-agent -n kube-system
```

- Now: modify kube-apiserver static pod in order to handle this process.
```bash
nvim /etc/kubernetes/manifests/kube-apiserver.yml
--
# add this
- --egress-selector-config-file=/etc/kubernetes/egress-selector-config.yml
#then add this under mountPath
- mountPath: /etc/kubernetes/konnectivity-server
  name: konnectivity-uds
  readOnly: false

- mountPath: /etc/kubernetes/egress-selector-config.yml
  name: egress-selector-config
  readOnly: true
#then add this under hostPath
- name: konnectivity-uds
  hostPath:
    path: /etc/kubernetes/konnectivity-server
    type: DirectoryOrCreate

- name: egress-selector-config
  hostPath:
    path: /etc/kubernetes/egress-selector-config.yml
    type: File
```

- Now : test the whole process
```bash
kubectl get --raw=/api/v1/nodes/my-cluster-worker/proxy/healthz
#should return : Ok
kubectl get --raw=/api/v1/nodes/my-cluster-worker2/proxy/healthz
kubectl get --raw=/api/v1/nodes/my-cluster-control-plane/proxy/healthz
```
