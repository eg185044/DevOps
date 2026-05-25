# Run in VS Code PowerShell on Windows 11.
# Install tools manually first: Git, AWS CLI v2, Terraform, VS Code.

aws --version
terraform version
ssh -V

# Configure AWS credentials. Use IAM user/access key with limited permissions for this lab.
aws configure

# Generate SSH key if you do not already have erezg01.pem from AWS.
# In AWS Console: EC2 -> Key pairs -> Create key pair -> erezg01 -> .pem
# Save it under: C:\Users\YOUR_USER\.ssh\erezg01.pem

# Get your public IP for terraform.tfvars allowed_ssh_cidr.
(Invoke-WebRequest -UseBasicParsing https://checkip.amazonaws.com).Content.Trim()
