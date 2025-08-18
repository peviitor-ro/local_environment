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

    # Create security.json to enable authentication
echo " --> Creating security.json at $SECURITY_FILE for Basic Authentication Plugin"
cat <<EOF > security.json
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

echo " --> adding SuggestComponent to jobs core"
docker exec -it solr-container curl -X POST -H "Content-Type: application/json" --data "{\"add-searchcomponent\":{\"name\":\"suggest\",\"class\":\"solr.SuggestComponent\",\"suggester\":{\"name\":\"jobTitleSuggester\",\"lookupImpl\":\"FuzzyLookupFactory\",\"dictionaryImpl\":\"DocumentDictionaryFactory\",\"field\":\"job_title\",\"suggestAnalyzerFieldType\":\"text_general\",\"buildOnCommit\":\"true\",\"buildOnStartup\":\"false\"}}}" http://localhost:8983/solr/jobs/config
docker exec -it solr-container curl -X POST -H "Content-Type: application/json" --data "{\"add-requesthandler\":{\"name\":\"/suggest\",\"class\":\"solr.SearchHandler\",\"startup\":\"lazy\",\"defaults\":{\"suggest\":\"true\",\"suggest.dictionary\":\"jobTitleSuggester\",\"suggest.count\":\"10\"},\"components\":[\"suggest\"]}}" http://localhost:8983/solr/jobs/config

echo " --> enabling Basic Authentication Plugin"
docker cp $SECURITY_FILE $CONTAINER_NAME:/var/solr/data/security.json
docker restart $CONTAINER_NAME
echo " --> $CONTAINER_NAME restarted. It is ready for authentication"

 #chown -R 8983:8983 /Users/$username/peviitor/solr/core/data
 chmod -R u+rwX /Users/$username/peviitor/solr/core/data
 chmod -R 777 /Users/$username/peviitor/solr/core/data
 docker restart $CONTAINER_NAME

# Check if Java is installed
if type -p java > /dev/null; then
    echo "Java is already installed:"
    java -version
else
    echo "Java not found. Installing OpenJDK 11 via Homebrew..."
    brew install openjdk@11
    echo "Java installed:"
    # Add OpenJDK 11 to PATH for the current shell session
    export PATH="/opt/homebrew/opt/openjdk@11/bin:$PATH"
    java -version
fi

# Define JMETER_HOME
JMETER_HOME=$(brew --prefix jmeter)/libexec

# Variables
REQUIRED_PLUGINS=("jpgc-functions")

# Function to check if plugin is installed
function is_plugin_installed() {
    local plugin_id="$1"
    
    # Check if JMETER_HOME is set
    if [ -z "$JMETER_HOME" ]; then
        echo "Error: JMETER_HOME is not set" >&2
        return 1
    fi
    
    # Verify PluginsManagerCMD.sh exists
    if [ ! -f "$JMETER_HOME/bin/PluginsManagerCMD.sh" ]; then
        echo "Error: PluginsManagerCMD.sh not found in $JMETER_HOME/bin" >&2
        return 1
    fi
    
    # Use status command to check for plugin
    if "$JMETER_HOME/bin/PluginsManagerCMD.sh" status 2>/dev/null | grep -q "$plugin_id"; then
        return 0
    else
        return 1
    fi
}

# Check if JMeter is installed
if type -p jmeter; then
    echo "JMeter is already installed:"
    jmeter --version
else
    echo "JMeter not found. Installing..."


    brew install jmeter

    JMETER_PATH=$(brew --prefix jmeter)/libexec
curl -L -o jmeter-plugins-manager.jar https://repo1.maven.org/maven2/kg/apc/jmeter-plugins-manager/1.11/jmeter-plugins-manager-1.11.jar
mv jmeter-plugins-manager.jar $JMETER_PATH/lib/ext/

rm $(brew --prefix jmeter)/libexec/lib/ext/jmeter-plugins-manager-1.9.jar

     chmod a+r $JMETER_PATH/lib/ext/jmeter-plugins-manager.jar


# Descarcă cmdrunner 2.3 dacă nu l-ai descărcat încă
curl -L -o cmdrunner-2.3.jar https://repo1.maven.org/maven2/kg/apc/cmdrunner/2.3/cmdrunner-2.3.jar


    java -cp $JMETER_PATH/lib/ext/jmeter-plugins-manager.jar org.jmeterplugins.repository.PluginManagerCMDInstaller
fi

# Set permissions (if needed)
 
 chmod -R 777 "$JMETER_PATH"



# Install plugins without sudo if you own the directory
for plugin in "${REQUIRED_PLUGINS[@]}"; do
  if is_plugin_installed "$plugin"; then
    echo "Plugin $plugin is already installed."
  else
    echo "Plugin $plugin not found. Installing..."
    $JMETER_HOME/bin/PluginsManagerCMD.sh install "$plugin"
  fi
done

# Check status
$JMETER_HOME/bin/PluginsManagerCMD.sh status

echo "Installation and validation complete."

new_user=$2
new_pass=$3
old_user="solr"
old_pass="SolrRocks"

# Create new user
curl --user $old_user:$old_pass http://localhost:8983/solr/admin/authentication \
-H 'Content-type:application/json' \
-d "{\"set-user\": {\"$new_user\":\"$new_pass\"}}"

# Assign admin role to new user
curl --user $old_user:$old_pass http://localhost:8983/solr/admin/authorization \
-H 'Content-type:application/json' \
-d "{\"set-user-role\": {\"$new_user\": [\"admin\"]}}"

jmeter -n -t "$RUNSH_DIR/migration.jmx" -Duser=$new_user -Dpass=$new_pass

# Delete old user
curl --user $new_user:$new_pass http://localhost:8983/solr/admin/authentication \
-H 'Content-type:application/json' \
-d "{\"delete-user\": [\"$old_user\"]}"

echo "Script execution completed."

echo " ================================================================="
echo " ===================== IMPORTANT INFORMATIONS ===================="
echo
echo "SOLR is running on http://localhost:8983/solr/"
echo "UI is running on http://localhost:8081/"
echo "swagger-ui is running on http://localhost:8081/swagger-ui/"
echo "JMeter is installed and configured. you can start it with command: jmeter"
echo "To run the migration script, use the following command: jmeter -n -t $RUNSH_DIR/migration.jmx -Duser=$new_user -Dpass=$new_pass"
echo "local username and password are: $new_user and $new_pass for SOLR"
echo "to find docker container name: docker ps -a"
echo "to find docker images: docker images"
echo "to find docker logs: docker logs <container_name>"
echo "to find docker container IP: docker inspect <container_name>"
echo "to find docker container IP: docker inspect <container_name> | grep IPAddress"
echo "docker is installed and configured. you can start it with command: docker start <container_name>"
echo "docker is installed and configured. you can stop it with command: docker stop <container_name>"
echo "docker is installed and configured. you can remove it with command: docker rm <container_name>"
echo " ================================================================="
echo " ===================== enjoy local environment ==================="
echo " ====================== peviitor.ro =============================="
echo " ================================================================="