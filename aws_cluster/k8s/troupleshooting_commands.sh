#these are some commands i usually use when a problem hits me  in the cluster.
--inside control-plane
crictl ps | grep kube-apiserver            # in order to see the id of kube-apiserver in order to check it's logs..
crictl inspect     <id-kube-apiserver>  | grep -A20 -B5 -E 
# • -A20 (--after-context=20): Prints 20 lines of trailing context after each matching line.
# • -B5 (--before-context=5): Prints 5 lines of leading context before each matching line.
# • -E (--extended-regexp): Interprets the pattern as an extended regular expression (ERE), which allows you to use the | (OR) operator without escaping it.
# • '"exitCode"|"reason"|"message"': The search pattern. It looks for any line containing either "exitCode", "reason", or "message".
#check logs of that ID
crictl logs <ID> 
#check kubelet of kube-apiserver
journalctl -u kubelet --since "2026-09-27 11:35:00" --until "2026-09-27 12:00:00" --no-pager | grep -Ei 'kube-apiserver|kill|stop|oom|evict|probe|liveness|readiness|static|container'
#check docker status for kind-control-plane
docker events --since "2026-09-27T11:50:00" --until "2026-09-27T12:10:00" \
  --filter container=kind-control-plane
#print config.yaml
cat /var/lib/kubelet/config.yaml | grep -n -E 'nodeIP|address'
#-n -> print each line number
# -E => allow regex mode in order to use | 

#grep all of these from this file
grep -R "172.19.0.2\|172.19.0.3\|172.19.0.4" \
  /etc/kubernetes/manifests \
  /var/lib/kubelet \
  /etc/kubernetes 2>/dev/null | head -100

#find the processes of all of these 
docker exec kind-control-plane crictl ps -a \
  --name kube-apiserver \
  --name konnectivity-server \
  --name etcd

#to restart the kubelet of control-plane
docker exec kind-control-plane systemctl restart kubelet
#to see the status 
docker exec kind-control-plane systemctl status kubelet --no-pager
#to see the nodes
k get nodes
#find the ID of kube-apiserver then stop it in order to allow for etcd to provision it again
docker exec kind-control-plane crictl ps -a | grep kube-apiserver
docker exec kind-control-plane crictl stop <API_CONTAINER_ID>
#to delete pods from the whole system
k delete pods --all -A --grace-period=0 --force
#note: avoid deleting any controller as they are responsible for provioning these pods.
#see some lines from kube-apiserver file
sed -n '45,75p' /etc/kubernetes/manifests/kube-apiserver.yaml


