output "ansible_controller_public_ip" {
  value = aws_instance.ansible.public_ip
}

output "frontend_public_ip" {
  value = aws_instance.frontend.public_ip
}

output "backend_public_ip" {
  value = aws_instance.backend.public_ip
}

output "worker_public_ip" {
  value = aws_instance.worker.public_ip
}

output "frontend_private_ip" {
  value = aws_instance.frontend.private_ip
}

output "backend_private_ip" {
  value = aws_instance.backend.private_ip
}

output "worker_private_ip" {
  value = aws_instance.worker.private_ip
}

output "website_url_direct" {
  value = "http://${aws_instance.frontend.public_ip}"
}

output "website_url_nlb" {
  value = "http://${aws_lb.frontend_nlb.dns_name}"
}

output "nlb_dns_name" {
  value = aws_lb.frontend_nlb.dns_name
}

output "rds_endpoint" {
  value = var.create_rds ? aws_db_instance.postgres[0].address : "disabled"
}

output "s3_bucket_name" {
  value = aws_s3_bucket.cv.bucket
}

output "sns_topic_arn" {
  value = aws_sns_topic.events.arn
}

output "ansible_inventory" {
  value = <<EOT
[frontend]
frontend ansible_host=${aws_instance.frontend.private_ip} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/aviad-01.pem private_ip=${aws_instance.frontend.private_ip}

[backend]
backend ansible_host=${aws_instance.backend.private_ip} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/aviad-01.pem private_ip=${aws_instance.backend.private_ip}

[worker]
worker ansible_host=${aws_instance.worker.private_ip} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/aviad-01.pem private_ip=${aws_instance.worker.private_ip}

[app_servers:children]
frontend
backend
worker

[all:vars]
ansible_python_interpreter=/usr/bin/python3
aws_region=${var.aws_region}
backend_private_ip=${aws_instance.backend.private_ip}
worker_private_ip=${aws_instance.worker.private_ip}
rds_endpoint=${var.create_rds ? aws_db_instance.postgres[0].address : "disabled"}
db_name=${var.db_name}
db_username=${var.db_username}
s3_bucket_name=${aws_s3_bucket.cv.bucket}
sns_topic_arn=${aws_sns_topic.events.arn}
frontend_url=http://${aws_lb.frontend_nlb.dns_name}
EOT
}
