terraform {
  required_version = ">= 1.6"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.56"
    }
  }

  cloud {
    hostname     = "app.terraform.io"
    organization = "AcademicCultureEnjoyers"

    workspaces {
      name = "ilmomasiina"
    }

  }
}

provider "hcloud" {
  token = var.hcloud_token
}
