#!/bin/bash

set -x

INSTALL_DIR=/home/cloudlab-openwhisk

pushd $INSTALL_DIR/install
wget https://golang.google.cn/dl/go1.19.1.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.19.1.linux-amd64.tar.gz
popd

mkdir -p $HOME/code/go
pushd $HOME/code/go
mkdir bin src pkg
popd
GOROOT="/usr/local/go"
GOPATH="$HOME/code/go"
GOBIN="$GOPATH/bin"
echo "export GOROOT=$GOROOT" >> .bashrc
echo "export GOPATH=$GOPATH" >> .bashrc
echo "export GOBIN=$GOBIN" >> .bashrc
echo "export PATH=$GOPATH/bin:$GOBIN:$GOROOT/bin:$PATH" >> .bashrc

source .bashrc