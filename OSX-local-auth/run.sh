#!/bin/bash

dir=$(pwd)


echo " ================================================================="
echo " ================= local environment installer ==================="
echo " ====================== peviitor.ro =============================="
echo " ================================================================="

#check if homebrew is installed, otherwise will be automatically installed
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not found. Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
  echo "Homebrew is already installed."
fi

#check if coreutils is installed, otherwise will be automatically installed
if command -v gls >/dev/null 2>&1; then
  echo "coreutils is already installed"
else
  echo "coreutils is not installed. Installing..."
  brew install coreutils
fi

#!/bin/bash

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

# Note: Avoid echoing passwords in real use.
echo "You entered password: $solr_password"

# Install homebrew packing manager
if ! command -v git > /dev/null 2>&1
then
    echo "Git is not installed."

    if ! xcode-select -p > /dev/null 2>&1
    then
        echo "Installing Xcode Command Line Tools (includes Git)..."
        xcode-select --install
        echo "Please complete Xcode Command Line Tools installation and then rerun this script."
        exit 1
    else
        echo "Xcode Command Line Tools installed but Git not found. Please check manually."
        exit 1
    fi
else
    echo "Git is installed."
fi

if ! command -v brew > /dev/null 2>&1
then
    echo "Homebrew not found. Installing Homebrew..."
    # Run install script as regular user (do NOT use sudo)
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
    echo "Homebrew is already installed."
fi

echo "Installing/upgrading Git with Homebrew (as normal user)..."
# No sudo here, run brew as regular user
brew install git || brew upgrade git

echo "Done."


