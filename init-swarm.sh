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

#locktest(){
  # cahck lock file? $1
  # if lock file exists echo
  # if not exit0
  # if not all exists?
#}

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
  docker-machine --native-ssh ssh node1 "rm -rf /dockerdata/traefik/certs"
  docker-machine --native-ssh ssh node1 "sudo mkdir -p /dockerdata/traefik"
  docker-machine --native-ssh ssh node1 "sudo chown -R docker:docker /dockerdata"
  test $1
  for (( i=1; i<=$N; i++ ))
  do
     echo "---------------SCP----------------"
     docker-machine scp -r ./certs node$i:/dockerdata/traefik/
     echo "---------------ls-----------------"
     docker-machine --native-ssh ssh node$i "ls /dockerdata/traefik/certs/"
     echo "---------------END----------------"
  done
  docker-machine --native-ssh ssh node1 docker secret create ${1}.crt /dockerdata/traefik/certs/${1}.crt
  docker-machine --native-ssh ssh node1 docker secret create ${1}.key /dockerdata/traefik/certs/${1}.key
  docker-machine --native-ssh ssh node1 touch /dockerdata/${1}.lock
}

traefik(){
  docker-machine --native-ssh ssh node1 "docker service create \
  --name traefik \
  --publish 80:80 \
  --publish 8080:8080 \
  --mode global \
  --label traefik.backend=traefik \
  --label traefik.frontend.rule=Host:traefik.$1 \
  --label traefik.port=8080 \
  --mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock \
  --mount type=bind,source=/dockerdata/traefik/traefik.toml,target=/etc/traefik/traefik.toml \
  --mount type=bind,source=/dockerdata/traefik/log,target=/log \
  --network traefik-net \
  traefik \
  --docker \
  --docker.swarmmode \
  --docker.domain=$1 \
  --docker.watch \
  --logLevel=DEBUG \
  --web"

  docker-machine --native-ssh ssh node1 "docker service ls"
  sleep 10
  docker-machine --native-ssh ssh node1 "docker service ps traefik"
}

traefik-ssl(){
  docker-machine --native-ssh ssh node1 "docker service create \
  --name traefik-ssl \
  --publish 80:80 \
  --publish 8080:8080 \
  --publish 443:443 \
  --mode global \
  --label traefik.backend=traefik \
  --label traefik.frontend.rule=Host:traefik.mydomain.lan \
  --label traefik.port=8080 \
  --mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock \
  --mount type=bind,source=/dockerdata/traefik/traefik.toml,target=/etc/traefik/traefik.toml \
  --mount type=bind,source=/dockerdata/traefik/certs,target=/certs \
  --mount type=bind,source=/dockerdata/traefik/log,target=/log \
  --network traefik-net \
  traefik \
  --docker \
  --docker.swarmmode \
  --docker.domain=$1 \
  --docker.watch \
  --logLevel=DEBUG \
  --web"

  docker-machine --native-ssh ssh node1 "docker service ls"
  sleep 10
  docker-machine --native-ssh ssh node1 "docker service ps traefik-ssl"
}

test-app(){
    docker-machine --native-ssh ssh node1 "docker service create \
     --name blog \
     --network traefik-net \
     --label traefik.enable=true \
     --label traefik.port=2368 \
     --label traefik.frontend.rule=Host:blog.$1 \
     alexellis2/ghost-on-docker"

     docker-machine --native-ssh ssh node1 "docker service ls"
     sleep 10
     docker-machine --native-ssh ssh node1 "docker service ps blog"

# to hostfile:
# node1-IP blog.<domain>
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
      # create shared folder
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
   docker-machine --native-ssh ssh node1 docker swarm init --listen-addr ${MANAGGER_IP} --advertise-addr ${MANAGGER_IP}

#  MANAGER_TOKEN=$(docker-machine --native-ssh ssh node1 docker swarm join-token -q manager)
   WORKER_TOKEN=$(docker-machine --native-ssh ssh node1 docker swarm join-token -q worker)
   for (( i=2; i<=$N; i++ ))
   do
      docker-machine --native-ssh ssh node$i docker swarm join --token ${WORKER_TOKEN} ${MANAGGER_IP}:2377
   done
   ;;
promote)
    test $2
   for (( i=2; i<=$N; i++ ))
   do
      docker-machine --native-ssh ssh node1 docker node promote node$i
   done
   ;;
weave-net)
    test $2
   for (( i=1; i<=$N; i++ ))
   do
      docker-machine --native-ssh ssh node$i docker plugin install --grant-all-permissions store/weaveworks/net-plugin:2.0.1
   done
   docker-machine --native-ssh ssh node1 docker network create --driver=store/weaveworks/net-plugin:2.0.1 weavenet
   ;;
