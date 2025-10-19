#!/bin/bash

if [ "$SUDO_USER" ]; then
    username=$SUDO_USER
else
    username=$USER
fi

ZK_CONFIG_FILE="/home/$username/peviitor/config/zookeeper.env"
ZK_ENABLED_VALUE="false"
ZK_CONNECT_STRING=""
ZK_TIMEOUT_MS="10000"
ZK_SECURE_VALUE="false"
ZK_CLIENT_CHROOT=""
ZK_CERT_DIR="/home/$username/peviitor/zookeeper/certs"

if [ -f "$ZK_CONFIG_FILE" ]; then
  echo "Loading Zookeeper configuration from $ZK_CONFIG_FILE"
  set -a
  # shellcheck source=/dev/null
  . "$ZK_CONFIG_FILE"
  set +a
  ZK_ENABLED_VALUE=$(echo "${ZK_ENABLED:-false}" | tr '[:upper:]' '[:lower:]')
  ZK_SECURE_VALUE=$(echo "${ZK_SECURE:-false}" | tr '[:upper:]' '[:lower:]')
  ZK_CONNECT_STRING="${ZK_CONNECT_STRING:-}"
  ZK_TIMEOUT_MS="${ZK_TIMEOUT_MS:-10000}"
  ZK_CLIENT_CHROOT="${ZK_CLIENT_CHROOT:-}"
  ZK_SSL_CA_PATH="${ZK_SSL_CA_PATH:-}"
  ZK_SSL_CERT_PATH="${ZK_SSL_CERT_PATH:-}"
  ZK_SSL_KEY_PATH="${ZK_SSL_KEY_PATH:-}"
else
  echo "No Zookeeper configuration found; defaulting to standalone Solr."
fi

SOLR_CLOUD_MODE=0
if [ "$ZK_ENABLED_VALUE" = "true" ] && [ -n "$ZK_CONNECT_STRING" ]; then
  SOLR_CLOUD_MODE=1
  echo "Zookeeper integration enabled; Solr will start in Cloud mode."
  if [ -n "$ZK_CLIENT_CHROOT" ] && [[ "$ZK_CONNECT_STRING" != *"$ZK_CLIENT_CHROOT" ]]; then
    ZK_CONNECT_STRING="${ZK_CONNECT_STRING}${ZK_CLIENT_CHROOT}"
  fi
else
  echo "Zookeeper integration disabled or incomplete; continuing in standalone mode."
fi

CORE_NAME=auth
CORE_NAME_2=jobs
CORE_NAME_3=logo
CONTAINER_NAME="solr-container"
SOLR_PORT=8983
SECURITY_FILE="security.json"

declare -a SOLR_DOCKER_OPTS=(
  --name "$CONTAINER_NAME"
  --network mynetwork
  --ip 172.18.0.10
  --restart=unless-stopped
  -d
  -p "$SOLR_PORT:$SOLR_PORT"
  -v "/home/$username/peviitor/solr/core/data:/var/solr/data"
)

if [ "$SOLR_CLOUD_MODE" -eq 1 ]; then
  SOLR_DOCKER_OPTS+=(-e "ZK_HOST=$ZK_CONNECT_STRING")
  SOLR_DOCKER_OPTS+=(-e "SOLR_ZK_TIMEOUT=${ZK_TIMEOUT_MS}")
  if [ -d "$ZK_CERT_DIR" ]; then
    SOLR_DOCKER_OPTS+=(-v "$ZK_CERT_DIR:/opt/solr/zookeeper:ro")
  fi
  if [ "$ZK_SECURE_VALUE" = "true" ]; then
    if [ -n "${ZK_SSL_CA_PATH:-}" ]; then
      SOLR_DOCKER_OPTS+=(-e "ZK_SSL_CA_PATH=/opt/solr/zookeeper/$(basename "$ZK_SSL_CA_PATH")")
    fi
    if [ -n "${ZK_SSL_CERT_PATH:-}" ]; then
      SOLR_DOCKER_OPTS+=(-e "ZK_SSL_CERT_PATH=/opt/solr/zookeeper/$(basename "$ZK_SSL_CERT_PATH")")
    fi
    if [ -n "${ZK_SSL_KEY_PATH:-}" ]; then
      SOLR_DOCKER_OPTS+=(-e "ZK_SSL_KEY_PATH=/opt/solr/zookeeper/$(basename "$ZK_SSL_KEY_PATH")")
    fi
  fi
  echo " --> starting Solr container in Cloud mode on port $SOLR_PORT"
else
  echo " --> starting Solr container in standalone mode on port $SOLR_PORT"
