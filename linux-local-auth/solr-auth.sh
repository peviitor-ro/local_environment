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
CONTAINER_NAME="solr-container"
SOLR_PORT=8983
SECURITY_FILE="security.json"

# Start Solr container

docker run --name $CONTAINER_NAME --network mynetwork --ip 172.168.0.10 --restart=always -d -p $SOLR_PORT:$SOLR_PORT \
    -v /home/$username/peviitor/solr/core/data:/var/solr/data solr:latest

echo "Waiting for Solr to start..."
sleep 10

sudo chmod -R 777 /home/$username/peviitor

# Create Solr cores
echo "Creating Solr cores"
docker exec -it $CONTAINER_NAME bin/solr create_core -c $CORE_NAME
docker exec -it $CONTAINER_NAME bin/solr create_core -c $CORE_NAME_2
docker exec -it $CONTAINER_NAME bin/solr create_core -c $CORE_NAME_3

##### CORE Jobs ####

docker exec -it solr-container curl -X POST -H "Content-Type: application/json" \
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

docker exec -it solr-container curl -X POST -H "Content-Type: application/json" \
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

docker exec -it solr-container curl -X POST -H "Content-Type: application/json" \
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

docker exec -it solr-container curl -X POST -H "Content-Type: application/json" \
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

docker exec -it solr-container curl -X POST -H "Content-Type: application/json" \
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

docker exec -it solr-container curl -X POST -H "Content-Type: application/json" \
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

docker exec -it solr-container curl -X POST -H "Content-Type: application/json" \
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

docker exec -it solr-container curl -X POST -H "Content-Type: application/json" \
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
  }' http://localhost:8983/solr/$CORE_NAME_2/schema



docker exec -it solr-container curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-copy-field": {
      "source": "job_link",
      "dest": "_text_"
    }
  }' http://localhost:8983/solr/$CORE_NAME_2/schema

docker exec -it solr-container curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-copy-field": {
      "source": "job_title",
      "dest": "_text_"
    }
  }' http://localhost:8983/solr/$CORE_NAME_2/schema

docker exec -it solr-container curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-copy-field": {
      "source": "company",
      "dest": ["_text_", "company_str", "hiringOrganization.name"]
    }
  }' http://localhost:8983/solr/$CORE_NAME_2/schema

docker exec -it solr-container curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-copy-field": {
      "source": "hiringOrganization.name",
      "dest": "hiringOrganization.name_str"
    }
  }' http://localhost:8983/solr/$CORE_NAME_2/schema

docker exec -it solr-container curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-copy-field": {
      "source": "country",
      "dest": "_text_"
    }
  }' http://localhost:8983/solr/$CORE_NAME_2/schema

docker exec -it solr-container curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-copy-field": {
      "source": "city",
      "dest": "_text_"
    }
  }' http://localhost:8983/solr/$CORE_NAME_2/schema


##### CORE Logo ####

docker exec -it solr-container curl -X POST -H "Content-Type: application/json" \
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





# Create security.json to enable authentication
cat <<EOF > $SECURITY_FILE
{
"authentication":{
   "blockUnknown": true,
   "class":"solr.BasicAuthPlugin",
   "credentials":{"solr":"IV0EHq1OnNrj6gvRCwvFwTrZ1+z1oBbnQdiVC3otuq0= Ndd7LKvVBAaZIF0QAVi1ekCfAJXr1GGfLtRUXhgrF8c="},
   "realm":"My Solr users",
   "forwardCredentials": false
},
"authorization":{
   "class":"solr.RuleBasedAuthorizationPlugin",
   "permissions":[{"name":"security-edit",
      "role":"admin"}],
   "user-role":{"solr":"admin"}
}}
EOF

echo "security.json created at $SECURITY_FILE"



docker exec -it solr-container curl -X POST -H "Content-Type: application/json" --data "{\"add-searchcomponent\":{\"name\":\"suggest\",\"class\":\"solr.SuggestComponent\",\"suggester\":{\"name\":\"jobTitleSuggester\",\"lookupImpl\":\"FuzzyLookupFactory\",\"dictionaryImpl\":\"DocumentDictionaryFactory\",\"field\":\"job_title\",\"suggestAnalyzerFieldType\":\"text_general\",\"buildOnCommit\":\"true\",\"buildOnStartup\":\"false\"}}}" http://localhost:8983/solr/jobs/config

docker exec -it solr-container curl -X POST -H "Content-Type: application/json" --data "{\"add-requesthandler\":{\"name\":\"/suggest\",\"class\":\"solr.SearchHandler\",\"startup\":\"lazy\",\"defaults\":{\"suggest\":\"true\",\"suggest.dictionary\":\"jobTitleSuggester\",\"suggest.count\":\"10\"},\"components\":[\"suggest\"]}}" http://localhost:8983/solr/jobs/config

docker cp $SECURITY_FILE $CONTAINER_NAME:/var/solr/data/security.json

docker restart $CONTAINER_NAME


# 1. Update package list
sudo apt update

# Check if Java is installed
if type -p java; then
    echo "Java is already installed:"
    java -version
else
    echo "Java not found. Installing OpenJDK 11..."
    sudo apt install -y openjdk-11-jdk
    echo "Java installed:"
    java -version
fi

# Check if JMeter is installed
if type -p jmeter; then
    echo "JMeter is already installed:"
    jmeter --version
else
    echo "JMeter not found. Installing..."
    # Install initial JMeter from repo
    sudo apt install -y jmeter
    # Install GTK module to suppress warnings
    sudo apt install -y libcanberra-gtk3-module
    # Set ownership and permissions for /usr/share/jmeter
    sudo chown -R $USER:$USER /usr/share/jmeter
    sudo chmod -R a+rX /usr/share/jmeter
    # Download latest JMeter binary
    wget https://dlcdn.apache.org/jmeter/binaries/apache-jmeter-5.6.3.tgz
    # Extract over existing installation
    sudo tar --strip-components=1 -xvzf apache-jmeter-5.6.3.tgz -C /usr/share/jmeter
    # Download Plugins Manager
    sudo wget -O /usr/share/jmeter/lib/ext/plugins-manager.jar https://jmeter-plugins.org/get/
    # Set proper permissions for plugins manager
    sudo chmod a+r /usr/share/jmeter/lib/ext/plugins-manager.jar
    # Verify installation
    jmeter --version
    echo "Installation complete. Run JMeter as your user with: jmeter"
    echo "Since you own /usr/share/jmeter, Plugins Manager can now install plugins properly."
fi

jmeter -n -t "$RUNSH_DIR/migration.jmx"