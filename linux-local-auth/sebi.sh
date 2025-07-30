#!/bin/bash

set -e  # Exit on error

dir=$(pwd)

# Prompt for Solr username and password
read -p "Enter the Solr username: " solr_user
read -sp "Enter the Solr password: " solr_password
echo

echo "You entered user: $solr_user"
# Note: Avoid echoing passwords in real use.

# Function to install git if missing
install_git_if_missing() {
  if ! command -v git &>/dev/null; then
    echo "Git not found, installing..."
    if command -v apt &>/dev/null; then
      sudo apt update && sudo apt install -y git
    elif command -v apt-get &>/dev/null; then
      sudo apt-get update && sudo apt-get install -y git
    elif command -v yum &>/dev/null; then
      sudo yum install -y git
    else
      echo "No supported package manager found. Install git manually."
      exit 1
    fi
  fi
  echo "Git is installed."
}

# Function to install Docker if missing
install_docker_if_missing() {
  if ! command -v docker &>/dev/null; then
    echo "Docker not found, installing..."
    if command -v apt &>/dev/null; then
      sudo apt update
      sudo apt install -y ca-certificates curl gnupg lsb-release
      sudo mkdir -p /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
      sudo apt update
      sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    elif command -v apt-get &>/dev/null; then
      sudo apt-get update
      sudo apt-get install -y ca-certificates curl gnupg lsb-release
      sudo mkdir -p /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
      sudo apt-get update
      sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    elif command -v yum &>/dev/null; then
      sudo yum install -y yum-utils
      sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
      sudo yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
      sudo systemctl start docker
      sudo systemctl enable docker

    else
      echo "No supported package manager found. Install Docker manually."
      exit 1
    fi
  fi
  echo "Docker is installed."
}

# Generate Solr BasicAuth credentials dynamically
generate_solr_credential() {
  local pass="$1"
  # Generate 16 random bytes salt and base64 encode it
  local salt=$(head -c 16 /dev/urandom | base64 | tr -d '\n')

  # Decode base64 salt string to binary for hashing
  local salt_bin=$(echo "$salt" | base64 -d)

  # Compute SHA-256 hash of password+salt (binary)
  # sha256sum outputs hex string - convert hex to binary then base64 encode
  local hash_hex=$(printf "%s%s" "$pass" "$salt_bin" | sha256sum | head -c 64)
  local hash_bin=$(echo "$hash_hex" | xxd -r -p | base64 | tr -d '\n')

  # Combine base64 hash and salt separated by space as Solr credentials
  echo "$hash_bin $salt"
}

# Determine correct username for paths
if [ "$SUDO_USER" ]; then
  username=$SUDO_USER
else
  username=$USER
fi

install_git_if_missing
install_docker_if_missing

# Clean up existing build directory safely
sudo rm -rf /home/$username/peviitor

# Stop and remove existing containers if they exist
echo "Removing existing containers if any..."
for container in apache-container solr-container data-migration deploy-fe; do
  if docker ps -aq -f name="$container" | grep -q .; then
    docker stop "$container"
    docker rm "$container"
  fi
done

# Remove Docker network if exists and create a new one
network='mynetwork'
if docker network ls | grep -q "$network"; then
  echo "Removing network $network..."
  docker network rm "$network"
fi
echo "Creating network $network..."
docker network create --subnet=172.168.0.0/16 "$network"

# Clone search-engine repo and adjust environment file
git clone --depth 1 --branch main --single-branch https://github.com/peviitor-ro/search-engine.git /home/$username/peviitor/search-engine
ENV_FILE="/home/$username/peviitor/search-engine/env/.env.local"
sed -i 's|http://localhost:8080|http://localhost:8081|g' "$ENV_FILE"

# Build frontend Docker image and run build inside container
cd /home/$username/peviitor/search-engine
docker build -t fe:latest .
docker run --name deploy_fe --network mynetwork --ip 172.168.0.13 --rm \
  -v /home/$username/peviitor/build:/app/build fe:latest npm run build:local

