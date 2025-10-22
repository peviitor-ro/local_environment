#!/bin/bash

dir=$(pwd)
repo_root=$(cd "$dir/../.." && pwd)

echo " ================================================================="
echo " ================= local environment installer ==================="
echo " ====================== peviitor.ro =============================="
echo " ================================================================="

brew install coreutils

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

echo " ================================================================="
echo " ===================== use those credentials ====================="
echo " ====================== for SOLR login ==========================="
echo " ================================================================="
echo "You entered user: $solr_user"
# Note: Avoid echoing passwords in real use.
echo "You entered password: $solr_password"

if ! command -v git >/dev/null 2>&1; then
    echo "Git is not installed. Attempting to install Git..."

    # Check if Homebrew is installed
    if ! command -v brew >/dev/null 2>&1; then
        echo "Homebrew is not installed. Please install Homebrew first:"
        echo '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
        exit 1
    fi

    # Install Git using Homebrew
    brew update
    brew install git

    echo "Git installed successfully:"
    git --version
else
    echo "Git is already installed."
    git --version
fi

   # Check if git installed successfully
    if command -v git &> /dev/null
    then
        echo "Git installed successfully."
    else
        echo "Failed to install Git. Please install it manually."
        exit 1
    fi

if ! command -v docker &> /dev/null
then
    echo "Docker is not installed. Attempting to install Docker..."

    # Check if Homebrew is installed
    if ! command -v brew &> /dev/null
    then
        echo "Homebrew is not installed. Please install Homebrew first:"
        echo '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
        exit 1
    fi

    # Install Docker Desktop using Homebrew Cask
    brew install --cask docker

    echo "Docker installed. Please start Docker Desktop from the Applications folder or via Spotlight."

    # Wait until user starts Docker Desktop because Docker daemon must be running
    echo "Waiting for Docker daemon to start..."
    while ! docker info > /dev/null 2>&1; do
        sleep 2
    done

    echo "Docker daemon is running."
fi

# Verify Docker installation
if command -v docker &> /dev/null
then
    echo "Docker installed successfully:"
    docker --version
else
    echo "Failed to install Docker. Please install it manually."
    exit 1
fi

if [ "$SUDO_USER" ]; then
    username=$SUDO_USER
else
    username=$USER
fi

rm -rf /Users/$username/peviitor

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

echo " --> building FRONTEND container. this will take a while..."


# Configurare
REPO="peviitor-ro/search-engine"
ASSET_NAME="build.zip"
TARGET_DIR="/Users/$username/peviitor"

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
 mkdir -p "$TARGET_DIR"
 chmod -R u+rwx ~/peviitor

ZK_CONFIG_TEMPLATE="$repo_root/config/zookeeper/zookeeper.env.example"
ZK_CONFIG_DIR="/Users/$username/peviitor/config"
ZK_DATA_DIR="/Users/$username/peviitor/zookeeper"

if [ -f "$ZK_CONFIG_TEMPLATE" ]; then
  mkdir -p "$ZK_CONFIG_DIR"
  if [ ! -f "$ZK_CONFIG_DIR/zookeeper.env" ]; then
    cp "$ZK_CONFIG_TEMPLATE" "$ZK_CONFIG_DIR/zookeeper.env"
    chown "$username":"staff" "$ZK_CONFIG_DIR/zookeeper.env" 2>/dev/null || true
    echo "Created Zookeeper placeholder config at $ZK_CONFIG_DIR/zookeeper.env"
  else
    echo "Existing Zookeeper config detected at $ZK_CONFIG_DIR/zookeeper.env; leaving in place."
  fi
fi

mkdir -p "$ZK_DATA_DIR/data" "$ZK_DATA_DIR/logs" "$ZK_DATA_DIR/certs"

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
rm -f "$TMP_FILE"

echo "Build-ul a fost actualizat cu succes în $TARGET_DIR"


echo "Folderul build a fost adus local și dezarhivat."
rm -f /Users/$username/peviitor/build/.htaccess

echo " --> cloning API repo from https://github.com/peviitor-ro/api.git"
git clone --depth 1 --branch master --single-branch https://github.com/peviitor-ro/api.git /Users/$username/peviitor/build/api

echo " --> creating api.env file for API"
cat > /Users/$username/peviitor/build/api/api.env <<EOF
LOCAL_SERVER = 172.168.0.10:8983
PROD_SERVER = zimbor.go.ro
BACK_SERVER = https://api.laurentiumarian.ro/
SOLR_USER = $solr_user
SOLR_PASS = $solr_password
EOF

echo " --> building APACHE WEB SERVER container for FRONTEND, API and SWAGGER-UI. this will take a while..."
docker run --name apache-container --network mynetwork --ip 172.168.0.11  --restart=always -d -p 8081:80 \
    -v /Users/$username/peviitor/build:/var/www/html alexstefan1702/php-apache-arm

# Modificarea URL-ului pentru swagger in containerul lui Alex Stefan
docker exec apache-container sed -i 's|url: "http://localhost:8080/api/v0/swagger.json"|url: "http://localhost:8081/api/v0/swagger.json"|g' /var/www/swagger-ui/swagger-initializer.js
docker restart apache-container



bash "$dir/solr-auth.sh" "$dir" "$solr_user" "$solr_password"

rm -f $dir/security.json
rm -f $dir/jmeter.log
echo " --> end of script execution  <-- "
