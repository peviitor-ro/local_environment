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

echo "Done."
