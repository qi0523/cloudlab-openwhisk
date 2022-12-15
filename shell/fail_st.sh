#!/bin/bash

set -x

USER=Zhihao
USER_GROUP=containernetwork
MASTER_PORT=3000
INVOKER_PORT=3001
INSTALL_DIR=/home/cloudlab-openwhisk
HOST_ETH0_IP=$(ifconfig eth0 | awk 'NR==2{print $2}')
HOST_NAME=$(hostname | awk 'BEGIN{FS="."} {print $1}')


#invoker ip array
invoker_ips=()

wait_invokers_ip(){
    # $1 == invoker nums
    NUM_REGISTERED=0
    NUM_UNREGISTERED=$(($1-NUM_REGISTERED))
    while [ "$NUM_UNREGISTERED" -ne 0 ]
    do
        sleep 0.5
        if [ -z "$nc_PID" ]
        then
            printf "%s: %s\n" "$(date +"%T.%N")" "Restarting listener via netcat..."
            coproc nc { nc -l $HOST_ETH0_IP $MASTER_PORT; }
        fi
        read -r -u${nc[0]} INVOKER_IP
        printf "%s: %s\n" "$(date +"%T.%N")" "read invoker ip: $INVOKER_IP"
        invoker_ips[$NUM_REGISTERED]=$INVOKER_IP
        NUM_REGISTERED=$(($NUM_REGISTERED+1))
        NUM_UNREGISTERED=$(($1-NUM_REGISTERED))
    done
}

wait_ips(){
    while [ ! -f "/home/cloudlab-openwhisk/ok.txt" ]
    do
        sleep 30
    done

    ips=$(cat /home/cloudlab-openwhisk/ips.txt)
    invoker_ips=($ips)
}

setup_primary() {

    # Download and install helm
    pushd $INSTALL_DIR/install
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
    chmod 744 get_helm.sh
    sudo ./get_helm.sh
    popd

    # initialize k8 primary node
    printf "%s: %s\n" "$(date +"%T.%N")" "Starting Kubernetes... (this can take several minutes)... "
    sudo kubeadm init --apiserver-advertise-address=$HOST_ETH0_IP --pod-network-cidr=10.244.0.0/16 > $INSTALL_DIR/k8s_install.log 2>&1
    if [ $? -eq 0 ]; then
        printf "%s: %s\n" "$(date +"%T.%N")" "Done! Output in $INSTALL_DIR/k8s_install.log"
    else
        echo ""
        echo "***Error: Error when running kubeadm init command. Check log found in $INSTALL_DIR/k8s_install.log."
        exit 1
    fi

    # Set up kubectl for Zhihao users TODO: completed
    sudo mkdir /users/$USER/.kube
    sudo cp /etc/kubernetes/admin.conf /users/$USER/.kube/config
    sudo chown -R $USER:$USER_GROUP /users/$USER/.kube
	printf "%s: %s\n" "$(date +"%T.%N")" "set /users/$USER/.kube to $USER:$USER_GROUP!"
	ls -lah /users/$USER/.kube
    printf "%s: %s\n" "$(date +"%T.%N")" "Done!"

    ### TODO: remove taint master, completed
    kubectl taint nodes --all node-role.kubernetes.io/master-
    kubectl taint nodes --all node-role.kubernetes.io/control-plane-
}

apply_flannel() {
    # flannel
    pushd $INSTALL_DIR/install
    wget https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
    kubectl apply -f kube-flannel.yml >> $INSTALL_DIR/flannel_install.log 2>&1
    popd
    # https://projectcalico.docs.tigera.io/getting-started/kubernetes/helm
    printf "%s: %s\n" "$(date +"%T.%N")" "Loaded flannel pods"
    if [ $? -ne 0 ]; then
       echo "***Error: Error when installing flannel. Log appended to $INSTALL_DIR/flannel_install.log"
       exit 1
    fi
    printf "%s: %s\n" "$(date +"%T.%N")" "Applied flannel networking from "

    # wait for flannel pods to be in ready state
    printf "%s: %s\n" "$(date +"%T.%N")" "Waiting for flannel pods to have status of 'Running': "
    sleep 10
    NUM_PODS=$(kubectl get pods -A | grep flannel | wc -l)
    while [ "$NUM_PODS" -eq 0 ]
    do
        sleep 5
        printf "."
        NUM_PODS=$(kubectl get pods -A | grep flannel | wc -l)
    done
    NUM_RUNNING=$(kubectl get pods -A | grep flannel | grep " Running" | wc -l)
    NUM_RUNNING=$((NUM_PODS-NUM_RUNNING))
    while [ "$NUM_RUNNING" -ne 0 ]
    do
        sleep 5
        printf "."
        NUM_RUNNING=$(kubectl get pods -A | grep flannel | grep " Running" | wc -l)
        NUM_RUNNING=$((NUM_PODS-NUM_RUNNING))
    done
    printf "%s: %s\n" "$(date +"%T.%N")" "flannel running!"
}

