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
    -v /home/$username/peviitor/solr/core/data:/var/solr/data solr:latest

echo "Waiting for Solr to start..."
sleep 10

sudo chmod -R 777 /home/$username/peviitor

# Create Solr cores
echo " -->Creating Solr cores $CORE_NAME, $CORE_NAME_2,$CORE_NAME_4 and $CORE_NAME_3"
docker exec -it $CONTAINER_NAME bin/solr create_core -c $CORE_NAME
docker exec -it $CONTAINER_NAME bin/solr create_core -c $CORE_NAME_2
docker exec -it $CONTAINER_NAME bin/solr create_core -c $CORE_NAME_3
docker exec -it $CONTAINER_NAME bin/solr create_core -c $CORE_NAME_4

echo " -->Adding fields to Solr cores $CORE_NAME, $CORE_NAME_2,$CORE_NAME_4  and $CORE_NAME_3"
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



##### CORE firme ####
docker exec -it solr-container curl -X POST -H "Content-Type: application/json" \
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



docker exec -it solr-container curl -X POST -H "Content-Type: application/json" \
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

  docker exec -it solr-container curl -X POST -H "Content-Type: application/json" \
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

  docker exec -it solr-container curl -X POST -H "Content-Type: application/json" \
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


    docker exec -it solr-container curl -X POST -H "Content-Type: application/json" \
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

      docker exec -it solr-container curl -X POST -H "Content-Type: application/json" \
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

  docker exec -it solr-container curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-copy-field": {
      "source": "sector",
      "dest": "_text_"
    }
  }' http://localhost:8983/solr/$CORE_NAME_4/schema


docker exec -it solr-container curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-copy-field": {
      "source": "brands",
      "dest": "_text_"
    }
  }' http://localhost:8983/solr/$CORE_NAME_4/schema

  docker exec -it solr-container curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-copy-field": {
      "source": "denumire",
      "dest": "_text_"
    }
  }' http://localhost:8983/solr/$CORE_NAME_4/schema

docker exec -it solr-container curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-copy-field": {
      "source": "stare",
      "dest": "_text_"
    }
  }' http://localhost:8983/solr/$CORE_NAME_4/schema


  docker exec -it solr-container curl -X POST -H "Content-Type: application/json" \
  --data '{
    "add-copy-field": {
      "source": "id",
      "dest": "_text_"
    }
  }' http://localhost:8983/solr/$CORE_NAME_4/schema



# Create security.json to enable authentication
echo " --> Creating security.json at $SECURITY_FILE for Basic Authentication Plugin"
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


echo " --> adding SuggestComponent to jobs core"
docker exec -it solr-container curl -X POST -H "Content-Type: application/json" --data "{\"add-searchcomponent\":{\"name\":\"suggest\",\"class\":\"solr.SuggestComponent\",\"suggester\":{\"name\":\"jobTitleSuggester\",\"lookupImpl\":\"FuzzyLookupFactory\",\"dictionaryImpl\":\"DocumentDictionaryFactory\",\"field\":\"job_title\",\"suggestAnalyzerFieldType\":\"text_general\",\"buildOnCommit\":\"true\",\"buildOnStartup\":\"false\"}}}" http://localhost:8983/solr/jobs/config
docker exec -it solr-container curl -X POST -H "Content-Type: application/json" --data "{\"add-requesthandler\":{\"name\":\"/suggest\",\"class\":\"solr.SearchHandler\",\"startup\":\"lazy\",\"defaults\":{\"suggest\":\"true\",\"suggest.dictionary\":\"jobTitleSuggester\",\"suggest.count\":\"10\"},\"components\":[\"suggest\"]}}" http://localhost:8983/solr/jobs/config

echo " --> enabling Basic Authentication Plugin"
docker cp $SECURITY_FILE $CONTAINER_NAME:/var/solr/data/security.json
docker restart $CONTAINER_NAME
echo " --> $CONTAINER_NAME restarted. It is ready for authentication"

