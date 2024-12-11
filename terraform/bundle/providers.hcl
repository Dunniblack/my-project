// https://github.com/hashicorp/terraform/blob/v0.15/tools/terraform-bundle/README.md

terraform {
  version = "1.9.8"
}

providers {
  azurerm = {
    source   = "hashicorp/azurerm"
    versions = ["~> 4.11.0"]
  }
  kubernetes = {
    source   = "hashicorp/kubernetes"
    versions = ["~> 2.33.0"]
  }
  helm = {
    source   = "hashicorp/helm"
    versions = ["~> 2.16.1"]
  }
  random = {
    source   = "hashicorp/random"
    versions = ["~> 3.6.3"]
  }
  local = {
    source   = "hashicorp/local"
    versions = ["~> 2.5.2"]
  }
  null = {
    source   = "hashicorp/null"
    versions = ["~> 3.2.3"]
  }
  tls = {
    source   = "hashicorp/tls"
    versions = ["~> 4.0.6"]
  }
  archive = {
    source   = "hashicorp/archive"
    versions = ["~> 2.6.0"]
  }
  external = {
    source   = "hashicorp/external"
    versions = ["~> 2.3.4"]
  }
  time = {
    source   = "hashicorp/time"
    versions = ["~> 0.12.1"]
  }
}