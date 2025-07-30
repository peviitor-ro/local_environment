#!/bin/bash

dir=$(pwd)

if ! command -v git &> /dev/null
then
    echo "Git is not installed. Attempting to install Git..."

    # Detect package manager and install Git
    if command -v apt &> /dev/null
    then
        sudo apt update
        sudo apt install -y git
    elif command -v apt-get &> /dev/null
    then
        sudo apt-get update
        sudo apt-get install -y git
    elif command -v yum &> /dev/null
    then
        sudo yum install -y git
    else
        echo "Could not find a supported package manager (apt, apt-get, or yum). Please install Git manually."
        exit 1
    fi

    # Check if git installed successfully
    if command -v git &> /dev/null
    then
        echo "Git installed successfully."
    else
        echo "Failed to install Git. Please install it manually."
        exit 1
    fi
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

sudo rm -rf /home/$username/peviitor

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

git clone https://github.com/peviitor-ro/search-engine.git /home/$username/peviitor/search-engine
cd /home/$username/peviitor/search-engine
docker build -t fe:latest .
docker run --name deploy_fe --network mynetwork --ip 172.18.0.13 --rm \
    -v /home/$username/peviitor/build:/app/build fe:latest npm run build:local
rm -f /home/$username/peviitor/build/.htaccess

git clone https://github.com/peviitor-ro/api.git /home/$username/peviitor/api
cp -r /home/$username/peviitor/api /home/$username/peviitor/build
docker run --name apache-container --network mynetwork --ip 172.18.0.11 -d -p 8080:80 \
    -v /home/$username/peviitor/build:/var/www/html alexstefan1702/php-apache

bash "$dir/solr-auth.sh"

echo "Script execution completed."
