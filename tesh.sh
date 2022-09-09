sudo mkdir -p $(df -h | grep proj | awk '{print $6}')/data/nfs
sudo chmod 777 $(df -h | grep proj | awk '{print $6}')/data/nfs


https://raw.githubusercontent.com/kubernetes-retired/external-storage/master/nfs-client/deploy/rbac.yaml

https://raw.githubusercontent.com/kubernetes-retired/external-storage/master/nfs-client/deploy/class.yaml

https://raw.githubusercontent.com/kubernetes-retired/external-storage/master/nfs-client/deploy/deployment.yaml