rm -f /home/$username/peviitor/build/.htaccess

# Clone api repo
git clone --branch master --single-branch https://github.com/peviitor-ro/api.git /home/$username/peviitor/build/api/

# Write api.env file for API with Solr credentials
cat > /home/$username/peviitor/build/api/api.env <<EOF
LOCAL_SERVER=172.168.0.10:8983
PROD_SERVER=zimbor.go.ro
BACK_SERVER=https://api.laurentiumarian.ro/
SOLR_USER=$solr_user
SOLR_PASS=$solr_password
EOF

# Run Apache container
docker run --name apache-container --network mynetwork --ip 172.168.0.11 --restart=always -d -p 8081:80 \
  -v /home/$username/peviitor/build:/var/www/html alexstefan1702/php-apache

# --- Begin Solr Authentication and Setup ---

CORE_NAME=auth
CORE_NAME_2=jobs
CORE_NAME_3=logo
CONTAINER_NAME="solr-container"
SOLR_PORT=8983
SECURITY_FILE="/home/$username/peviitor/solr/core/data/security.json"

# Start Solr container
docker run --name $CONTAINER_NAME --network mynetwork --ip 172.168.0.10 --restart=always -d -p $SOLR_PORT:$SOLR_PORT \
  -v /home/$username/peviitor/solr/core/data:/var/solr/data solr:latest

echo "Waiting for Solr to start..."
sleep 10

sudo chmod -R 777 /home/$username/peviitor

# Create Solr cores
echo "Creating Solr cores..."
docker exec "$CONTAINER_NAME" bin/solr create_core -c "$CORE_NAME"
docker exec "$CONTAINER_NAME" bin/solr create_core -c "$CORE_NAME_2"
docker exec "$CONTAINER_NAME" bin/solr create_core -c "$CORE_NAME_3"

# Helper to add fields to Solr schema
add_solr_field() {
  local core=$1
  local json=$2
  docker exec "$CONTAINER_NAME" curl -s -X POST -H "Content-Type: application/json" --data "$json" "http://localhost:8983/solr/$core/schema"
}

# Add fields to 'jobs' core
echo "Adding fields to 'jobs' core..."
add_solr_field "$CORE_NAME_2" '{
  "add-field": [
    {"name": "job_link", "type": "text_general", "stored": true, "indexed": true, "multiValued": true, "uninvertible": true},
    {"name": "job_title", "type": "text_general", "stored": true, "indexed": true, "multiValued": true, "uninvertible": true},
    {"name": "company", "type": "text_general", "stored": true, "indexed": true, "multiValued": true, "uninvertible": true},
    {"name": "company_str", "type": "string", "stored": true, "indexed": true, "docValues": true, "uninvertible": true, "omitNorms": true, "omitTermFreqAndPositions": true, "sortMissingLast": true},
    {"name": "hiringOrganization.name", "type": "text_general", "stored": true, "indexed": true, "multiValued": true, "uninvertible": true},
    {"name": "country", "type": "text_general", "stored": true, "indexed": true, "multiValued": true, "uninvertible": true},
    {"name": "city", "type": "text_general", "stored": true, "indexed": true, "multiValued": true, "uninvertible": true},
    {"name": "county", "type": "text_general", "stored": true, "indexed": true, "multiValued": true, "uninvertible": true}
  ]
}'

# Add copy fields to 'jobs' core
echo "Adding copy fields to 'jobs' core..."
copy_fields=(
  '{"add-copy-field": {"source": "job_link", "dest": "_text_"}}'
  '{"add-copy-field": {"source": "job_title", "dest": "_text_"}}'
  '{"add-copy-field": {"source": "company", "dest": ["_text_", "company_str", "hiringOrganization.name"]}}'
  '{"add-copy-field": {"source": "hiringOrganization.name", "dest": "hiringOrganization.name_str"}}'
  '{"add-copy-field": {"source": "country", "dest": "_text_"}}'
  '{"add-copy-field": {"source": "city", "dest": "_text_"}}'
)

