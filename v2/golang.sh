#!/bin/bash

set -x

INSTALL_DIR=/home/cloudlab-openwhisk

cd $INSTALL_DIR/install
wget https://golang.google.cn/dl/go1.19.1.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.19.1.linux-amd64.tar.gz

mkdir -p $HOME/go
cd $HOME/go
mkdir bin src pkg

GOROOT="/usr/local/go"
GOPATH="$HOME/go"
GOBIN="$GOPATH/bin"
echo "export GOROOT=$GOROOT" >> .bashrc
echo "export GOPATH=$GOPATH" >> .bashrc
echo "export GOBIN=$GOBIN" >> .bashrc
echo "export PATH=$GOPATH/bin:$GOBIN:$GOROOT/bin:$PATH" >> .bashrc

source .bashrc