#!/bin/sh

set -eu

echo -n 'Installing config generator... '

# install crudini
yum -y -q install epel-release | grep -v "already installed and latest version" || true
yum -y -q install crudini | grep -v "already installed and latest version" || true

# deploy the initial config
cp -R -f share/Config ${STEAM_HOME}/

# fix ownership
chown -R steam.steam ${STEAM_HOME}/Config

# fix selinux context
restorecon -r ${STEAM_HOME}/Config

# easy access to stock config files
sudo -u steam sh -c 'ln -sfn ~/Steam/KF2Server/KFGame/Config ~/Config/Internal'

echo 'done.'
