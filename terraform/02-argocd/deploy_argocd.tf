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

## Create namespace
resource "kubernetes_namespace" "argo_cd" {
  metadata {
    name = "argocd"
  }
}

resource "helm_release" "argo_cd" {
  name       = "argo-cd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "6.7.14" # pending reference this dynamically to argo-apps/argocd/config.yaml

  namespace = "argocd"

  values = [file("../../${path.module}/argo-apps/argocd/values-override-initial.yaml")]

  # Ensure that the Kubernetes namespace exists before deploying
  depends_on = [
    kubernetes_namespace.argo_cd, # to be removed as helm will create the namespace
    # data.terraform_remote_state.eks.outputs.eks_managed_node_groups # pending. wait until node groups are provisioned before deploying argocd
  ]
}

## Install argocd helm chart
#resource "helm_release" "argo_cd" {
#  name       = "argo-cd"
#  repository = "https://argoproj.github.io/argo-helm"
#  chart      = "argo-cd"
#  version    = "6.7.14" # Chart 6.7.14, app v v2.10.7
#
#  namespace = "argocd" # "argocd" # check
#
#
##    values = [
##    "https://raw.githubusercontent.com/tbalza/kubernetes-cicd/main/argo-apps/argocd/values-override.yaml"
##  ]
#
#  # ServiceAccount Role
#
#  set {
#    name  = "serviceAccount.create"
#    value = "true"
#  }
#
#  set {
#    name  = "serviceAccount.name"
#    value = "argocd-application-controller"
#  }
#
#  set {
#    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn" #check
#    value = data.terraform_remote_state.eks.outputs.argo_cd_iam_role_arn # reference cluster state
#  }
#
#  set {
#    name  = "serviceAccount.automountServiceAccountToken"
#    value = "true"
#  }
#
#  # CRDs
#
#  set {
#    name  = "crds.install"
#    value = "true"
#  }
#
#  set {
#    name  = "crds.keep"
#    value = "true" # true to not cause production problems
#  }
#
#  set {
#    name  = "server.service.type"
#    value = "ClusterIP"
#  }
#
#  set {
#    name  = "server.containerPorts.server" # change container port
#    value = "8282"
#  }
#
#  set {
#    name  = "server.extraArgs[0]" # check SSL
#    value = "--insecure"
#  }
#
#  set {
#    name  = "server.extraEnv[1].name" # check SLL
#    value = "ARGOCD_INSECURE"
#  }
#
#  set {
#    name  = "server.extraEnv[1].value" # check SSL
#    value = "true"
#  }
#
#  # ApplicationSet
#
#  set {
#    name  = "applicationSet.enabled" # check
#    value = "true"
#  }
#
#  set {
#    name  = "applicationSet.name"
#    value = "applicationset-controller"
#  }
#
#  set {
#    name  = "applicationSet.replicas"
#    value = "1"
#  }
#
#  ###### Node Selectors
#
#  set {
#    name  = "dex.server.nodeSelector.role" # check
#    value = "ci-cd"
#  }
#
#  set {
#    name  = "notifications.controller.nodeSelector.role" # check
#    value = "ci-cd"
#  }
#
#  # Node Selector Configurations for Controller
#  set {
#    name  = "controller.nodeSelector.role"
#    value = "ci-cd"
#  }
#
#  # Node Selector Configurations for Server
#  set {
#    name  = "server.nodeSelector.role"
#    value = "ci-cd"
#  }
#
#  # Node Selector Configurations for RepoServer
#  set {
#    name  = "repoServer.nodeSelector.role"
#    value = "ci-cd"
#  }
#
#  # Node Selector Configurations for ApplicationSet
#  set {
#    name  = "applicationSet.nodeSelector.role"
#    value = "ci-cd"
#  }
#
#  # check, pending: pass values creds/ssl etc
#  # https://stackoverflow.com/questions/73070417/how-to-pass-values-from-the-terraform-to-the-helm-chart-values-yaml-file
#
#  wait = true
#
#  depends_on = [
#    kubernetes_namespace.argo_cd
#  ]
#}

## Create argocd ALB ingress
#resource "kubernetes_ingress_v1" "argo_cd" {
#  metadata {
#    name      = "argocd-ingress"
#    namespace = "argocd"
#    annotations = {
#      "kubernetes.io/ingress.class"            = "alb"
#      "alb.ingress.kubernetes.io/scheme"       = "internet-facing"
#      "alb.ingress.kubernetes.io/target-type"  = "ip"
#      "alb.ingress.kubernetes.io/listen-ports" = jsonencode([{ HTTP = 80 }]) # jsonencode([{ HTTP = 80 }, { HTTPS = 443 }])
#      #"alb.ingress.kubernetes.io/tags"             = "Example=argocd"
#      "alb.ingress.kubernetes.io/healthcheck-path" = "/healthz"
#      "alb.ingress.kubernetes.io/group.name"       = "argo-cd-cluster" # prevent multiple ALB being created
#      "alb.ingress.kubernetes.io/group.order"      = "1"
#    }
#  }
#
#  spec {
#    rule {
#      http {
#        path {
#          path      = "/*"
#          path_type = "ImplementationSpecific"
#          backend {
#            service {
#              name = "argo-cd-argocd-server"
#              port {
#                number = 80
#              }
#            }
#          }
#        }
#      }
#    }
#  }
#  depends_on = [
#    #data.terraform_remote_state.eks.outputs.eks, # wait for cluster to be done
#    helm_release.argo_cd # wait for agocd to be deployed by helm before creating ingress.
#  ]
#}

## ArgoCD apply ApplicationSet

# Use kubectl to apply an ArgoCD ApplicationSet that dynamically deploys apps in argo-apps/ that contain a config.yaml
# Applies community managed helm charts with local repo overrides (values-override.yaml)






resource "kubectl_manifest" "example_applicationset" {
  yaml_body = file("${path.module}/applicationset.yaml") # /../../argo-apps/argocd/applicationset.yaml

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

