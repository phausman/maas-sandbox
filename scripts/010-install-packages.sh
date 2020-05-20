#!/usr/bin/env bash

set -x

echo "Installing packages"
snap install jq
snap install maas --channel 2.7/stable