#docker exec -it $CONTAINER_NAME chown solr:solr /var/solr/data/security.json
#docker exec -it $CONTAINER_NAME chmod 600 /var/solr/data/security.json
sudo chown -R 8983:8983 /home/$username/peviitor/solr/core/data
sudo chmod -R u+rwX /home/$username/peviitor/solr/core/data
sudo docker restart $CONTAINER_NAME
docker exec -it $CONTAINER_NAME chmod 600 /var/solr/data/security.json

docker restart $CONTAINER_NAME
echo " --> $CONTAINER_NAME restarted."


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



# Define JMETER_HOME
JMETER_HOME=/usr/share/jmeter

# Variables
JMETER_HOME=/usr/share/jmeter
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

    sudo apt install -y jmeter libcanberra-gtk3-module
    sudo chown -R $USER:$USER $JMETER_HOME
    sudo chmod -R a+rX $JMETER_HOME

    wget https://dlcdn.apache.org/jmeter/binaries/apache-jmeter-5.6.3.tgz
    sudo tar --strip-components=1 -xvzf apache-jmeter-5.6.3.tgz -C $JMETER_HOME

    wget -O $JMETER_HOME/lib/ext/plugins-manager.jar https://jmeter-plugins.org/get/
    sudo chmod a+r $JMETER_HOME/lib/ext/plugins-manager.jar

    wget -O $JMETER_HOME/lib/cmdrunner-2.2.jar https://search.maven.org/remotecontent?filepath=kg/apc/cmdrunner/2.2/cmdrunner-2.2.jar

    java -cp $JMETER_HOME/lib/ext/plugins-manager.jar org.jmeterplugins.repository.PluginManagerCMDInstaller
fi

# Set permissions (if needed)
sudo chown -R $USER:$USER $JMETER_HOME
sudo chmod -R a+rX $JMETER_HOME

# Download cmdrunner-2.3.jar (instead of 2.2) to lib
wget -O $JMETER_HOME/lib/cmdrunner-2.3.jar https://repo1.maven.org/maven2/kg/apc/cmdrunner/2.3/cmdrunner-2.3.jar

# Download official Plugins Manager jar with proper naming
wget -O $JMETER_HOME/lib/ext/jmeter-plugins-manager-1.10.jar https://jmeter-plugins.org/get/



# Run PluginManagerCMDInstaller with correct jar name
java -cp $JMETER_HOME/lib/ext/jmeter-plugins-manager-1.10.jar org.jmeterplugins.repository.PluginManagerCMDInstaller

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

# Delete old user
curl --user $new_user:$new_pass http://localhost:8983/solr/admin/authentication \
-H 'Content-type:application/json' \
-d "{\"delete-user\": [\"$old_user\"]}"

FILE="$HOME/Documents/informatii_importante.peviitor.txt"
mkdir -p "$(dirname "$FILE")"
cat > "$FILE" <<'EOF'
=================================================================
                    IMPORTANT INFORMATION
=================================================================

SERVICES
  [~] SOLR:       http://localhost:8983/solr/
  [~] UI:         http://localhost:8081/
  [~] Swagger UI: http://localhost:8081/swagger-ui/

JMETER
  [~] Migrare:  jmeter -n -t $RUNSH_DIR/migration.jmx -Duser=$new_user -Dpass=$new_pass
  [~] Firme:    jmeter -n -t $RUNSH_DIR/firme.jmx    -Duser=$new_user -Dpass=$new_pass

CREDENTIALS
  [~] SOLR local user: $new_user
  [~] SOLR local pass: $new_pass

DOCKER
  [~] List container:     docker ps -a
  [~] List images:        docker images
  [~] Logs container:     docker logs <container_name>
  [~] Inspect container:  docker inspect <container_name>
  [~] IP container:
      - docker inspect <container_name>
      - docker inspect <container_name> | grep IPAddress
  [~] Start container:    docker start <container_name>
  [~] Stop container:     docker stop <container_name>
  [~] Remove container:   docker rm <container_name>

=================================================================
                       Local environment
                          peviitor.ro
=================================================================
EOF

jmeter -n -t "$RUNSH_DIR/migration.jmx" -Duser=$new_user -Dpass=$new_pass
jmeter -n -t "$RUNSH_DIR/firme.jmx" -Duser=$new_user -Dpass=$new_pass

echo "Script execution completed."
