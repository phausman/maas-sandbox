#!/usr/bin/env bash

set -e

echo "Installing packages..."
snap install jq
snap install maas --channel 3.0/stable

# Install PostgreSQL for MAAS
apt-get update --yes
apt-get install --yes postgresql