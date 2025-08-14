#!/bin/bash

RUNSH_DIR=$1

if [ "$SUDO_USER" ]; then
    username=$SUDO_USER
else
    username=$USER
fi

CORE_NAME=auth
CORE_NAME_2=jobs
CORE_NAME_3=logo
CORE_NAME_4=firme
CONTAINER_NAME="solr-container"
SOLR_PORT=8983
SECURITY_FILE="security.json"

# Start Solr container
echo " --> starting Solr container...on port $SOLR_PORT"
docker run --name $CONTAINER_NAME --network mynetwork --ip 172.168.0.10 --restart=always -d -p $SOLR_PORT:$SOLR_PORT \
    -v /Users/$username/peviitor/solr/core/data:/var/solr/data solr:latest

echo "Waiting for Solr to start..."
sleep 10

chmod -R 777 /Users/$username/peviitor

# Create Solr cores
echo " -->Creating Solr cores $CORE_NAME, $CORE_NAME_2 and $CORE_NAME_3"
docker exec -it $CONTAINER_NAME bin/solr create_core -c $CORE_NAME
docker exec -it $CONTAINER_NAME bin/solr create_core -c $CORE_NAME_2
docker exec -it $CONTAINER_NAME bin/solr create_core -c $CORE_NAME_3
docker exec -it $CONTAINER_NAME bin/solr create_core -c $CORE_NAME_4

echo " -->Adding fields to Solr cores $CORE_NAME, $CORE_NAME_2, $CORE_NAME_3 and $CORE_NAME_4"

##### CORE Jobs ####
docker exec -it $CONTAINER_NAME curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-field": [
      {
        "name": "job_link",
        "type": "text_general",
        "stored": true,
        "indexed": true
        "multiValued": true
        "uninvertible": true
      }
    ]
  }' http://localhost:8983/solr/$CORE_NAME_2/schema

    docker exec -it $CONTAINER_NAME curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-field": [
      {
        "name": "job_title",
        "type": "text_general",
        "stored": true,
        "indexed": true
        "multiValued": true
        "uninvertible": true
      }
    ]
  }' http://localhost:8983/solr/$CORE_NAME_2/schema

  docker exec -it $CONTAINER_NAME curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-field": [
      {
        "name": "company",
        "type": "text_general",
        "stored": true,
        "indexed": true
        "multiValued": true
        "uninvertible": true
      }
    ]
  }' http://localhost:8983/solr/$CORE_NAME_2/schema

  docker exec -it $CONTAINER_NAME curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-field": [
      {
        "name": "company_str",
        "type": "string",
        "stored": true,
        "indexed": true,
        "docValues": true,
        "uninvertible": true,
        "omitNorms": true,
        "omitTermFreqAndPositions": true,
        "sortMissingLast": true,
      }
    ]
  }' http://localhost:8983/solr/$CORE_NAME_2/schema

  docker exec -it $CONTAINER_NAME curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-field": [
      {
        "name": "hiringOrganization.name",
        "type": "text_general",
        "stored": true,
        "indexed": true
        "multiValued": true
        "uninvertible": true
      }
    ]
  }' http://localhost:8983/solr/$CORE_NAME_2/schema

  docker exec -it $CONTAINER_NAME curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-field": [
      {
        "name": "country",
        "type": "text_general",
        "stored": true,
        "indexed": true
        "multiValued": true
        "uninvertible": true
      }
    ]
  }' http://localhost:8983/solr/$CORE_NAME_2/schema

  docker exec -it $CONTAINER_NAME curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-field": [
      {
        "name": "city",
        "type": "text_general",
        "stored": true,
        "indexed": true
        "multiValued": true
        "uninvertible": true
      }
    ]
  }' http://localhost:8983/solr/$CORE_NAME_2/schema

  docker exec -it $CONTAINER_NAME curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-field": [
      {
        "name": "county",
        "type": "text_general",
        "stored": true,
        "indexed": true
        "multiValued": true
        "uninvertible": true
      }
    ]
  }' http://localhost:8983/solr/$CORE_NAME_2/schem

  docker exec -it $CONTAINER_NAME  curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-copy-field": {
      "source": "job_link",
      "dest": "_text_"
    }
  }' http://localhost:8983/solr/$CORE_NAME_2/schema

  docker exec -it $CONTAINER_NAME curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-copy-field": {
      "source": "job_title",
      "dest": "_text_"
    }
  }' http://localhost:8983/solr/$CORE_NAME_2/schema

  docker exec -it $CONTAINER_NAME  curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-copy-field": {
      "source": "company",
      "dest": ["_text_", "company_str", "hiringOrganization.name"]
    }
  }' http://localhost:8983/solr/$CORE_NAME_2/schema

  docker exec -it $CONTAINER_NAME curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-copy-field": {
      "source": "hiringOrganization.name",
      "dest": "hiringOrganization.name_str"
    }
  }' http://localhost:8983/solr/$CORE_NAME_2/schema

  docker exec -it $CONTAINER_NAME  curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-copy-field": {
      "source": "country",
      "dest": "_text_"
    }
  }' http://localhost:8983/solr/$CORE_NAME_2/schema

  docker exec -it $CONTAINER_NAME  curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-copy-field": {
      "source": "city",
      "dest": "_text_"
    }
  }' http://localhost:8983/solr/$CORE_NAME_2/schema

  ##### CORE Logo ####

