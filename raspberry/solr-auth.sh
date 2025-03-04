#!/bin/bash

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
# docker run -d --name $CONTAINER_NAME -p $SOLR_PORT:8983 solr:latest
docker run --name $CONTAINER_NAME --network mynetwork --ip 172.18.0.10 -d -p $SOLR_PORT:$SOLR_PORT \
    --restart unless-stopped \
    -v /home/$username/peviitor/solr/core/data:/var/solr/data solr:latest

echo "Waiting for Solr to start..."
sleep 3

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


docker exec -it solr-container curl -X POST -H "Content-Type: application/json" --data "{\"add-searchcomponent\":{\"name\":\"suggest\",\"class\":\"solr.SuggestComponent\",\"suggester\":{\"name\":\"jobTitleSuggester\",\"lookupImpl\":\"FuzzyLookupFactory\",\"dictionaryImpl\":\"DocumentDictionaryFactory\",\"field\":\"job_title\",\"suggestAnalyzerFieldType\":\"text_general\",\"buildOnCommit\":\"true\",\"buildOnStartup\":\"false\"}}}" http://localhost:8983/solr/jobs/config
docker exec -it solr-container curl -X POST -H "Content-Type: application/json" --data "{\"add-requesthandler\":{\"name\":\"/suggest\",\"class\":\"solr.SearchHandler\",\"startup\":\"lazy\",\"defaults\":{\"suggest\":\"true\",\"suggest.dictionary\":\"jobTitleSuggester\",\"suggest.count\":\"10\"},\"components\":[\"suggest\"]}}" http://localhost:8983/solr/jobs/config


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


master_server=$(curl -s https://api.peviitor.ro/devops/solr/)
echo $master_server
curl "${master_server}solr/jobs/select?q=*:*&fl=job_title,job_link,company,hiringOrganization.name,country,remote,jobLocationType,validThrough,city,sursa,id,county&rows=1000000&wt=json&indent=true" -o backup.json
jq '.response.docs' backup.json > cleaned_backup.json

my_server=http://localhost:8983
echo "Cleaning data on $my_server"
curl "${my_server}/solr/jobs/update" -H "Content-Type: text/xml" --data-binary '<delete><query>*:*</query></delete>'
curl "${my_server}/solr/jobs/update" --data '<commit/>'
echo "Uploading data to ${my_server}"
curl "${my_server}/solr/jobs/update?commit=true" -H "Content-Type: application/json" --data-binary @cleaned_backup.json


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

docker cp $SECURITY_FILE $CONTAINER_NAME:/var/solr/data/security.json

docker restart $CONTAINER_NAME

