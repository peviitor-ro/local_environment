#!/bin/bash

if ! command -v git &> /dev/null
then
    echo "Git is not installed. Please install Git and re-run the script."
    exit 1
fi

if ! command -v docker &> /dev/null
then
    echo "Docker is not installed. Please install Docker and re-run the script."
    exit 1
fi

if [ "$SUDO_USER" ]; then
    username=$SUDO_USER
else
    username=$USER
fi

sudo rm -rf /Users/lre/peviitor

echo "Remove existing containers if they exist"
for container in apache-container solr-container data-migration deploy-fe
do
  if [ "$(docker ps -aq -f name=$container)" ]; then
    docker stop $container
    docker rm $container
  fi
done

# Check if "mynetwork" network exists, create if it doesn't
network='mynetwork'
if [ -z "$(docker network ls | grep $network)" ]; then
  docker network create --subnet=172.18.0.0/16 $network
fi

git clone https://github.com/peviitor-ro/search-engine.git /Users/lre/peviitor/search-engine
cd /Users/lre/peviitor/search-engine
docker build -t fe:latest .
docker run --name deploy_fe --network mynetwork --ip 172.18.0.13 --rm \
    -v /Users/lre/peviitor/build:/app/build fe:latest npm run build:local
rm -f /Users/lre/peviitor/build/.htaccess

git clone https://github.com/peviitor-ro/api.git /Users/lre/peviitor/api
cp -r /Users/lre/peviitor/api /Users/lre/peviitor/build
docker run --name apache-container --network mynetwork --ip 172.18.0.11 -d -p 8080:80 -v /Users/lre/peviitor/build:/var/www/html sebiboga/php-apache:arm64

git clone https://github.com/peviitor-ro/solr.git /Users/lre/peviitor/solr
sudo chmod -R 777 /Users/lre/peviitor
docker run --name solr-container --network mynetwork --ip 172.18.0.10 -d -p 8983:8983 -v /Users/lre/peviitor/solr/core/data:/var/solr/data solr:latest

#if error is: The path /Users/lre/peviitor/solr/core/data is not shared from the host and is not known to Docker. we need to add in file sharing this path /Users/lre/peviitor/solr/core/data

# Wait for solr-container to be ready
until [ "$(docker inspect -f {{.State.Running}} solr-container)" == "true" ]; do
    sleep 0.1;
done;

docker run --name data-migration --network mynetwork --ip 172.18.0.12 --rm sebiboga/peviitor-data-migration-local:latest

docker rmi sebiboga/peviitor-data-migration-local:latest

echo "Script execution completed."