add_cluster_nodes() { ## $1 == 1

    # awk -v line=$(awk '{if($1=="kubeadm")print NR}' k8s.log) '{if(NR>=line && NR<line+2){print $0}}' k8s.log
    REMOTE_CMD=$(awk -v line=$(awk '{if($1=="kubeadm")print NR}' $INSTALL_DIR/k8s_install.log) '{if(NR>=line && NR<line+2){print $0}}' $INSTALL_DIR/k8s_install.log)
    printf "%s: %s\n" "$(date +"%T.%N")" "Remote command is: $REMOTE_CMD"

    NUM_REGISTERED=$(kubectl get nodes | wc -l)
    NUM_REGISTERED=$(($1-NUM_REGISTERED+2))
    counter=0
    while [ "$NUM_REGISTERED" -ne 0 ]
    do 
	sleep 3
        printf "%s: %s\n" "$(date +"%T.%N")" "Registering nodes, attempt #$counter, registered=$NUM_REGISTERED"
        for (( i=0; i<$1; i++ ))
        do
            INVOKER_IP=${invoker_ips[$i]}
            echo $INVOKER_IP
            exec 3<>/dev/tcp/$INVOKER_IP/$INVOKER_PORT
            echo $REMOTE_CMD 1>&3
            exec 3<&-
        done
	counter=$((counter+1))
        NUM_REGISTERED=$(kubectl get nodes | wc -l)
        NUM_REGISTERED=$(($1-NUM_REGISTERED+2)) 
    done

    printf "%s: %s\n" "$(date +"%T.%N")" "Waiting for all nodes to have status of 'Ready': "
    NUM_READY=$(kubectl get nodes | grep " Ready" | wc -l)
    NUM_READY=$(($1-NUM_READY+1))
    while [ "$NUM_READY" -ne 0 ]
    do
        sleep 5
        printf "."
        NUM_READY=$(kubectl get nodes | grep " Ready" | wc -l)
        NUM_READY=$(($1-NUM_READY+1))
    done
    printf "%s: %s\n" "$(date +"%T.%N")" "Done!"
}

