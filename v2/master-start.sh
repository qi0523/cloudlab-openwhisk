#!/bin/bash

set -x

USER=Zhihao
USER_GROUP=containernetwork
MASTER_PORT=3000
INVOKER_PORT=3001
INSTALL_DIR=/home/cloudlab-openwhisk
HOST_ETH0_IP=$(ifconfig eth0 | awk 'NR==2{print $2}')

#role: control-plane

## modify containerd, TODO:
sudo apt install -y apparmor apparmor-utils

## cni plugins TODO:

#invoker ip array
invoker_ips=()

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

wait_invokers_ip(){
    # $1 == invoker nums
    NUM_REGISTERED=0
    NUM_UNREGISTERED=$(($1-NUM_REGISTERED))
    while [ "$NUM_UNREGISTERED" -ne 0 ]
    do
        sleep 1
        read -r -u${nc[0]} INVOKER_IP
        printf "%s: %s\n" "$(date +"%T.%N")" "read invoker ip: $INVOKER_IP"
        invoker_ips[$NUM_REGISTERED]=$INVOKER_IP
        NUM_REGISTERED=$(($NUM_REGISTERED+1))
        NUM_UNREGISTERED=$(($1-NUM_REGISTERED))
    done
    kill $nc_PID
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
    sudo kubeadm init --apiserver-advertise-address=$HOST_ETH0_IP --pod-network-cidr=10.11.0.0/16 > $INSTALL_DIR/k8s_install.log 2>&1
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

apply_calico() {
    # https://projectcalico.docs.tigera.io/getting-started/kubernetes/helm
    helm repo add projectcalico https://projectcalico.docs.tigera.io/charts > $INSTALL_DIR/calico_install.log 2>&1 
    if [ $? -ne 0 ]; then
       echo "***Error: Error when loading helm calico repo. Log written to $INSTALL_DIR/calico_install.log"
       exit 1
    fi
    printf "%s: %s\n" "$(date +"%T.%N")" "Loaded helm calico repo"

    helm install calico projectcalico/tigera-operator --version v3.22.0 >> $INSTALL_DIR/calico_install.log 2>&1
    if [ $? -ne 0 ]; then
       echo "***Error: Error when installing calico with helm. Log appended to $INSTALL_DIR/calico_install.log"
       exit 1
    fi
    printf "%s: %s\n" "$(date +"%T.%N")" "Applied Calico networking from "

    # wait for calico pods to be in ready state
    printf "%s: %s\n" "$(date +"%T.%N")" "Waiting for calico pods to have status of 'Running': "
    sleep 10
    NUM_PODS=$(kubectl get pods -n calico-system | grep calico | wc -l)
    while [ "$NUM_PODS" -eq 0 ]
    do
        sleep 5
        printf "."
        NUM_PODS=$(kubectl get pods -n calico-system | grep calico | wc -l)
    done
    NUM_RUNNING=$(kubectl get pods -n calico-system | grep " Running" | wc -l)
    NUM_RUNNING=$((NUM_PODS-NUM_RUNNING))
    while [ "$NUM_RUNNING" -ne 0 ]
    do
        sleep 5
        printf "."
        NUM_RUNNING=$(kubectl get pods -n calico-system | grep " Running" | wc -l)
        NUM_RUNNING=$((NUM_PODS-NUM_RUNNING))
    done
    printf "%s: %s\n" "$(date +"%T.%N")" "Calico running!"
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
	sleep 2
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
        sleep 3
        printf "."
        NUM_READY=$(kubectl get nodes | grep " Ready" | wc -l)
        NUM_READY=$(($1-NUM_READY+1))
    done
    printf "%s: %s\n" "$(date +"%T.%N")" "Done!"
}

prepare_for_openwhisk() {
    # Args: 1 = IP, 2 = num nodes, 3 = num invokers, 4 = invoker engine

    git clone https://github.com/apache/openwhisk-deploy-kube $INSTALL_DIR/openwhisk-deploy-kube

    pushd $INSTALL_DIR/openwhisk-deploy-kube
    git pull
    popd

    # Iterate over each node and set the openwhisk role
    # From https://superuser.com/questions/284187/bash-iterating-over-lines-in-a-variable
    NODE_NAMES=$(kubectl get nodes -o name)
    CORE_NODES=$(($2-$3))
    counter=0
    while IFS= read -r line; do
        if [ $counter -lt $CORE_NODES ] ; then
            printf "%s: %s\n" "$(date +"%T.%N")" "Skipped labelling non-invoker node ${line:5}"
            else
                kubectl label nodes ${line:5} openwhisk-role=invoker
                if [ $? -ne 0 ]; then
                    echo "***Error: Failed to set openwhisk role to invoker on ${line:5}."
                    exit -1
                fi
            printf "%s: %s\n" "$(date +"%T.%N")" "Labelled ${line:5} as openwhisk invoker node"
        fi
        counter=$((counter+1))
    done <<< "$NODE_NAMES"
    printf "%s: %s\n" "$(date +"%T.%N")" "Finished labelling nodes."

    kubectl create namespace openwhisk
    if [ $? -ne 0 ]; then
        echo "***Error: Failed to create openwhisk namespace"
        exit 1
    fi
    printf "%s: %s\n" "$(date +"%T.%N")" "Created openwhisk namespace in Kubernetes."

    cp /local/repository/mycluster.yaml $INSTALL_DIR/openwhisk-deploy-kube/mycluster.yaml
    sed -i "s/REPLACE_ME_WITH_IP/$1/g" $INSTALL_DIR/openwhisk-deploy-kube/mycluster.yaml
    sed -i "s/REPLACE_ME_WITH_INVOKER_ENGINE/$4/g" $INSTALL_DIR/openwhisk-deploy-kube/mycluster.yaml
    sed -i "s/REPLACE_ME_WITH_INVOKER_COUNT/$3/g" $INSTALL_DIR/openwhisk-deploy-kube/mycluster.yaml
    sudo chown $USER:$PROFILE_GROUP $INSTALL_DIR/openwhisk-deploy-kube/mycluster.yaml
    sudo chmod -R g+rw $INSTALL_DIR/openwhisk-deploy-kube/mycluster.yaml
    printf "%s: %s\n" "$(date +"%T.%N")" "Updated $INSTALL_DIR/openwhisk-deploy-kube/mycluster.yaml"
    
    if [ $4 == "docker" ] ; then
        if test -d "/mydata"; then
	    sed -i "s/\/var\/lib\/docker\/containers/\/mydata\/docker\/containers/g" $INSTALL_DIR/openwhisk-deploy-kube/helm/openwhisk/templates/_invoker-helpers.tpl
            printf "%s: %s\n" "$(date +"%T.%N")" "Updated dockerrootdir to /mydata/docker/containers in $INSTALL_DIR/openwhisk-deploy-kube/helm/openwhisk/templates/_invoker-helpers.tpl"
        fi
    fi
}


deploy_openwhisk() {
    # Takes cluster IP as argument to set up wskprops files.

    # Deploy openwhisk via helm
    printf "%s: %s\n" "$(date +"%T.%N")" "About to deploy OpenWhisk via Helm... "
    cd $INSTALL_DIR/openwhisk-deploy-kube
    helm install owdev ./helm/openwhisk -n openwhisk -f mycluster.yaml > $INSTALL_DIR/ow_install.log 2>&1 
    if [ $? -eq 0 ]; then
        printf "%s: %s\n" "$(date +"%T.%N")" "Ran helm command to deploy OpenWhisk"
    else
        echo ""
        echo "***Error: Helm install error. Please check $INSTALL_DIR/ow_install.log."
        exit 1
    fi
    cd $INSTALL_DIR

    # Monitor pods until openwhisk is fully deployed
    kubectl get pods -n openwhisk
    printf "%s: %s\n" "$(date +"%T.%N")" "Waiting for OpenWhisk to complete deploying (this can take several minutes): "
    DEPLOY_COMPLETE=$(kubectl get pods -n openwhisk | grep owdev-install-packages | grep Completed | wc -l)
    while [ "$DEPLOY_COMPLETE" -ne 1 ]
    do
        sleep 2
        DEPLOY_COMPLETE=$(kubectl get pods -n openwhisk | grep owdev-install-packages | grep Completed | wc -l)
    done
    printf "%s: %s\n" "$(date +"%T.%N")" "OpenWhisk deployed!"
    
    # Set up wsk properties for all users
    for FILE in /users/*; do
        CURRENT_USER=${FILE##*/}
        echo -e "
	APIHOST=$1:31001
	AUTH=23bc46b1-71f6-4ed5-8c54-816aa4f8c502:123zO3xZCLrMN6v2BKK1dXYFpXlPkccOFqm12CdAsMgRU4VrNZ9lyGVCGuMDGIwP
	" | sudo tee /users/$CURRENT_USER/.wskprops
	sudo chown $CURRENT_USER:$PROFILE_GROUP /users/$CURRENT_USER/.wskprops
    done
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

coproc nc { nc -l $HOST_ETH0_IP $MASTER_PORT; }

wait_invokers_ip $1

setup_primary $HOST_ETH0_IP

# Apply calico networking
apply_calico

# Coordinate master to add nodes to the kubernetes cluster
# Argument is number of nodes
add_cluster_nodes $1

# Exit early if we don't need to deploy OpenWhisk
if [ "$2" = "false" ]; then
    printf "%s: %s\n" "$(date +"%T.%N")" "Don't need to deploy Openwhisk!"
    exit 0
fi

# Prepare cluster to deploy OpenWhisk: takes IP, num nodes, invoker num, and invoker engine
prepare_for_openwhisk $2 $3 $6 $7

# Deploy OpenWhisk via Helm
# Takes cluster IP
deploy_openwhisk $2

printf "%s: %s\n" "$(date +"%T.%N")" "Profile setup completed!"