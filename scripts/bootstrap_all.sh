#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
cd terraform
terraform init
terraform fmt -recursive
terraform validate
terraform apply -auto-approve
terraform output -raw ansible_inventory > ../ansible/inventory.ini
cd ../ansible
ansible-playbook -i inventory.ini site.yml --ask-vault-pass
