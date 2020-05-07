#!/usr/bin/env bash

set -xe

# Generate key if it not exist yet
echo "Generating SSH key..."
if [[ ! -f "/home/vagrant/.ssh/id_rsa" ]]
then
    ssh-keygen -q -t rsa -f /home/vagrant/.ssh/id_rsa -N ""
    chown -R vagrant:vagrant /home/vagrant/.ssh/
else
    echo "SSH key already exists, skipping"
fi

# The key must be injected into maas.supervisor namespace, instead on regular
# root user's home directory. This must be run after installing MAAS
# snap because the key will be injected into snap-created directory. If we
# had created this directory earlier, the snap would fail to install.
echo "Installing host's private SSH key in /var/snap/maas/current/root/.ssh/id_rsa"
mkdir -p /var/snap/maas/current/root/.ssh
mv /tmp/vagrant/id_rsa /var/snap/maas/current/root/.ssh/
chown root:root /var/snap/maas/current/root/.ssh/id_rsa
chmod 400 /var/snap/maas/current/root/.ssh/id_rsa