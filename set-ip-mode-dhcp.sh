#!/bin/bash

NODE_NAME=$1
FABRIC_NAME=$2
SUBNET=$3

# Get SYSTEM_ID
SYSTEM_ID=$(maas admin machines read hostname=$NODE_NAME | jq '.[] | .system_id' | tr -d '"')

# Get interface number
INTERFACE_ID=$(maas admin interfaces read $SYSTEM_ID | jq ".[] | {id:.id, fabric:.vlan.fabric}" --compact-output | grep fabric-0 | jq '.id')

# Set interface IP mode DHCP
maas admin interface link-subnet $SYSTEM_ID $INTERFACE_ID mode=dhcp subnet=${SUBNET}