prepare_for_openwhisk() {
    # Args: 1 = IP, 2 = num nodes, 3 = num invokers, 4 = invoker engine

    # TODO: nfs-server
    sudo apt-get update
    sudo apt install nfs-kernel-server -y
    NFS_DIR=/proj/containernetwork-PG0/data/nfs
    sudo mkdir -p $NFS_DIR
    sudo chmod 777 $NFS_DIR

    echo "$NFS_DIR *(fsid=0,rw,sync,no_root_squash)" | sudo tee /etc/exports
    sudo systemctl restart nfs-server
    if [ "$?" -ne 0 ]; then
        echo "nfs server failed..."
        exit 1
    fi

    # nfs-subdir-external-provisioner
    helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
    helm install nfs-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
        --set nfs.server=$HOST_ETH0_IP \
        --set nfs.path=$NFS_DIR \
        --set storageClass.defaultClass=true
    if [ "$?" -ne 0 ]; then
        echo "nfs provisioner failed..."
        exit 1
    fi

    # k8s sc
    nfs_client_running_num=$(kubectl get pods -A | grep nfs-provisioner | grep Running | wc -l)
    while [ "$nfs_client_running_num" -eq 0 ]
    do
        sleep 3
        echo "wait for nfs_provisioner_running...."
        nfs_client_running_num=$(kubectl get pods -A | grep nfs-provisioner | grep Running | wc -l)
    done

    #label nodes=core 
    CONTROLLER_NODE=$(kubectl get nodes | grep master | awk '{print $1}')
    kubectl label nodes ${CONTROLLER_NODE} openwhisk-role=core
    # label nodes=invoker
    INVOKER_NODES=$(kubectl get nodes | grep ow | awk '{print $1}')
    while IFS= read -r line; do
        kubectl label nodes ${line} openwhisk-role=invoker
        if [ $? -ne 0 ]; then
            echo "***Error: Failed to set openwhisk role to invoker on ${line:5}."
            exit -1
        fi
        printf "%s: %s\n" "$(date +"%T.%N")" "Labelled ${line} as openwhisk invoker node"
    done <<< "$INVOKER_NODES"
    printf "%s: %s\n" "$(date +"%T.%N")" "Finished labelling nodes."

    # git clone qi0523/openwhisk-deploy-bue
    git clone https://github.com/qi0523/openwhisk-deploy-kube $INSTALL_DIR/openwhisk-deploy-kube

    pushd $INSTALL_DIR/openwhisk-deploy-kube
    sed -i "s/REPLACE_ME_WITH_IP/$HOST_ETH0_IP/g" mycluster.yaml
    popd
    kubectl create namespace openwhisk
    if [ $? -ne 0 ]; then
        echo "***Error: Failed to create openwhisk namespace"
        exit 1
    fi
    printf "%s: %s\n" "$(date +"%T.%N")" "Created openwhisk namespace in Kubernetes."

    pushd $INSTALL_DIR/install
    # Download and install the OpenWhisk CLI
    wget https://github.com/apache/openwhisk-cli/releases/download/latest/OpenWhisk_CLI-latest-linux-386.tgz
    sudo tar -xzvf OpenWhisk_CLI-latest-linux-386.tgz -C /usr/local/bin wsk

    # Set up wsk properties for all users
        echo -e "
	APIHOST=$HOST_ETH0_IP:31001
	AUTH=23bc46b1-71f6-4ed5-8c54-816aa4f8c502:123zO3xZCLrMN6v2BKK1dXYFpXlPkccOFqm12CdAsMgRU4VrNZ9lyGVCGuMDGIwP
	" | sudo tee /users/$USER/.wskprops
	sudo chown $USER:$USER_GROUP /users/$USER/.wskprops
    popd
}


deploy_openwhisk() {
    # Takes cluster IP as argument to set up wskprops files.

    # Deploy openwhisk via helm
    printf "%s: %s\n" "$(date +"%T.%N")" "About to deploy OpenWhisk via Helm... "
    pushd $INSTALL_DIR/openwhisk-deploy-kube
    helm install owdev ./helm/openwhisk -n openwhisk -f mycluster.yaml > $INSTALL_DIR/ow_install.log 2>&1 
    if [ $? -eq 0 ]; then
        printf "%s: %s\n" "$(date +"%T.%N")" "Ran helm command to deploy OpenWhisk"
    else
        echo ""
        echo "***Error: Helm install error. Please check $INSTALL_DIR/ow_install.log."
        exit 1
    fi

    # Monitor pods until openwhisk is fully deployed
    kubectl get pods -n openwhisk
    printf "%s: %s\n" "$(date +"%T.%N")" "Waiting for OpenWhisk to complete deploying (this can take several minutes): "
    DEPLOY_COMPLETE=$(kubectl get pods -n openwhisk | grep owdev-install-packages | grep Completed | wc -l)
    while [ "$DEPLOY_COMPLETE" -ne 1 ]
    do
        sleep 10
        DEPLOY_COMPLETE=$(kubectl get pods -n openwhisk | grep owdev-install-packages | grep Completed | wc -l)
    done
    printf "%s: %s\n" "$(date +"%T.%N")" "OpenWhisk deployed!"
    popd
}

# Start by recording the arguments
printf "%s: args=(" "$(date +"%T.%N")"
for var in "$@"
do
    printf "'%s' " "$var"
done
printf ")\n"


python server.py $1 $HOST_ETH0_IP &

wait_ips

setup_primary $HOST_ETH0_IP

# Apply flannel networking
apply_flannel

# Coordinate master to add nodes to the kubernetes cluster
# Argument is number of nodes
add_cluster_nodes $1

# Exit early if we don't need to deploy OpenWhisk
# if [ "$2" = "false" ]; then
#     printf "%s: %s\n" "$(date +"%T.%N")" "Don't need to deploy Openwhisk!"
#     exit 0
# fi

# Prepare cluster to deploy OpenWhisk: takes IP, num nodes, invoker num, and invoker engine
prepare_for_openwhisk

# Deploy OpenWhisk via Helm
# Takes cluster IP
#deploy_openwhisk $HOST_ETH0_IP

printf "%s: %s\n" "$(date +"%T.%N")" "Profile setup completed!"