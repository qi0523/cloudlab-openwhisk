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
K8S_VERSION=1.24.2-00


## mkdir base dir
sudo mkdir $BASE_DIR
sudo chown -R $USER:$USER_GROUP $BASE_DIR

mkdir -p $INSTALL_DIR
pushd $INSTALL_DIR

##### install containerd-1.5.11
wget https://github.com/qi0523/containerd/releases/download/v1.6.9/containerd-1.6.9-linux-amd64.tar.gz
wget https://github.com/opencontainers/runc/releases/download/v1.1.4/runc.amd64
wget https://github.com/containernetworking/plugins/releases/download/v1.1.1/cni-plugins-linux-amd64-v1.1.1.tgz
wget https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
wget https://github.com/qi0523/nerdctl/releases/download/v0.23.3/nerdctl-0.23.3-linux-amd64.tar.gz

sudo tar Cxzvf /usr/local containerd-1.6.9-linux-amd64.tar.gz
sudo mkdir -p /usr/local/lib/systemd/system
cat containerd.service | sudo tee /usr/local/lib/systemd/system/containerd.service

sudo systemctl daemon-reload
sudo systemctl enable --now containerd

sudo install -m 755 runc.amd64 /usr/local/sbin/runc

#runc /sys/fs/cgroup/memory/memory.memsw
sudo sed -i 's/GRUB_CMDLINE_LINUX=".*"/GRUB_CMDLINE_LINUX="cgroup_enable=memory swapaccount=1"/' /etc/default/grub
sudo update-grub

#cni-plugin
sudo mkdir -p /opt/cni/bin
sudo tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.1.1.tgz

#nerdctl
sudo tar -xvzf nerdctl-0.23.3-linux-amd64.tar.gz -C /usr/bin nerdctl
sudo mkdir -p /var/lib/nerdctl

############################ containerd config.toml
sudo mkdir -p /etc/containerd/
containerd config default | sudo tee /etc/containerd/config.toml
#sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd


##### install kubernetes
sudo curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
echo 'deb http://apt.kubernetes.io/ kubernetes-xenial main' | sudo tee -a /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet=$K8S_VERSION kubeadm=$K8S_VERSION kubectl=$K8S_VERSION
sudo apt-mark hold kubelet kubeadm kubectl

# Set to use private IP
sudo sed -i "s/KUBELET_CONFIG_ARGS=--config=\/var\/lib\/kubelet\/config\.yaml/KUBELET_CONFIG_ARGS=--config=\/var\/lib\/kubelet\/config\.yaml --node-ip=REPLACE_ME_WITH_IP/g" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
sudo sed -i '4a Environment="cgroup-driver=systemd/cgroup-driver=cgroupfs"' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

######## kubelet config.yaml
sudo mkdir -p /var/lib/kubelet/
cat <<EOF | sudo tee /var/lib/kubelet/config.yaml
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
imageGCHighThresholdPercent: 100
EOF

##### install distribution
wget https://github.com/qi0523/distribution-agent/releases/download/v1.1.1/distribution-agent-1.1.1.tar.gz
sudo tar Cxzvf /usr/local/bin distribution-agent-1.1.1.tar.gz

##### install 
git clone https://github.com/magnific0/wondershaper.git
cd wondershaper
sudo make install

popd

rm -rf $INSTALL_DIR/*