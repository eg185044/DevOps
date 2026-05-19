param(
    [Parameter(Mandatory=$true)][string]$ControllerIp,
    [Parameter(Mandatory=$true)][string]$KeyPath,
    [string]$RemoteUser = "ubuntu"
)

$ErrorActionPreference = "Stop"

Write-Host "Creating project tarball..."
$tar = "aws-devops-cv-platform.tar.gz"
if (Test-Path $tar) { Remove-Item $tar -Force }

tar -czf $tar --exclude "terraform/.terraform" --exclude "terraform/*.tfstate" --exclude "terraform/terraform.tfvars" --exclude ".git" .

Write-Host "Uploading to controller $ControllerIp..."
scp -i $KeyPath $tar "$RemoteUser@$ControllerIp`:~/"

Write-Host "Extracting on controller..."
ssh -i $KeyPath "$RemoteUser@$ControllerIp" "rm -rf ~/aws-devops-cv-platform && mkdir -p ~/aws-devops-cv-platform && tar -xzf ~/$tar -C ~/aws-devops-cv-platform"

Write-Host "Done. SSH command:"
Write-Host "ssh -i `"$KeyPath`" $RemoteUser@$ControllerIp"