fi

# Start Solr container
# docker run -d --name $CONTAINER_NAME -p $SOLR_PORT:8983 solr:latest
docker run "${SOLR_DOCKER_OPTS[@]}" solr:latest

echo "Waiting for Solr to start..."
sleep 10

sudo chmod -R 777 /home/$username/peviitor

create_solr_entity() {
  local collection="$1"
  if [ "$SOLR_CLOUD_MODE" -eq 1 ]; then
    docker exec -i "$CONTAINER_NAME" bin/solr create -c "$collection" -n _default -s 1 -rf 1
  else
    docker exec -i "$CONTAINER_NAME" bin/solr create_core -c "$collection"
  fi
}

# Create Solr cores
entity_label="cores"
if [ "$SOLR_CLOUD_MODE" -eq 1 ]; then
  entity_label="collections"
fi
echo "Creating Solr $entity_label"
create_solr_entity "$CORE_NAME"
create_solr_entity "$CORE_NAME_2"
create_solr_entity "$CORE_NAME_3"

##### CORE Jobs ####

docker exec "$CONTAINER_NAME" curl -X POST -H "Content-Type: application/json" \
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

docker exec "$CONTAINER_NAME" curl -X POST -H "Content-Type: application/json" \
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

docker exec "$CONTAINER_NAME" curl -X POST -H "Content-Type: application/json" \
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

docker exec "$CONTAINER_NAME" curl -X POST -H "Content-Type: application/json" \
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

docker exec "$CONTAINER_NAME" curl -X POST -H "Content-Type: application/json" \
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

docker exec "$CONTAINER_NAME" curl -X POST -H "Content-Type: application/json" \
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

docker exec "$CONTAINER_NAME" curl -X POST -H "Content-Type: application/json" \
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

docker exec "$CONTAINER_NAME" curl -X POST -H "Content-Type: application/json" \
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



docker exec "$CONTAINER_NAME" curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-copy-field": {
      "source": "job_link",
      "dest": "_text_"
    }
  }' http://localhost:8983/solr/$CORE_NAME_2/schema

docker exec "$CONTAINER_NAME" curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-copy-field": {
      "source": "job_title",
      "dest": "_text_"
    }
  }' http://localhost:8983/solr/$CORE_NAME_2/schema

docker exec "$CONTAINER_NAME" curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-copy-field": {
      "source": "company",
      "dest": ["_text_", "company_str", "hiringOrganization.name"]
    }
  }' http://localhost:8983/solr/$CORE_NAME_2/schema

docker exec "$CONTAINER_NAME" curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-copy-field": {
      "source": "hiringOrganization.name",
      "dest": "hiringOrganization.name_str"
    }
  }' http://localhost:8983/solr/$CORE_NAME_2/schema

docker exec "$CONTAINER_NAME" curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-copy-field": {
      "source": "country",
      "dest": "_text_"
    }
  }' http://localhost:8983/solr/$CORE_NAME_2/schema

docker exec "$CONTAINER_NAME" curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-copy-field": {
      "source": "city",
      "dest": "_text_"
    }
  }' http://localhost:8983/solr/$CORE_NAME_2/schema


##### CORE Logo ####

docker exec "$CONTAINER_NAME" curl -X POST -H "Content-Type: application/json" \
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

docker exec "$CONTAINER_NAME" curl -X POST -H "Content-Type: application/json" --data "{\"add-searchcomponent\":{\"name\":\"suggest\",\"class\":\"solr.SuggestComponent\",\"suggester\":{\"name\":\"jobTitleSuggester\",\"lookupImpl\":\"FuzzyLookupFactory\",\"dictionaryImpl\":\"DocumentDictionaryFactory\",\"field\":\"job_title\",\"suggestAnalyzerFieldType\":\"text_general\",\"buildOnCommit\":\"true\",\"buildOnStartup\":\"false\"}}}" http://localhost:8983/solr/jobs/config

docker exec "$CONTAINER_NAME" curl -X POST -H "Content-Type: application/json" --data "{\"add-requesthandler\":{\"name\":\"/suggest\",\"class\":\"solr.SearchHandler\",\"startup\":\"lazy\",\"defaults\":{\"suggest\":\"true\",\"suggest.dictionary\":\"jobTitleSuggester\",\"suggest.count\":\"10\"},\"components\":[\"suggest\"]}}" http://localhost:8983/solr/jobs/config

docker run --name data-migration --network mynetwork --ip 172.18.0.12 --rm sebiboga/peviitor-data-migration-local:latest

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
