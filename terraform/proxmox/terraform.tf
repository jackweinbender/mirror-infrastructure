terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.111"
    }
  }

  backend "s3" {
    bucket = "tf-backend-61rckk"
    key    = "proxmox.tfstate"
    region = "us-east-1"
  }
}
