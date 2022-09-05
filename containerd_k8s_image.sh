#!/bin/bash
set -x

####### Forwarding IPv4 and letting iptables see bridged traffic
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system

###### constants
USER=Zhihao
USER_GROUP=containernetwork
BASE_DIR=/home/cloudlab-openwhisk
INSTALL_DIR=$BASE_DIR/install
K8S_VERSION=1.24.0-00


## mkdir base dir
sudo mkdir $BASE_DIR
sudo chown -R $USER:$USER_GROUP $BASE_DIR

mkdir -p $INSTALL_DIR
pushd $INSTALL_DIR

##### install containerd-1.5.11
wget https://github.com/containerd/containerd/releases/download/v1.5.11/containerd-1.5.11-linux-amd64.tar.gz
wget https://github.com/opencontainers/runc/releases/download/v1.1.4/runc.amd64
wget https://github.com/containernetworking/plugins/releases/download/v1.1.1/cni-plugins-linux-amd64-v1.1.1.tgz
wget https://github.com/containerd/nerdctl/releases/download/v0.22.2/nerdctl-0.22.2-linux-amd64.tar.gz
wget https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
wget https://github.com/rootless-containers/rootlesskit/releases/download/v1.0.1/rootlesskit-$(uname -m).tar.gz
wget https://github.com/moby/buildkit/releases/download/v0.10.4/buildkit-v0.10.4.linux-amd64.tar.gz

sudo tar Cxzvf /usr/local containerd-1.5.11-linux-amd64.tar.gz
sudo mkdir -p /usr/local/lib/systemd/system
sudo mv containerd.service /usr/local/lib/systemd/system/

sudo systemctl daemon-reload
sudo systemctl enable --now containerd

sudo install -m 755 runc.amd64 /usr/local/sbin/runc

sudo mkdir -p /opt/cni/bin
sudo tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.1.1.tgz

############################ containerd config.toml
sudo mkdir -p /etc/containerd/
cat <<EOF | sudo tee /etc/containerd/config.toml
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
    SystemdCgroup = true
EOF
sudo systemctl restart containerd

sudo tar Cxzvvf /usr/local/bin nerdctl-0.22.2-linux-amd64.tar.gz

# rootless
sudo apt-get update
sudo apt install uidmap slirp4netns

#RootlessKit
sudo tar Cxzvf /usr/local/bin rootlesskit-x86_64.tar.gz

#BuildKit
sudo tar Cxzvf /usr/local/ buildkit-v0.10.4.linux-amd64.tar.gz

sudo buildkitd --oci-worker=false --containerd-worker=true &

# enable cgruop v2
sudo sed -i 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="systemd.unified_cgroup_hierarchy=1,/' /etc/default/grub
sudo update-grub

sudo mkdir -p /etc/systemd/system/user@.service.d

cat <<EOF | sudo tee /etc/systemd/system/user@.service.d/delegate.conf
[Service]
Delegate=cpu cpuset io memory pids
EOF

sudo systemctl daemon-reload

sudo sed -i '120c \\tcontrollers="/etc/systemd/system/user@.service.d/delegate.conf"' /usr/local/bin/containerd-rootless-setuptool.sh

/usr/local/bin/containerd-rootless-setuptool.sh check
/usr/local/bin/containerd-rootless-setuptool.sh install


##### install kubernetes
sudo curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
echo 'deb http://apt.kubernetes.io/ kubernetes-xenial main' | sudo tee -a /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet=$K8S_VERSION kubeadm=$K8S_VERSION kubectl=$K8S_VERSION
sudo apt-mark hold kubelet kubeadm kubectl

# Set to use private IP
sudo sed -i "s/KUBELET_CONFIG_ARGS=--config=\/var\/lib\/kubelet\/config\.yaml/KUBELET_CONFIG_ARGS=--config=\/var\/lib\/kubelet\/config\.yaml --node-ip=REPLACE_ME_WITH_IP/g" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

######## kubelet config.yaml
sudo mkdir -p /var/lib/kubelet/
cat <<EOF | sudo tee /var/lib/kubelet/config.yaml
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
cgroupDriver: systemd
EOF

popd

rm -rf $INSTALL_DIR/*