#!/bin/bash

# Turn off all swap
sudo swapoff -a

# Remove existing /swapfile if it exists
if [ -f /swapfile ]; then
  echo "Removing existing /swapfile ..."
  sudo rm /swapfile
fi

# Create a new 6GB swapfile
echo "Creating 6GB swapfile at /swapfile ..."
sudo fallocate -l 6G /swapfile

# If fallocate failed, use dd as fallback
if [ $? -ne 0 ]; then
  echo "fallocate failed, using dd to create swapfile ..."
  sudo dd if=/dev/zero of=/swapfile bs=1M count=6144
fi

# Set permissions
echo "Setting swapfile permissions ..."
sudo chmod 600 /swapfile

# Setup swap area
echo "Setting up swap area ..."
sudo mkswap /swapfile

# Enable the swapfile
echo "Enabling swapfile ..."
sudo swapon /swapfile

# Backup fstab if not backed up already
if [ ! -f /etc/fstab.backup ]; then
  echo "Backing up /etc/fstab to /etc/fstab.backup ..."
  sudo cp /etc/fstab /etc/fstab.backup
fi

# Add swapfile entry to /etc/fstab if not present
if ! grep -q '/swapfile' /etc/fstab; then
  echo "Adding /swapfile entry to /etc/fstab ..."
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
else
  echo "/swapfile entry already exists in /etc/fstab."
fi

# Show swap status
echo "Current swap status:"
sudo swapon --show
free -h
