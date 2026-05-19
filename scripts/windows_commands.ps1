# Windows 11 helper commands
# Run from VS Code PowerShell terminal.

terraform version
aws --version

cd terraform
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
terraform output -raw ansible_inventory > ../ansible/inventory.ini