portainer) # global
      # locktest /dockerdata/portainer.lock
      docker-machine --native-ssh ssh node1 "sudo mkdir -p /dockerdata/portainer"
      docker-machine --native-ssh ssh node1 "sudo chown -R docker:docker /dockerdata"
      docker-machine --native-ssh ssh node1 docker service rm portainer > /dev/null
      docker-machine --native-ssh ssh node1 "docker service create --name portainer \
                                --publish 9000:9000 \
                                --constraint 'node.role == manager' \
                                --mount type=bind,src=/dockerdata/portainer,dst=/data \
                                --mount type=bind,src=//var/run/docker.sock,dst=/var/run/docker.sock \
                                --reserve-memory '20M' --limit-memory '40M' \
                                --restart-condition 'any' --restart-max-attempts '55' \
                                --update-delay '5s' --update-parallelism '1' \
                                portainer/portainer -H unix:///var/run/docker.sock"
      sleet 10
      docker-machine --native-ssh ssh node1 "docker service ls"
   ;;
   portainer-ssl) # global
      # locktest /dockerdata/portainer.lock
      # locktest /dockerdata/traefik.lock
      # locktest /dockerdata/domain.lock
      docker-machine --native-ssh ssh node1 "sudo mkdir -p /dockerdata/portainer"
      docker-machine --native-ssh ssh node1 "sudo chown -R docker:docker /dockerdata"
      docker-machine --native-ssh ssh node1 docker service rm portainer > /dev/null
      docker-machine --native-ssh ssh node1 "docker service create \
                               --name 'portainer' \
                               --constraint 'node.role == manager' \
                               --network 'traefik-net' \
                               --replicas '1' \
                               --mount type=bind,src=/dockerdata/portainer,dst=/data \
                               --mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock \
                               --label 'traefik.frontend.rule=Host:$3;PathPrefixStrip:/portainer' \
                               --label 'traefik.backend=portainer' \
                               --label 'traefik.port=9000' \
                               --label 'traefik.docker.network=traefik-net' \
                               --reserve-memory '20M' --limit-memory '40M' \
                               --restart-condition 'any' --restart-max-attempts '55' \
                               --update-delay '5s' --update-parallelism '1' \
                               portainer/portainer"
         sleet 10
         docker-machine --native-ssh ssh node1 "docker service ls"
      ;;
registry) # global
   # locktest /dockerdata/registry.lock
   test $2
   for (( i=1; i<=$N; i++ ))
   do
      docker-machine --native-ssh ssh node$i "sudo mkdir -p /dockerdata/registry"
      docker-machine --native-ssh ssh node$i "sudo chown -R docker:docker /dockerdata"
   done
   docker-machine --native-ssh ssh node1 "docker service create --name registry \
                             --mount type=bind,src=/dockerdata/registry,dst=/var/lib/registry \
                             -p 5000:5000 \
                             --mode global \
                             registry:2"
   sleep 10
   docker-machine --native-ssh ssh node1 "docker service ls"
   sleep 10
   docker-machine --native-ssh ssh node1 "docker service ps registry"
   ;;
traefik)
      # locktest /dockerdata/traefik.lock
config='
[docker]
endpoint = "unix:///var/run/docker.sock"
# default domain
domain = "mydomain.lan"
watch = true
swarmmode = true
[accessLog]
  filePath = "/log/access.log"
traefikLogsFile = "/log/traefik.log"
'
   test $2
   for (( i=1; i<=$N; i++ ))
   do
      docker-machine --native-ssh ssh node$1 docker service rm traefik-ssl
      docker-machine --native-ssh ssh node$1 "docker network create --driver=overlay traefik-net"
      docker-machine --native-ssh ssh node$1 "sudo mkdir -p /dockerdata/traefik/log"
      docker-machine --native-ssh ssh node$1 "sudo chown -R docker:docker /dockerdata"
      docker-machine --native-ssh ssh node$1 echo ${config} > /dockerdata/traefik/traefik.toml
      docker-machine --native-ssh ssh node$1 echo /dockerdata/traefik.lock
   done
  #test2 $3
  traefik $3
  #test-app $3
  ;;
traefik-ssl)
   # locktest /dockerdata/traefik.lock
   certgen  $3 # domain
   certcopy $2 # nod number
config='
defaultEntryPoints = ["http", "https"]
[web]
# Port for the status page
address = ":8080"
[entryPoints]
  [entryPoints.http]
  address = ":80"
    [entryPoints.http.redirect]
      entryPoint = "https"
  [entryPoints.https]
  address = ":443"
    [entryPoints.https.tls]
      [[entryPoints.https.tls.certificates]]
      CertFile = "/certs/$3.crt"
      KeyFile = "/certs/$3.key"
[docker]
endpoint = "unix:///var/run/docker.sock"
# default domain
domain = "$3"
watch = true
swarmmode = true
[accessLog]
  filePath = "/log/access.log"
traefikLogsFile = "/log/traefik.log"
'
   test $2
   for (( i=1; i<=$N; i++ ))
   do
      docker-machine --native-ssh ssh node$1 docker service rm traefik
      docker-machine --native-ssh ssh node$1 "docker network create --driver=overlay traefik-net"
      docker-machine --native-ssh ssh node$1 "sudo mkdir -p /dockerdata/traefik/log"
      docker-machine --native-ssh ssh node$1 "sudo chown -R docker:docker /dockerdata"
      docker-machine --native-ssh ssh node$1 echo ${config} > /dockerdata/traefik/traefik.toml
   done
    #test2 $3
    traefik-ssl $3
    #test-app $3
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
      docker-machine --native-ssh ssh node$i docker swarm leave --force
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
