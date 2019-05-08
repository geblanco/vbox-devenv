#!/bin/bash

# first boot, install various packages
apt update && apt upgrade -y
apt install -y ifupdown python3-pip
cp interfaces /etc/network/interfaces
systemctl restart networking

# install pipenv
pip3 install --user pipenv

# add user installed packages to PATH
echo "export PATH=$(python3 -m site --user-base)/bin:"'$PATH' >> ~/.bash_aliases

# install project... ToDo
