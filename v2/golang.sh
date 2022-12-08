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
echo "export GOROOT=$GOROOT" >> $HOME/.bashrc
echo "export GOPATH=$GOPATH" >> $HOME/.bashrc
echo "export GOBIN=$GOBIN" >> $HOME/.bashrc
echo "export PATH=$GOPATH/bin:$GOBIN:$GOROOT/bin:$PATH" >> $HOME/.bashrc

source $HOME/.bashrc