for field in "${copy_fields[@]}"; do
  add_solr_field "$CORE_NAME_2" "$field"
done

# Add fields to 'logo' core
echo "Adding fields to 'logo' core..."
add_solr_field "$CORE_NAME_3" '{
  "add-field": [
    {"name": "url", "type": "text_general", "stored": true, "indexed": true, "multiValued": true, "uninvertible": true}
  ]
}'

# Generate Solr BasicAuth credentials (dynamic!)
solr_cred=$(generate_solr_credential "$solr_password")

# Create security.json to enable authentication with dynamic credential
echo "Creating Solr security.json with dynamic credentials..."
cat <<EOF > "$SECURITY_FILE"
{
  "authentication": {
    "blockUnknown": true,
    "class": "solr.BasicAuthPlugin",
    "credentials": {
      "$solr_user": "$solr_cred"
    },
    "realm": "My Solr users",
    "forwardCredentials": false
  },
  "authorization": {
    "class": "solr.RuleBasedAuthorizationPlugin",
    "permissions": [
      {"name": "security-edit", "role": "admin"}
    ],
    "user-role": {
      "$solr_user": "admin"
    }
  }
}
EOF

docker cp "$SECURITY_FILE" "$CONTAINER_NAME":/var/solr/data/security.json

# Configure Suggester for 'jobs' core
echo "Configuring suggester for 'jobs' core..."
docker exec "$CONTAINER_NAME" curl -s -X POST -H "Content-Type: application/json" --data '{
  "add-searchcomponent": {
    "name": "suggest",
    "class": "solr.SuggestComponent",
    "suggester": {
      "name": "jobTitleSuggester",
      "lookupImpl": "FuzzyLookupFactory",
      "dictionaryImpl": "DocumentDictionaryFactory",
      "field": "job_title",
      "suggestAnalyzerFieldType": "text_general",
      "buildOnCommit": "true",
      "buildOnStartup": "false"
    }
  }
}' http://localhost:8983/solr/jobs/config

docker exec "$CONTAINER_NAME" curl -s -X POST -H "Content-Type: application/json" --data '{
  "add-requesthandler": {
    "name": "/suggest",
    "class": "solr.SearchHandler",
    "startup": "lazy",
    "defaults": {
      "suggest": "true",
      "suggest.dictionary": "jobTitleSuggester",
      "suggest.count": "10"
    },
    "components": ["suggest"]
  }
}' http://localhost:8983/solr/jobs/config

# Restart Solr container to apply changes
docker restart "$CONTAINER_NAME"

# --- Java and JMeter setup ---

echo "Checking Java installation..."
if type -p java &>/dev/null; then
  echo "Java is already installed:"
  java -version
else
  echo "Java not found. Installing OpenJDK 11..."
  sudo apt update
  sudo apt install -y openjdk-11-jdk
  java -version
fi

echo "Checking JMeter installation..."
if type -p jmeter &>/dev/null; then
  echo "JMeter is already installed:"
  jmeter --version
else
  echo "Installing JMeter..."
  sudo apt update
  sudo apt install -y jmeter libcanberra-gtk3-module wget
  sudo chown -R $USER:$USER /usr/share/jmeter
  sudo chmod -R a+rX /usr/share/jmeter

  wget https://dlcdn.apache.org/jmeter/binaries/apache-jmeter-5.6.3.tgz -O /tmp/apache-jmeter-5.6.3.tgz
  sudo tar --strip-components=1 -xvzf /tmp/apache-jmeter-5.6.3.tgz -C /usr/share/jmeter

  sudo wget -O /usr/share/jmeter/lib/ext/plugins-manager.jar https://jmeter-plugins.org/get/
  sudo chmod a+r /usr/share/jmeter/lib/ext/plugins-manager.jar

  jmeter --version
fi

# Run JMeter test plan
echo "Running JMeter tests..."
jmeter -n -t "$dir/migration.jmx"

echo "Script execution completed."
