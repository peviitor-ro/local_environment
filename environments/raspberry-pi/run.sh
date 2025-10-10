#!/bin/bash

dir=$(pwd)

echo "================================================================="
echo "                      Local environment                          "
echo "                          peviitor.ro                            "
echo "================================================================="

sudo apt-get install coreutils -y

if ! command -v apt >/dev/null 2>&1; then
    echo -e "You are not running on a Debian-based system. Please run this script on a Debian-based system."
    exit 1
fi

# Function to create swap space
create_swap() {
  local swap_size=$1
  
  # Check if swap already exists
  if [[ $(swapon --show) ]]; then
    echo "Swap space already exists. Skipping swap creation."
    return 0
  fi
  
  # Create swap file
  echo "Creating ${swap_size} swap space..."
  sudo fallocate -l "${swap_size}" /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  
  # Make swap permanent
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
  
  # Set swappiness
  sudo sysctl vm.swappiness=10
  echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
  
  echo "Swap space of ${swap_size} created successfully."
}

# Ask user if they want to create swap space
read -p "Do you want to create a swap space? (y/n): " create_swap_choice

if [[ "$create_swap_choice" == "y" || "$create_swap_choice" == "Y" ]]; then
  read -p "Enter swap size (e.g., 2G, 4G) [default: 2G]: " swap_size
  if [[ -z "$swap_size" ]]; then
    swap_size="2G"
  fi
  create_swap "$swap_size"
fi

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
  if validate_password "$solr_password"; then
    echo -e "\n[~] Password accepted."
    break
  else
    echo -e "\n[~] Password must be strong. Try again!"
  fi
done

echo "================================================================="
echo "                        Apache Solr login                        "
echo "                          peviitor.ro                            "
echo "================================================================="

echo "You entered user: $solr_user"
# Parola nu este afișată pentru motive de securitate

if ! command -v git &> /dev/null; then
    if command -v apt &> /dev/null; then
        sudo apt update && sudo apt install -y git
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y git
    elif command -v yum &> /dev/null; then
        sudo yum install -y git
    elif command -v pacman &> /dev/null; then
        sudo pacman -Syu --noconfirm git
    elif command -v apk &> /dev/null; then
        sudo apk add git
    else
        echo "No known package manager found."
        exit 1
    fi

    if command -v git &> /dev/null; then
        echo "--> git was installed successfully."
    else
        exit 1
    fi
else
    echo "--> git is already installed."
fi

if ! command -v unzip &> /dev/null; then
    if command -v apt &> /dev/null; then
        sudo apt update && sudo apt install -y unzip
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y unzip
    elif command -v yum &> /dev/null; then
        sudo yum install -y unzip
    elif command -v pacman &> /dev/null; then
        sudo pacman -Syu --noconfirm unzip
    elif command -v apk &> /dev/null; then
        sudo apk add unzip
    else
        echo "No known package manager found."
        exit 1
    fi

    if command -v unzip &> /dev/null; then
        echo "--> unzip was installed successfully."
    else
        exit 1
    fi
else
    echo "--> unzip is already installed."
fi

if ! command -v docker &> /dev/null
then
    echo "Docker is not installed. Attempting to install Docker..."

    # Check Docker version if already installed
    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version)
        echo "Docker is already installed: $DOCKER_VERSION"
    else
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
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg   | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            echo \
              "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu   \
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
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg   | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            echo \
              "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu   \
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

#echo " --> cloning repo from https://github.com/peviitor-ro/search-engine.git"
#git clone --depth 1 --branch main --single-branch https://github.com/peviitor-ro/search-engine.git /home/$username/peviitor/search-engine


echo " --> building FRONTEND container. this will take a while..."


# Configurare
REPO="peviitor-ro/search-engine"
ASSET_NAME="build.zip"
TARGET_DIR="/home/$username/peviitor"

echo "Caut link-ul pentru $ASSET_NAME din ultimul release GitHub al repo-ului $REPO..."

# Obține URL-ul download pentru build.zip din ultimul release
DOWNLOAD_URL=$(curl -s "https://api.github.com/repos/$REPO/releases/latest" \
  | grep "browser_download_url" \
  | grep "$ASSET_NAME" \
  | cut -d '"' -f 4)

if [ -z "$DOWNLOAD_URL" ]; then
  echo "EROARE: Nu am găsit URL-ul pentru \"$ASSET_NAME\" în ultimul release."
  exit 1
fi

echo "Download URL găsit: $DOWNLOAD_URL"

# Creează folderul țintă dacă nu există
sudo mkdir -p "$TARGET_DIR"
sudo chmod -R u+rwx ~/peviitor


# Fișier temporar pentru arhivă
TMP_FILE="/tmp/$ASSET_NAME"

echo "Descarc $ASSET_NAME..."
wget -q --show-progress "$DOWNLOAD_URL" -O "$TMP_FILE"
if [ $? -ne 0 ]; then
  echo "EROARE la descărcare."
  exit 1
fi

echo "Dezarhivez arhiva în: $TARGET_DIR"
unzip -o "$TMP_FILE" -d "$TARGET_DIR"
if [ $? -ne 0 ]; then
  echo "EROARE la dezarhivare."
  exit 1
fi

# Șterge arhiva temporară
sudo rm -f "$TMP_FILE"

echo "Build-ul a fost actualizat cu succes în $TARGET_DIR"

echo "Folderul build a fost adus local și dezarhivat."
rm -f /home/$username/peviitor/build/.htaccess

echo " --> cloning API repo from https://github.com/peviitor-ro/api.git"
git clone --depth 1 --branch master --single-branch https://github.com/peviitor-ro/api.git /home/$username/peviitor/build/api/

echo " --> creating api.env file for API"
API_ENV_FILE="/home/$username/peviitor/build/api/api.env"
if [ ! -f "$API_ENV_FILE" ]; then
  cat > "$API_ENV_FILE" <<EOF
LOCAL_SERVER = 172.168.0.10:8983
PROD_SERVER = zimbor.go.ro
BACK_SERVER = https://api.laurentiumarian.ro/
SOLR_USER = $solr_user
SOLR_PASS = $solr_password
EOF
else
  echo " --> api.env file already exists. Skipping creation."
fi

echo " --> building APACHE WEB SERVER container for FRONTEND, API and SWAGGER-UI. this will take a while..."
docker run --name apache-container --network mynetwork --ip 172.168.0.11  --restart=always -d -p 8081:80 \
    -v /home/$username/peviitor/build:/var/www/html alexstefan1702/php-apache-arm


# Modificarea URL-ului pentru swagger in containerul lui Alex Stefan
sudo docker exec apache-container sed -i 's|url: "http://localhost:8080/api/v0/swagger.json"|url: "http://localhost:8081/api/v0/swagger.json"|g' /var/www/swagger-ui/swagger-initializer.js
sudo docker exec apache-container sed -i 's|url: "http://localhost:8081/api/v0/swagger.json"|Curl: "http://zimbor.go.ro:8091/api/v1/swagger.json"|g' /var/www/swagger-ui/swagger-initializer.js
docker restart apache-container


bash "$dir/solr-auth.sh" "$dir" "$solr_user" "$solr_password"

rm -f $dir/security.json
rm -f $dir/jmeter.log
