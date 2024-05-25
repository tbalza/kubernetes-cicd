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
}

################################################################################
# Argocd
################################################################################

# Dynamically load values from argocd's kustomization.yaml
locals {
  argocd_config = yamldecode(file("../../${path.module}/argo-apps/argocd/kustomization.yaml"))
  # IDE may show "unresolved reference" even though it's linked correctly in tf.
  argocd_helm_chart = local.argocd_config.helmCharts[0] # Access the first (or only) element in the list
}

output "argocd_helm_chart" {
  value = local.argocd_helm_chart
}

# Create namespace
resource "kubernetes_namespace" "argo_cd" {
  metadata {
    name = "argocd"
  }
}

resource "helm_release" "argo_cd" {
  # IDE may show "unresolved reference" even though it's linked correctly in tf.
  name       = local.argocd_helm_chart.name # "argo-cd"
  repository = local.argocd_helm_chart.repo # "https://argoproj.github.io/argo-helm"
  chart      = local.argocd_helm_chart.releaseName # "argo-cd"
  version    = local.argocd_helm_chart.version # "6.7.14" # pending reference this dynamically to argo-apps/argocd/config.yaml
  namespace = local.argocd_helm_chart.namespace # "argocd"

  values = [file("../../${path.module}/argo-apps/argocd/values.yaml")]

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn" # annotation to allows service account to assume aws role
    value = data.terraform_remote_state.eks.outputs.argo_cd_iam_role_arn
  }

  # Ensure that the Kubernetes namespace exists before deploying
  depends_on = [
    kubernetes_namespace.argo_cd,
    #data.terraform_remote_state.eks.outputs.eks, # pending. wait until node groups are provisioned before deploying argocd
    #data.terraform_remote_state.eks.outputs.eks_managed_node_groups # pending. wait until node groups are provisioned before deploying argocd
  ]
}

## ArgoCD apply ApplicationSet
## Uses directory generator to dynamically create argo-apps in subfolders
## Kustomize uses helmChart for 3rd party charts with local repo overrides (values.yaml) and load additional k8s manifests

resource "kubectl_manifest" "example_applicationset" {
  yaml_body = file("../../${path.module}/argo-apps/argocd/applicationset.yaml")

  depends_on = [
    helm_release.argo_cd # kubectl_manifest.kustomize_patch
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