docker exec -it $CONTAINER_NAME  curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-field": [
      {
        "name": "url",
        "type": "text_general",
        "stored": true,
        "indexed": true
        "multiValued": true
        "uninvertible": true
      }
    ]
  }' http://localhost:8983/solr/$CORE_NAME_3/schema

  ##### CORE firme ####
docker exec -it $CONTAINER_NAME curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-field": [
      {
        "name": "cui",
        "type": "plongs",
        "stored": true,
        "indexed": true
        "multiValued": true
        "uninvertible": true
      }
    ]
  }' http://localhost:8983/solr/$CORE_NAME_4/schema

  docker exec -it $CONTAINER_NAME curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-field": [
      {
        "name": "stare",
        "type": "text_general",
        "stored": true,
        "indexed": true
        "multiValued": true
        "uninvertible": true
      }
    ]
  }' http://localhost:8983/solr/$CORE_NAME_4/schema

    docker exec -it $CONTAINER_NAME curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-field": [
      {
        "name": "cod_postal",
        "type": "plongs",
        "stored": true,
        "indexed": true
        "multiValued": true
        "uninvertible": true
      }
    ]
  }' http://localhost:8983/solr/$CORE_NAME_4/schema

    docker exec -it $CONTAINER_NAME  curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-field": [
      {
        "name": "cod_stare",
        "type": "plongs",
        "stored": true,
        "indexed": true
        "multiValued": true
        "uninvertible": true
      }
    ]
  }' http://localhost:8983/solr/$CORE_NAME_4/schema


     docker exec -it $CONTAINER_NAME curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-field": [
      {
        "name": "sector",
        "type": "plongs",
        "stored": true,
        "indexed": true
        "multiValued": true
        "uninvertible": true
      }
    ]
  }' http://localhost:8983/solr/$CORE_NAME_4/schema

       docker exec -it $CONTAINER_NAME curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-field": [
      {
        "name": "brands",
        "type": "string",
        "stored": true,
        "indexed": true
        "multiValued": true
        "uninvertible": true
      }
    ]
  }' http://localhost:8983/solr/$CORE_NAME_4/schema

    docker exec -it $CONTAINER_NAME curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-copy-field": {
      "source": "sector",
      "dest": "_text_"
    }
  }' http://localhost:8983/solr/$CORE_NAME_4/schema

  docker exec -it $CONTAINER_NAME curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-copy-field": {
      "source": "brands",
      "dest": "_text_"
    }
  }' http://localhost:8983/solr/$CORE_NAME_4/schema

   docker exec -it $CONTAINER_NAME  curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-copy-field": {
      "source": "denumire",
      "dest": "_text_"
    }
  }' http://localhost:8983/solr/$CORE_NAME_4/schema

  docker exec -it $CONTAINER_NAME  curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-copy-field": {
      "source": "stare",
      "dest": "_text_"
    }
  }' http://localhost:8983/solr/$CORE_NAME_4/schema

    docker exec -it $CONTAINER_NAME curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-copy-field": {
      "source": "id",
      "dest": "_text_"
    }
  }' http://localhost:8983/solr/$CORE_NAME_4/schema