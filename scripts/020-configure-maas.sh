#!/usr/bin/env bash

set -e

# $1: MAAS_IP
# $2: OAM_DYNAMIC_RANGE_START
# $3: OAM_DYNAMIC_RANGE_END
# $4: OAM_RESERVED_RANGE_START
# $5: OAM_RESERVED_RANGE_END
# $6: HOST_USERNAME
# $7: HOST_IP
# $8: OAM_NETWORK_PREFIX
# $9: CLOUD_NODES_COUNT
# $10: LOCAL_IMAGE_MIRROR_URL

MAAS_DBUSER=maas
MAAS_DBPASS=maas
MAAS_DBNAME=maas

# Initialize MAAS
echo "Initializing MAAS..."
if ! (maas apikey --username root > /dev/null 2>&1)
then
    maas init region+rack \
        --maas-url http://localhost:5240/MAAS/ \
        --database-uri "postgres://$MAAS_DBUSER:$MAAS_DBPASS@localhost/$MAAS_DBNAME"
    maas createadmin --username root --password root --email root@localhost.localdomain
else
    echo "MAAS already initialized, skipping"
fi

# Wait until MAAS endpoint URL is available
while nc -z localhost 5240 ; [ $? -ne 0 ] 
do
    echo "MAAS endpoint URL is not available yet, waiting 10s..."
    sleep 10
done

# Log into MAAS
echo "Logging into MAAS..."
maas login root http://localhost:5240/MAAS $(maas apikey --username root)

# Use local image mirror, if configured
if [ ! -z ${10} ]
then
    echo "Requesting MAAS to stop importing images before updating" \
         "boot-source with local image mirror URL..."
    maas root boot-resources stop-import

    while [ $(maas root boot-resources is-importing) != "false" ]
    do 
        echo "MAAS is still importing images. Requesting MAAS to stop" \
             "importing images (again) and waiting 30s..."
        maas root boot-resources stop-import
        sleep 30
    done
    
    echo "Updating boot-source to point to local image mirror..."
    maas root boot-source update 1 url="${10}"
fi

# Add Ubuntu 18.04 Bionic Beaver to boot sources if not already added
if [ -z $(maas root boot-source-selections read 1 | \
            jq '.[] | select(."release" == "bionic") | ."id"') ]
then
    maas root boot-source-selections create 1 \
        os="ubuntu" release="bionic" arches="amd64" \
        subarches="*" labels="*"
fi

# Start importing images
echo "Requesting MAAS to import images..."
maas root boot-resources import

# Import local SSH key to MAAS, if not already imported
echo "Importing SSH key..."
if ! (maas root sshkeys read | grep "$(</home/vagrant/.ssh/id_rsa.pub)")
then
    maas root sshkeys create "key=$(</home/vagrant/.ssh/id_rsa.pub)"
else
    echo "SSH key already imported, skipping"
fi

# Skip intro
echo "Configuring 'completed_intro'..."
maas root maas set-config name=completed_intro value=true

# Create reserved dynamic range for OAM network (if it does not exist already)
echo "Creating dynamic range..."
RESULT=$(maas root ipranges read | \
    jq ".[] | select((.type==\"dynamic\") and (.start_ip==\"$2\") and (.end_ip==\"$3\")) | .id")
if [ -z ${RESULT} ]
then
    maas root ipranges create type=dynamic start_ip=$2 end_ip=$3
else
    echo "Dynamic range already created, skipping"
fi

# Create reserved range for MAAS server and networking equipment
echo "Creating reserved range..."
RESULT=$(maas root ipranges read | \
    jq ".[] | select((.type==\"reserved\") and (.start_ip==\"$4\") and (.end_ip==\"$5\")) | .id")
if [ -z ${RESULT} ]
then
    maas root ipranges create type=reserved start_ip=$4 end_ip=$5
else
    echo "Reserved range already created, skipping"
fi

# Provide DHCP for OAM network subnet
echo "Configuring DHCP for OAM network..."
maas root vlan update 1 untagged primary_rack=maas dhcp_on=True

# Configure default gateway for OAM network
echo "Configuring gateway for OAM network..."
maas root subnet update ${8}0/24 gateway_ip=${8}1

# Disable 'Automatically sync images'
echo "Disabling 'Automatically sync images'..."
maas root maas set-config name=boot_images_auto_import value=false

# Wait until MAAS finished importing images
echo "Waiting for MAAS to finish importing images..."
while [ $(maas root boot-resources is-importing) != "false" ]
do 
    echo "MAAS is still importing images, waiting 30s..."
    sleep 30
done

# Wait until Rack Controller finishes syncing images
echo "Waiting for Rack Controller to finish synchronizing the images "; 
RACK_CONTROLLER_ID=$(maas root region-controllers read | \
    jq --raw-output '.[] | .system_id')
while [ $(maas root rack-controller list-boot-images $RACK_CONTROLLER_ID | \
    jq --raw-output '.status') != "synced" ]
do 
    echo "MAAS Rack is still synchronizing images, waiting 30s..."
    sleep 30
done

# Create nodeNN nodes
echo "Creating machines..."
for i in $(seq 1 ${9})
do
    # Check if the machine exists
    NODE_NUM=$(printf %02d ${i})
    MACHINE=$(maas root machines read hostname=node${NODE_NUM} | jq '.[] | .system_id')

    if [ -z ${MACHINE} ]
    then
        maas root machines create \
            architecture="amd64/generic" \
            mac_addresses="0e:00:00:00:00:${NODE_NUM}" \
            hostname=node${NODE_NUM} \
            power_type=virsh power_parameters='{"power_address": "qemu+ssh://'${6}'@'${7}'/system", "power_id": "node'${NODE_NUM}'"}'
    else
        echo "Machine node${NODE_NUM} already exists, skipping"
    fi
done

# Reset power of the machines so that they can start commissioning
echo "Power cycling machines..."
for i in $(seq 1 ${9})
do
    # Check if the machine exists
    NODE_NUM=$(printf %02d ${i})
    MACHINE=$(maas root machines read hostname=node${NODE_NUM} | \
        jq --raw-output '.[] | .system_id')

    if [ ! -z ${MACHINE} ]
    then
        # Query machine status
        MACHINE_STATUS=$(maas root machine read ${MACHINE} | \
            jq --raw-output '.status_name')

        # Skip commissioning if the machine is already commissioned and
        # in 'Ready' state
        if [ ${MACHINE_STATUS} == "Ready" ]
        then
            echo "Machine \'node${NODE_NUM}\' (${MACHINE}) is already" \
                 "commissioned, skipping..."
            continue
        fi

        if [ ${MACHINE_STATUS} == "Commissioning" ]
        then
            # Abort automatic commissioning after the node has been created
            maas root machine abort ${MACHINE}
        fi

        # Query power state
        POWER_STATE=$(maas root machine query-power-state ${MACHINE} | \
            jq --raw-output '.state')

        # Power off the machine if it is on
        while [ ${POWER_STATE} != "off" ]
        do
            echo "Powering off machine \'node${NODE_NUM}\' (${MACHINE})"
            maas root machine power-off ${MACHINE}

            POWER_STATE=$(maas root machine query-power-state ${MACHINE} | \
                jq --raw-output '.state')
        done

        echo "Requesting commissioning of the machine \'node${NODE_NUM}\' (${MACHINE})"
        maas root machine commission ${MACHINE}
    else
        echo "WARNING: Machine node${NODE_NUM} does not exist, skipping"
    fi
done