#!/bin/bash

dir=$(pwd)
repo_root=$(cd "$dir/../.." && pwd)

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

sudo rm -rf /home/$username/peviitor
sudo mkdir -p /home/$username/peviitor
sudo chmod -R 777 /home/$username/peviitor

ZK_CONFIG_TEMPLATE="$repo_root/config/zookeeper/zookeeper.env.example"
ZK_CONFIG_DIR="/home/$username/peviitor/config"
ZK_DATA_DIR="/home/$username/peviitor/zookeeper"

if [ -f "$ZK_CONFIG_TEMPLATE" ]; then
  sudo mkdir -p "$ZK_CONFIG_DIR"
  if [ ! -f "$ZK_CONFIG_DIR/zookeeper.env" ]; then
    sudo cp "$ZK_CONFIG_TEMPLATE" "$ZK_CONFIG_DIR/zookeeper.env"
    sudo chown "$username":"$username" "$ZK_CONFIG_DIR/zookeeper.env"
    echo "Created Zookeeper placeholder config at $ZK_CONFIG_DIR/zookeeper.env"
  else
    echo "Existing Zookeeper config detected at $ZK_CONFIG_DIR/zookeeper.env; leaving in place."
  fi
fi

sudo mkdir -p "$ZK_DATA_DIR/data" "$ZK_DATA_DIR/logs" "$ZK_DATA_DIR/certs"

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
	-v /home/$username/peviitor/build:/app/build fe:latest npm run build:qa
rm -f /home/$username/peviitor/build/.htaccess

git clone https://github.com/peviitor-ro/api.git /home/$username/peviitor/api
cp -r /home/$username/peviitor/api /home/$username/peviitor/build
docker run --name apache-container --network mynetwork --ip 172.18.0.11 -d -p 8080:80 \
    --restart unless-stopped \
    -v /home/$username/peviitor/build:/var/www/html alexstefan1702/php-apache-qa

bash "$dir/solr-auth.sh"

echo "Script execution completed."
