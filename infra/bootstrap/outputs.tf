output "state_bucket_name" {
  description = "S3 bucket for Terraform state — referenced by the backend block in every other infra/ directory"
  value       = aws_s3_bucket.tfstate.id
}

output "backend_config_snippet" {
  description = "Paste this into the terraform{} block of another config to use this backend"
  value       = <<-EOT
    backend "s3" {
      bucket       = "${aws_s3_bucket.tfstate.id}"
      key          = "<component>/terraform.tfstate"
      region       = "${var.aws_region}"
      encrypt      = true
      use_lockfile = true
    }
  EOT
}
