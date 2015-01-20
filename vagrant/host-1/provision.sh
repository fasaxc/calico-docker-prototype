#!/bin/bash

set -x
set -e

IP1=192.168.50.2
HOST1=calico-1
IP2=192.168.50.3
HOST2=calico-2
DEMO_ROOT=/opt/demo
PLUGIN_ROOT=/opt/plugin

echo "$IP2 $HOST2" >> /etc/hosts

apt-add-repository -y ppa:james-page/docker
apt-get update
apt-get install -y docker.io ipset git

mkdir -p $DEMO_ROOT
cd $DEMO_ROOT
git clone https://github.com/Metaswitch/calico-docker-prototype.git .

cd $DEMO_ROOT

for file in $DEMO_ROOT/felix.txt $DEMO_ROOT/felix/Dockerfile $DEMO_ROOT/bird/Dockerfile;
do
  sed -i "s/IP1/$IP1/" $file
  sed -i "s/IP2/$IP2/" $file 
  sed -i "s/HOST1/$HOST1/" $file
  sed -i "s/HOST2/$HOST2/" $file
done

docker build -t "calico:bird" $DEMO_ROOT/bird 
docker build -t "calico:plugin" $DEMO_ROOT/plugin
docker build -t "calico:felix" $DEMO_ROOT/felix
docker build -t "calico:util" $DEMO_ROOT/util

modprobe ip6_tables
modprobe xt_set
mkdir -p /var/log/calico
mkdir -p /var/run/netns
mkdir -p $PLUGIN_ROOT/data

cp $DEMO_ROOT/felix.txt $PLUGIN_ROOT/data

docker run -d -v /var/log/bird:/var/log/bird \
           --privileged=true \
           --name="bird" \
           --net=host \
           --restart=always \
           -t calico:bird \
           /usr/bin/run_bird bird1.conf
docker run -d -v /var/log/calico:/var/log/calico \
           --privileged=true \
           --name="plugin-net" \
           --net=host \
           --restart=always \
           -v $PLUGIN_ROOT:$PLUGIN_ROOT \
           calico:plugin \
           python /opt/scripts/plugin.py network
docker run -d -v /var/log/calico:/var/log/calico \
           --privileged=true \
           --name="plugin-ep" \
           --net=host \
           --restart=always \
           -v $PLUGIN_ROOT:$PLUGIN_ROOT calico:plugin \
           python /opt/scripts/plugin.py ep

docker run -d -v /var/log/calico:/var/log/calico \
           --privileged=true \
           --name="felix" \
           --net=host \
           --restart=always \
           -t calico:felix calico-felix \
           --config-file=/etc/calico/felix.cfg
docker run -d -v /var/log/calico:/var/log/calico \
           --privileged=true \
           --name="acl-mgr" \
           --net=host \
           --restart=always \
           -t calico:felix calico-acl-manager \
           --config-file=/etc/calico/acl_manager.cfg


