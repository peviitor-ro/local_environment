#!/bin/bash

# Prevent running script as root
if [ "$EUID" -eq 0 ]; then
  echo "Please run this script as a normal user, NOT as root or with sudo."
  exit 1
fi

dir=$(pwd)

echo " ================================================================="
echo " ================= local environment installer ==================="
echo " ====================== peviitor.ro =============================="
echo " ================================================================="

# Check if Homebrew is installed, install if needed
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not found. Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Reload shell environment for brew to work immediately
  eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null)"
else
  echo "Homebrew is already installed."
fi

# Check if coreutils is installed, install if needed
if command -v gls >/dev/null 2>&1; then
  echo "coreutils is already installed"
else
  echo "coreutils is not installed. Installing..."
  brew install coreutils
fi

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
echo "You entered password: $solr_password"

# Check if Git is installed
if ! command -v git >/dev/null 2>&1; then
  echo "Git is not installed."

  # Install Xcode Command Line Tools if not installed
  if ! xcode-select -p >/dev/null 2>&1; then
    echo "Installing Xcode Command Line Tools (includes Git)..."
    xcode-select --install
    echo "Please complete installation and rerun the script."
    exit 1
  else
    echo "Xcode Command Line Tools installed but Git not found. Please check manually."
    exit 1
  fi
else
  echo "Git is installed."
fi

# Install or upgrade Git via Homebrew
echo "Installing/upgrading Git using Homebrew..."
brew install git || brew upgrade git


if ! command -v docker &> /dev/null
then
    echo "Docker is not installed. Attempting to install Docker..."

    # Check for Homebrew and install if missing
    if ! command -v brew &> /dev/null
    then
        echo "Homebrew not found. Installing Homebrew first..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        # Reload shell environment so brew works immediately
        eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null)"
    fi

    # Install Docker Desktop via Homebrew Cask
    echo "Installing Docker Desktop..."
    brew install --cask docker

    echo "Docker Desktop installed. Please open Docker.app from your Applications folder to finish setup."
else
    echo "Docker is already installed."
fi

username=${SUDO_USER:-$USER}

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
TARGET_DIR="/Users/$username/peviitor"

# Create with sudo if outside user home
sudo mkdir -p "$TARGET_DIR"

# If you want to ensure you have rwx permissions in your ~/peviitor folder
chmod -R u+rwx ~/peviitor

TMP_FILE="/tmp/$ASSET_NAME"

# Fișier temporar pentru arhivă
brew install wget
echo "Descarc $ASSET_NAME..."
wget -q --show-progress "$DOWNLOAD_URL" -O "$TARGET_DIR"
if [ $? -ne 0 ]; then
  echo "EROARE la descărcare."
  exit 1
fi

