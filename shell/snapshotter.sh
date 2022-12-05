#!/bin/bash

set -x

INSTALL_DIR=/home/cloudlab-openwhisk

pushd $INSTALL_DIR/install
wget https://github.com/containerd/stargz-snapshotter/releases/download/v0.12.1/stargz-snapshotter-v0.12.1-linux-amd64.tar.gz
sudo tar Cxzvf /usr/local/bin stargz-snapshotter-v0.12.1-linux-amd64.tar.gz
popd

sudo sed -i 's/snapshotter = "overlayfs"/snapshotter = "stargz"/g' /etc/containerd/config.toml
sudo sed -i 's/disable_snapshot_annotations = true/disable_snapshot_annotations = false/g' /etc/containerd/config.toml
#190
sudo sed -i '189a\  [proxy_plugins.stargz]' /etc/containerd/config.toml
sudo sed -i '190a\    type = "snapshot"' /etc/containerd/config.toml
sudo sed -i '191a\    address = "/run/containerd-stargz-grpc/containerd-stargz-grpc.sock"' /etc/containerd/config.toml

sudo apt-get install fuse
sudo modprobe fuse

sudo wget -O /etc/systemd/system/stargz-snapshotter.service https://raw.githubusercontent.com/containerd/stargz-snapshotter/main/script/config/etc/systemd/system/stargz-snapshotter.service
sudo systemctl enable --now stargz-snapshotter
sudo systemctl restart containerd