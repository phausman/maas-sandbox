#!/usr/bin/env bash

set -x

echo "Installing packages"
sudo snap install jq
snap install maas --channel 2.7/stable