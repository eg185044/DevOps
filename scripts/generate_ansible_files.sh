#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../terraform"
terraform output -raw ansible_inventory > ../ansible/inventory.ini
echo "Generated ansible/inventory.ini from Terraform outputs"
