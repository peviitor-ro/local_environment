#!/bin/bash

if [ "$SUDO_USER" ]; then
    username=$SUDO_USER
else
    username=$USER
fi

docker stop apache-container 
docker rm apache-container 
cd /home/$username/peviitor/search-engine
docker build -t fe:latest .
docker run --name deploy_fe --network mynetwork --ip 172.18.0.13 --rm \
    -v /home/$username/peviitor/build:/app/build fe:latest npm run build:local
rm -f /home/$username/peviitor/build/.htaccess
cp -r /home/$username/peviitor/api /home/$username/peviitor/build
docker run --name apache-container --network mynetwork --ip 172.18.0.11 -d -p 8080:80 \
    -v /home/$username/peviitor/build:/var/www/html sebiboga/php-apache:latest