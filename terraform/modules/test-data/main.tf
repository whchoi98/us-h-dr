resource "null_resource" "generate_data" {
  triggers = {
    data_size  = var.data_size_gb
    pg_host    = var.pg_host
    mongo_host = var.mongo_host
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Test data generation requires manual execution from VSCode Server."
      echo "Run: python3 /home/ec2-user/generate-test-data.py --size ${var.data_size_gb} --pg-host ${var.pg_host} --mongo-host ${var.mongo_host}"
    EOT
  }
}

output "instructions" {
  value = "SSH to VSCode Server (instance: ${var.vscode_instance_id}) and run: python3 generate-test-data.py --size ${var.data_size_gb} --pg-host ${var.pg_host} --mongo-host ${var.mongo_host}"
}
