#!/usr/bin/env bash
set -euo pipefail
sudo apt-get update -y
sudo apt-get install -y software-properties-common git unzip curl python3-pip python3-venv docker.io
sudo add-apt-repository --yes --update ppa:ansible/ansible || true
sudo apt-get install -y ansible || pip3 install --user ansible
sudo systemctl enable --now docker
sudo usermod -aG docker ubuntu || true
ansible --version
