terraform {
  required_version = ">= 1.3.2"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.13.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.12.1"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.0.4"
    }
    #    argocd = {
    #      source = "oboukili/argocd"
    #      version = "6.1.1"
    #    }
  }
}