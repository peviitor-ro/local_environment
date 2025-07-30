#!/bin/bash

dir=$(pwd)

# Prompt for Solr username and password

# Function to validate the password against the specified policy
validate_password() {
  local password="$1"

  # Check length >= 15
  if [ ${#password} -ge 15 ]; then
    return 0
  fi

  # Check for lowercase letter
  if ! [[ $password =~ [a-z] ]]; then
    return 1
  fi

  # Check for uppercase letter
  if ! [[ $password =~ [A-Z] ]]; then
    return 1
  fi

  # Check for digit
  if ! [[ $password =~ [0-9] ]]; then
    return 1
  fi

  # Check for special character from the set !@#$%^&*_-[]()
  if ! [[ $password =~ [\!\@\#\$\%\^\&\*\_\-\[\]\(\)] ]]; then
    return 1
  fi

  return 0
}

# Prompt for Solr username and password with validation
read -p "Enter the Solr username: " solr_user

while true; do
  read -sp "Enter the Solr password: " solr_password
  echo
  if validate_password "$solr_password"; then
    echo "Password accepted."
    break
  else
    echo "Password must be at least 15 characters long OR contain at least one lowercase letter, one uppercase letter, one digit, and one special character (!@#$%^&*_-[]()). Please try again."
  fi
done

echo "You entered user: $solr_user"
# Note: Avoid echoing passwords in real use.

if ! command -v git &> /dev/null
then
    echo "Git is not installed. Attempting to install Git..."

    # Detect package manager and install Git
    if command -v apt &> /dev/null
    then
        sudo apt update
        sudo apt install -y git
    elif command -v apt-get &> /dev/null
    then
        sudo apt-get update
        sudo apt-get install -y git
    elif command -v yum &> /dev/null
    then
        sudo yum install -y git
    else
        echo "Could not find a supported package manager (apt, apt-get, or yum). Please install Git manually."
        exit 1
    fi

    # Check if git installed successfully
    if command -v git &> /dev/null
    then
        echo "Git installed successfully."
    else
        echo "Failed to install Git. Please install it manually."
        exit 1
    fi
fi


if ! command -v docker &> /dev/null
then
    echo "Docker is not installed. Attempting to install Docker..."

    if command -v apt &> /dev/null
    then
        sudo apt update
        sudo apt install -y \
            ca-certificates \
            curl \
            gnupg \
            lsb-release

        # Add Docker’s official GPG key and set up the stable repository
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
          $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

        sudo apt update
        sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    elif command -v apt-get &> /dev/null
    then
        sudo apt-get update
        sudo apt-get install -y \
            ca-certificates \
            curl \
            gnupg \
            lsb-release

        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
          $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    elif command -v yum &> /dev/null
    then
        sudo yum install -y yum-utils
        sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        sudo yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        sudo systemctl start docker
        sudo systemctl enable docker

    else
        echo "Could not find a supported package manager (apt, apt-get, or yum). Please install Docker manually."
        exit 1
    fi

    # Verify Docker installation
    if command -v docker &> /dev/null
    then
        echo "Docker installed successfully."
    else
        echo "Failed to install Docker. Please install it manually."
        exit 1
    fi
fi


if [ "$SUDO_USER" ]; then
    username=$SUDO_USER
else
    username=$USER
fi

sudo rm -rf /home/$username/peviitor

echo "Remove existing containers if they exist"
for container in apache-container solr-container data-migration deploy-fe
do
  if [ "$(docker ps -aq -f name=$container)" ]; then
    docker stop $container
    docker rm $container
  fi
done

network='mynetwork'

# Verifică dacă rețeaua există
if [ ! -z "$(docker network ls | grep $network)" ]; then
  echo "Network $network exists, removing..."
  docker network rm $network
fi

# Creează rețeaua nouă
echo "Creating network $network..."
docker network create --subnet=172.168.0.0/16 $network


git clone --depth 1 --branch main --single-branch https://github.com/peviitor-ro/search-engine.git /home/$username/peviitor/search-engine
ENV_FILE="/home/$username/peviitor/search-engine/env/.env.local"

sed -i 's|http://localhost:8080|http://localhost:8081|g' "$ENV_FILE"

cd /home/$username/peviitor/search-engine
docker build -t fe:latest .
docker run --name deploy_fe --network mynetwork --ip 172.168.0.13 --rm \
    -v /home/$username/peviitor/build:/app/build fe:latest npm run build:local
rm -f /home/$username/peviitor/build/.htaccess

git clone --branch master --single-branch https://github.com/peviitor-ro/api.git /home/$username/peviitor/build/api/

cat > /home/$username/peviitor/build/api/api.env <<EOF
LOCAL_SERVER = 172.168.0.10:8983
PROD_SERVER = zimbor.go.ro
BACK_SERVER = https://api.laurentiumarian.ro/
SOLR_USER = $solr_user
SOLR_PASS = $olr_password
EOF



docker run --name apache-container --network mynetwork --ip 172.168.0.11  --restart=always -d -p 8081:80 \
    -v /home/$username/peviitor/build:/var/www/html alexstefan1702/php-apache

bash "$dir/solr-auth.sh" "$dir" "$solr_user" "$solr_password"

echo "Script execution completed."
