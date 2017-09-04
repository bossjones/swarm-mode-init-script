#!/bin/bash

# todo:
# admin panel: rancher, shipyard-project, swarmpit
# network: Contiv Network Plugin
# proxy: traefic-ssl?
## ssl: portainer-ssl, registry-ssl
# glusterFS ??

test(){
   if [ -z "$1" ]; then
        echo "Host number not present"
	exit 1
   else
        N=$1
   fi
}

certgen(){
rm -rf ./certs
mkdir ./certs
export PASSPHRASE=$(head -c 500 /dev/urandom | tr -dc a-z0-9A-Z | head -c 128; echo)
export DOMAIN=$1

subj="
C=HU
ST=Pest
O=My Company
localityName=Budapest
commonName=$DOMAIN
organizationalUnitName=OU
emailAddress=root@$DOMAIN
"

openssl genrsa -des3 -out certs/$DOMAIN.key -passout env:PASSPHRASE 2048

openssl req \
    -new \
    -batch \
    -subj "$(echo -n "$subj" | tr "\n" "/")" \
    -key certs/$DOMAIN.key \
    -out certs/$DOMAIN.csr \
-passin env:PASSPHRASE

cp certs/$DOMAIN.key certs/$DOMAIN.key.org

openssl rsa -in certs/$DOMAIN.key.org -out certs/$DOMAIN.key -passin env:PASSPHRASE

openssl x509 -req -days 3650 -in certs/$DOMAIN.csr -signkey certs/$DOMAIN.key -out certs/$DOMAIN.crt
}

certcopy(){
  docker-machine ssh node1 "rm -rf /dockerdata/certs"
  docker-machine ssh node1 "sudo mkdir -p /dockerdata"
  docker-machine ssh node1 "sudo chown -R docker:docker /dockerdata"
  echo "---------------SCP----------------"
  docker-machine scp -r ./certs node1:/dockerdata/
  echo "---------------ls-----------------"
  docker-machine ssh node1 "ls /dockerdata/certs/"
  echo "---------------END----------------"
  # cahck lock file?
  docker-machine ssh node1 docker secret create ${1}.crt /dockerdata/certs/${1}.crt
  docker-machine ssh node1 docker secret create ${1}.key /dockerdata/certs/${1}.key
  docker-machine ssh node1 "rm -rf /dockerdata/certs"
  docker-machine ssh node1 touch /dockerdata/${1}.lock
}

traefic(){
  docker-machine ssh node1 "docker network create --driver=overlay traefik-net"
  docker-machine ssh node1 "docker service create \
  --name traefik \
  --mode global \
  --publish 80:80 --publish 8080:8080 \
  --mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock \
  --network traefik-net \
  traefik:v1.1.0-rc1 \
  --docker \
  --docker.swarmmode \
  --docker.domain=swarm.mydomain.lan \
  --docker.watch \
  --logLevel=DEBUG \
  --web"
}

test-app(){
  docker service create \
  --name whoami \
  --network traefik-net \
  --label traefik.port=80 \
  --label traefik.frontend.rule=Host:whoami.mydomain.lan \
  emilevauge/whoami

# to hostfile:
# node1-IP whoami.mydomain.lan
}


#--------------------------------------------------------------------------------------------------------------

case "$1" in
create)
   test $2
   for (( i=1; i<=$N; i++ ))
   do
      docker-machine create --driver virtualbox node$i
   done
   ;;
init)
   test $2
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
    test $2
   for (( i=2; i<=$N; i++ ))
   do
      docker-machine ssh node1 docker node promote node$i
   done
   ;;
weave-net)
    test $2
   for (( i=1; i<=$N; i++ ))
   do
      docker-machine ssh node$i docker plugin install --grant-all-permissions store/weaveworks/net-plugin:2.0.1
   done
   docker-machine ssh node1 docker network create --driver=store/weaveworks/net-plugin:2.0.1 weavenet
   ;;
portainer)
      docker-machine ssh node1 "sudo mkdir -p /dockerdata/portainer"
      docker-machine ssh node1 "sudo chown -R docker:docker /dockerdata"
      docker-machine ssh node1 docker service rm portainer > /dev/null
      docker-machine ssh node1 docker service rm portainer-ssl > /dev/null
      docker-machine ssh node1 "docker service create --name portainer \
                                --publish 9000:9000 \
                                --constraint 'node.role == manager' \
                                --mount type=bind,src=/dockerdata/portainer,dst=/data \
                                --mount type=bind,src=//var/run/docker.sock,dst=/var/run/docker.sock \
                                portainer/portainer -H unix:///var/run/docker.sock"
      sleet 10
      docker-machine ssh node1 "docker service ls"
   ;;
registry)
   test $2
   for (( i=1; i<=$N; i++ ))
   do
      docker-machine ssh node$i "sudo mkdir -p /dockerdata/registry"
      docker-machine ssh node$i "sudo chown -R docker:docker /dockerdata"
   done
   docker-machine ssh node1 "docker service create --name registry \
                             --mount type=bind,src=/dockerdata/registry,dst=/var/lib/registry \
                             -p 5000:5000 \
                             --mode global \
                             registry:2"
   sleep 10
   docker-machine ssh node1 "docker service ls"
   sleep 10
   docker-machine ssh node1 "docker service ps registry"
   ;;
traefic)
  traefic
  #test-app
  ;;
destroy-swarm)
   test $2
   for (( i=1; i<=$N; i++ ))
   do
      docker-machine ssh node$i docker swarm leave --force
   done
   ;;
destroy)
   test $2
   for (( i=1; i<=$N; i++ ))
   do
      docker-machine rm -f node$i
   done
   ;;
portainer-ssl)
     certgen $3
     certcopy $3
     traefic $2
     docker-machine ssh node1 "sudo mkdir -p /dockerdata/portainer"
     docker-machine ssh node1 "sudo chown -R docker:docker /dockerdata"
     docker-machine ssh node1 docker service rm portainer > /dev/null
     docker-machine ssh node1 docker service rm portainer-ssl > /dev/null
     docker-machine ssh node1 "docker service create --name portainer-ssl \
                              --publish 443:9000 \
                              --constraint 'node.role == manager' \
                              --mount type=bind,src=/dockerdata/portainer,dst=/data \
                              --mount type=bind,src=//var/run/docker.sock,dst=/var/run/docker.sock \
                              portainer/portainer -H unix:///var/run/docker.sock"
     sleet 10
     docker-machine ssh node1 "docker service ls"
  ;;
*) echo "Usage:  ./init-swarm.sh <command> <node number>
	./init-swarm.sh create|init|weave-net|promote|registry|destroy-swarm|destroy <node number>
  ./init-swarm.sh portainer|traefic"
#  ./init-swarm.sh portainer-ssl 3 mydomain.lan
   ;;
esac
