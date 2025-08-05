#!/bin/bash

docker stop apache-container solr-container
docker rm apache-container solr-container
docker rmi fe:latest sebiboga/peviitor:latest sebiboga/php-apache:latest