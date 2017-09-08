#!/bin/bash

# todo:
# admin panel: rancher, shipyard-project, swarmpit
# network: Contiv Network Plugin
## ssl: registry-ssl
## traefik loadbalance
# glusterFS ?? (gluster-s3 ???)
## portaner global
## gegistry global
# locktest function
# domaintest
# docker-gc
# secret: store cert files and traefik toml files?

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
  test $1
  for (( i=1; i<=$N; i++ ))
  do
     docker-machine ssh node$i "rm -rf /dockerdata/traefik/certs"
     docker-machine ssh node$i "sudo mkdir -p /dockerdata/traefik"
     docker-machine ssh node$i "sudo chown -R docker:docker /dockerdata"
     echo "---------------SCP----------------"
     docker-machine scp -r ./certs node$i:/dockerdata/traefik/
     echo "---------------ls-----------------"
     docker-machine ssh node$i "ls /dockerdata/traefik/certs/"
     echo "---------------END----------------"
  done
  docker-machine ssh node1 docker secret create ${2}.crt /dockerdata/traefik/certs/${2}.crt
  docker-machine ssh node1 docker secret create ${2}.key /dockerdata/traefik/certs/${2}.key
  docker-machine ssh node1 touch /dockerdata/certlock.lock
}

#--------------------------------------------------------------------------------------------------------------

case "$1" in
create)
   test $2

   for (( i=1; i<=$N; i++ ))
   do
      docker-machine create --driver virtualbox node$i
      # --virtualbox-disk-size "20000"  --virtualbox-cpu-count "1" --virtualbox-memory "1024"
      # docker-machine create -d virtualbox --virtualbox-boot2docker-url https://releases.rancher.com/os/latest/rancheros.iso
      docker-machine scp -r ./compose node$i:/home/docker/
   done
   ;;
start)
  test $2
  for (( i=1; i<=$N; i++ ))
  do
     docker-machine start node$i
  done
  ;;
init)
   test $2
   MANAGGER_IP=$(docker-machine ip node1)
   docker-machine ssh node1 docker swarm init --listen-addr ${MANAGGER_IP} --advertise-addr ${MANAGGER_IP}

#  MANAGER_TOKEN=$(docker-machine ssh node1 docker swarm join-token -q manager)
   WORKER_TOKEN=$(docker-machine ssh node1 docker swarm join-token -q worker)
   sleep 5
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
stop)
 test $2
 for (( i=1; i<=$N; i++ ))
 do
    docker-machine stop node$i
 done
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
certgen)
   certgen  $2
   ;;
*) echo "Usage:  ./init-swarm.sh <command> <node number>
	./init-swarm.sh create|init|promote|start|stop|destroy-swarm|destroy <node number>
  ./init-swarm.sh weave-net|registry <node number>
  ./init-swarm.sh portainer
  ./init-swarm.sh traefik|traefik-ssl 3 mydomain.lan"
   ;;
esac
