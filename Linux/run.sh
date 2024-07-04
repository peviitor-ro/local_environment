#!/bin/bash

# Check if Git is installed
if ! command -v git &> /dev/null
then
    echo "Git is not installed. Please install Git and re-run the script."
    exit 1
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null
then
    echo "Docker is not installed. Please install Docker and re-run the script."
    exit 1
fi

# Create directory if it doesn't exist
sudo rm -rf /home/peviitor

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

docker run --name deploy_fe --network mynetwork --ip 172.18.0.13 --rm \
    -v /home/peviitor/:/app/build sebiboga/fe:latest npm run build:local
sudo rm -f /home/peviitor/.htaccess

git clone https://github.com/peviitor-ro/api.git /home/peviitor/
docker run --name apache-container --network mynetwork --ip 172.18.0.11 -d -p 8080:80 \
    -v /home/peviitor/:/var/www/html sebiboga/php-apache:1.0.0

git clone https://github.com/peviitor-ro/solr.git /home/peviitor/
sudo chmod -R 777 /home/$USERNAME/peviitor
docker run --name solr-container --network mynetwork --ip 172.18.0.10 -d -p 8983:8983 \
    -v /home/peviitor/solr/core/data:/var/solr/data sebiboga/peviitor:1.0.0

# Wait for solr-container to be ready
until [ "$(docker inspect -f {{.State.Running}} solr-container)" == "true" ]; do
    sleep 0.1;
done;

docker run --name data-migration --network mynetwork --ip 172.18.0.12 --rm sebiboga/peviitor-data-migration-local:latest

# Remove the image
docker rmi sebiboga/peviitor-data-migration-local:latest

echo "Script execution completed."