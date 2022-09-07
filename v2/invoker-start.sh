#!/bin/bash

set -x

USER=Zhihao
USER_GROUP=containernetwork
MASTER_PORT=3000
INVOKER_PORT=3001
INSTALL_DIR=/home/cloudlab-openwhisk
HOST_ETH0_IP=$(ifconfig eth0 | awk 'NR==2{print $2}')

## modify containerd, TODO:


disable_swap() {
    # Turn swap off and comment out swap line in /etc/fstab
    sudo swapoff -a
    if [ $? -eq 0 ]; then   
        printf "%s: %s\n" "$(date +"%T.%N")" "Turned off swap"
    else
        echo "***Error: Failed to turn off swap, which is necessary for Kubernetes"
        exit -1
    fi
    sudo sed -i 's/UUID=.*swap/# &/' /etc/fstab
}

send_ip_to_master() {
    # $1 == master ip
    printf "%s: %s\n" "$(date +"%T.%N")" "host ip is: $HOST_ETH0_IP"
    sleep 2
    printf "%s: %s\n" "$(date +"%T.%N")" "Send eth0 ip to master node"
    echo $HOST_ETH0_IP
    exec 3<>/dev/tcp/$1/$MASTER_PORT
    echo $HOST_ETH0_IP 1>&3
    exec 3<&-
}

wait_join_k8s() {
    printf "%s: %s\n" "$(date +"%T.%N")" "nc pid is: $nc_PID"
    kill $nc_PID
}

setup_invoker() {
    # $1 == master ip
    #1. send host ip to master.
    send_ip_to_master $1
    #2. wait to join in k8s cluster.
    wait_join_k8s
}

# Start by recording the arguments
printf "%s: args=(" "$(date +"%T.%N")"
for var in "$@"
do
    printf "'%s' " "$var"
done
printf ")\n"

# Kubernetes does not support swap, so we must disable it
disable_swap

# Use mountpoint (if it exists) to set up additional docker image storage
if test -d "/mydata"; then
    configure_docker_storage
fi

# Use second argument (node IP) to replace filler in kubeadm configuration
sudo sed -i "s/REPLACE_ME_WITH_IP/$HOST_ETH0_IP/g" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf


# listen INVOKER_PORT

coproc nc {nc -l $HOST_ETH0_IP $INVOKER_PORT; }

setup_invoker $1

exit 0