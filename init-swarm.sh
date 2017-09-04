#!/bin/bash

# todo:
# admin panel: rancher, shipyard-project, swarmpit
# network: Contiv Network Plugin
# proxy: traefic?
# gen cert? and add to secret?
# tls: portaner-tls, registry-tls

vizsgal(){
   if [ -z "$1" ]; then
        echo "Host number not present"
	exit 1
   else
        N=$1
   fi
}


case "$1" in
create)
   vizsgal $2
   for (( i=1; i<=$N; i++ ))
   do
      docker-machine create --driver virtualbox node$i
   done
   ;;
init)
   vizsgal $2
   MANAGGER_IP=$(docker-machine ip node1)
   docker-machine ssh node1 docker swarm init --listen-addr ${MANAGGER_IP} --advertise-addr ${MANAGGER_IP}

#  MANAGER_TOKEN=$(docker-machine ssh node1 docker swarm join-token -q manager)
   WORKER_TOKEN=$(docker-machine ssh node1 docker swarm join-token -q worker)
   for (( i=2; i<=$N; i++ ))
   do
      docker-machine ssh node$i docker swarm join --token ${WORKER_TOKEN} ${MANAGGER_IP}:2377
   done
   ;;
promote)
    vizsgal $2
   for (( i=2; i<=$N; i++ ))
   do
      docker-machine ssh node1 docker node promote node$i
   done
   ;;
weave-net)
    vizsgal $2
   for (( i=1; i<=$N; i++ ))
   do
      docker-machine ssh node$i docker plugin install --grant-all-permissions store/weaveworks/net-plugin:2.0.1
   done
   docker-machine ssh node1 docker network create --driver=store/weaveworks/net-plugin:2.0.1 weavenet
   ;;
portainer)
      docker-machine ssh node1 "sudo mkdir -p /dockerdata/portainer"
      docker-machine ssh node1 "sudo chown -R docker:docker /dockerdata"
      docker-machine ssh node1 "docker service create --name portainer --publish 9000:9000 --constraint 'node.role == manager' --mount type=bind,src=/dockerdata/portainer,dst=/data --mount type=bind,src=//var/run/docker.sock,dst=/var/run/docker.sock portainer/portainer -H unix:///var/run/docker.sock"
      sleet 10
      docker-machine ssh node1 "docker service ls"
   ;;
registry)
   vizsgal $2
   for (( i=1; i<=$N; i++ ))
   do
      docker-machine ssh node$i "sudo mkdir -p /dockerdata/registry"
      docker-machine ssh node$i "sudo chown -R docker:docker /dockerdata"
   done
   docker-machine ssh node1 "docker service create --name registry --mount type=bind,src=/dockerdata/registry,dst=/var/lib/registry -p 5000:5000 --mode global registry:2"
   sleep 10
   docker-machine ssh node1 "docker service ls"
   sleep 10
   docker-machine ssh node1 "docker service ps registry"
   ;;
destroy-swarm)
   vizsgal $2
   for (( i=1; i<=$N; i++ ))
   do
      docker-machine ssh node$i docker swarm leave --force
   done
   ;;
destroy)
   vizsgal $2
   for (( i=1; i<=$N; i++ ))
   do
      docker-machine rm -f node$i
   done
   ;;
*) echo "Usage:  init-swarm.sh <command> <node number>
	init-swarm.sh create|init|weave-net|promote|portainer|registry|destroy-swarm|destroy <node number>"
   ;;
esac
