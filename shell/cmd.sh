sudo wondershaper -a eth0 -d 5242880 -u 5242880

sudo nerdctl --insecure-registry=true pull --unpack=false 172.17.94.2:30000/openwhisk/action-nodejs-v8:1.20.0
sudo nerdctl rmi 172.17.94.2:30000/openwhisk/action-nodejs-v8:1.20.0

bash ./st.sh 3 > /home/cloudlab-openwhisk/start.log 2>&1

helm install owdev ./helm/openwhisk -n openwhisk -f mycluster.yaml

sudo /usr/local/etc/emulab/rc/rc.storage fullreset
sudo /usr/local/etc/emulab/rc/rc.storage boot

sudo sed -i "17a evictionHard:" /var/lib/kubelet/config.yaml
sudo sed -i '18a \  nodefs.available: "0%"' /var/lib/kubelet/config.yaml
sudo sed -i '19a \  imagefs.available: "0%"' /var/lib/kubelet/config.yaml
sudo sed -i "28a imageGCHighThresholdPercent: 100" /var/lib/kubelet/config.yaml