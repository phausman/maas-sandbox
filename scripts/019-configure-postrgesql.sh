#!/usr/bin/env bash

set -e

# This is based on https://maas.io/docs/snap/3.0/ui/maas-installation

MAAS_DBUSER=maas
MAAS_DBPASS=maas
MAAS_DBNAME=maas

echo "Setting up PostgreSQL..."

# Create a PostgreSQL user if it does not already exist
if [ -z $(sudo -u postgres psql postgres --tuples-only --no-align \
            -c "SELECT 1 FROM pg_roles WHERE rolname='$MAAS_DBUSER'") ] 
then
    sudo -u postgres \
        psql -c "CREATE USER \"$MAAS_DBUSER\" WITH ENCRYPTED PASSWORD '$MAAS_DBPASS'"
fi

# Create the MAAS database if it does not already exist
if ! sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw $MAAS_DBNAME
then
    sudo -u postgres createdb -O "$MAAS_DBUSER" "$MAAS_DBNAME"
fi


# Edit /etc/postgresql/10/main/pg_hba.conf and add a line for the newly
# created database, replacing the variables with actual names
if ! grep -qw "host    $MAAS_DBNAME    $MAAS_DBUSER    0/0     md5" \
        /etc/postgresql/12/main/pg_hba.conf
then
    tee -a /etc/postgresql/12/main/pg_hba.conf << EOF
host    $MAAS_DBNAME    $MAAS_DBUSER    0/0     md5
EOF
fi