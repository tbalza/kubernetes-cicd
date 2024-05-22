provider "aws" {
  region = data.terraform_remote_state.eks.outputs.region
}

###############################################################################
# Read state from eks cluster to extract outputs
###############################################################################

data "terraform_remote_state" "eks" {
  backend = "local" # Pending remote set up to enable collaboration, state locking etc.

  config = {
    path = "../01-eks-cluster/terraform.tfstate"
  }
}

###############################################################################
# Providers
###############################################################################

provider "kubernetes" {
  host                   = data.terraform_remote_state.eks.outputs.cluster_endpoint                                 # var.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.eks.outputs.cluster_certificate_authority_data) # var.cluster_ca_cert
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"                                                       # /v1alpha1"
    args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.eks.outputs.cluster_name] # var.cluster_name
    command     = "aws"
  }
}

provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.eks.outputs.cluster_endpoint                                 # var.cluster_endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.eks.outputs.cluster_certificate_authority_data) # var.cluster_ca_cert
    exec {
      api_version = "client.authentication.k8s.io/v1beta1" # /v1alpha1"
      args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.eks.outputs.cluster_name]
      command     = "aws"
    }
  }
}

provider "kubectl" {
  host                   = data.terraform_remote_state.eks.outputs.cluster_endpoint                                 # var.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.eks.outputs.cluster_certificate_authority_data) # var.cluster_ca_cert
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"                                                       # /v1alpha1"
    args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.eks.outputs.cluster_name] # var.cluster_name
    command     = "aws"
  }
  load_config_file = false
}

################################################################################
# Argocd
################################################################################

## Dynamically load values from argocd's config.yaml
locals {
  argocd_config = yamldecode(file("../../${path.module}/argo-apps/argocd/config.yaml"))
}

output "argocd_config" {
  value = local.argocd_config
}

## Create namespace
resource "kubernetes_namespace" "argo_cd" {
  metadata {
    name = "argocd"
  }
}

resource "helm_release" "argo_cd" {
  # IDE may show "unresolved reference" even though it's linked correctly in tf.
  name       = local.argocd_config.name # "argo-cd"
  repository = local.argocd_config.helmchart_url # "https://argoproj.github.io/argo-helm"
  chart      = local.argocd_config.chart # "argo-cd"
  version    = local.argocd_config.version # "6.7.14" # pending reference this dynamically to argo-apps/argocd/config.yaml
  namespace = local.argocd_config.app_namespace # "argocd"

  values = [file("../../${path.module}/argo-apps-kustomize/argocd/values.yaml")]

  # Ensure that the Kubernetes namespace exists before deploying
  depends_on = [
    kubernetes_namespace.argo_cd,
    #data.terraform_remote_state.eks.outputs.eks, # pending. wait until node groups are provisioned before deploying argocd
    #data.terraform_remote_state.eks.outputs.eks_managed_node_groups # pending. wait until node groups are provisioned before deploying argocd
  ]
}

## ArgoCD apply ApplicationSet

# Use kubectl to apply an ArgoCD ApplicationSet that dynamically deploys apps in argo-apps/ that contain a config.yaml
# Applies community managed helm charts with local repo overrides (values-override.yaml)

resource "kubectl_manifest" "example_applicationset" {
  yaml_body = file("../../${path.module}/argo-apps-kustomize/argocd/manifests/applicationset.yaml") # /../../argo-apps/argocd/applicationset.yaml

  depends_on = [
    helm_release.argo_cd
  ]
}






# Fix interdependencies for graceful provisioning and teardown ### check

#Yes absolutely, using depends_on in an output is 100% valid
#and used for exactly this kind of timing issue where an output for a single resource isn't fully available
#until some other resource completes. S3 bucket and bucket policy is another common one. Or IAM role and role attachments.

#output "cluster_endpoint" {
#  description = "Endpoint for your Kubernetes API server"
#  value       = data.terraform_remote_state.eks.outputs.cluster_endpoint # try(module.eks.cluster_endpoint, null)
#
#  depends_on = [
#    data.terraform_remote_state.eks.outputs.access_entries,
#    data.terraform_remote_state.eks.outputs.access_policy_associations,
#  ]
#}
#
#output "cluster_certificate_authority_data" {
#  description = "Base64 encoded certificate data required to communicate with the cluster"
#  value       = data.terraform_remote_state.eks.outputs.cluster_certificate_authority_data # try(aws_eks_cluster.this[0].certificate_authority[0].data, null)
#
#  depends_on = [
#    data.terraform_remote_state.eks.outputs.access_entries,
#    data.terraform_remote_state.eks.outputs.access_policy_associations,
#  ]
#}

