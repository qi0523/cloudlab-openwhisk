#!/bin/bash

set -x
INSTALL_DIR=/home/cloudlab-openwhisk
HOST_NAME=$(hostname | awk 'BEGIN{FS="."} {print $1}')

# change hostname
sudo hostnamectl set-hostname $HOST_NAME
sudo sed -i "4a 127.0.0.1 $HOST_NAME" /etc/hosts

#role: control-plane

## modify containerd, TODO:
sudo apt install -y apparmor apparmor-utils

## cni plugins TODO:
pushd $INSTALL_DIR/install
wget https://github.com/containernetworking/plugins/releases/download/v1.1.1/cni-plugins-linux-amd64-v1.1.1.tgz
sudo tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.1.1.tgz
popd

## memory.memsw
sudo sed -i 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="cgroup_enable=memory swapaccount=1,/' /etc/default/grub
sudo update-grub