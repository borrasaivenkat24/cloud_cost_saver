terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket       = "venkat-tfstate-12345" # your state bucket
    key          = "cloud-cost-saver/terraform.tfstate"
    region       = "ap-south-1"
    use_lockfile = true
  }
}

provider "aws" {
  region = "ap-south-1"
}

variable "site_bucket_name" {
  type = string
}

variable "alert_email" {
  type      = string
  sensitive = true
}

module "static_site" {
  source      = "./modules/static-site"
  bucket_name = var.site_bucket_name
  index_file  = "${path.root}/site/index.html"
}

module "ec2_scheduler" {
  source           = "./modules/ec2-scheduler"
  name             = "ec2-cost-saver"
  lambda_source    = "${path.root}/lambda/stop_instances.py"
  schedule         = "cron(30 16 * * ? *)" # 16:30 UTC = 10:00 PM IST
  target_tag_value = "dev"
  site_bucket_name = module.static_site.bucket_name
  site_bucket_arn  = module.static_site.bucket_arn
  alert_email      = var.alert_email
}

output "website_url" {
  value = module.static_site.website_url
}

output "lambda_name" {
  value = module.ec2_scheduler.function_name
}