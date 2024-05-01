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

################################################################################
# Argocd
################################################################################

## Create namespace
resource "kubernetes_namespace" "argo_cd" {
  metadata {
    name = "argocd"
  }
}

## Install argocd helm chart
resource "helm_release" "argo_cd" {
  name       = "argo-cd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "6.7.14" # Chart 6.7.14, app v v2.10.7

  namespace = "argocd" # "argocd" # check

  set {
    name  = "crds.install"
    value = "true"
  }

  set {
    name  = "crds.keep"
    value = "true" # true to not cause production problems
  }

  set {
    name  = "server.service.type"
    value = "ClusterIP"
  }

  set {
    name  = "server.containerPorts.server" # change container port
    value = "8282"
  }

  set {
    name  = "server.extraArgs[0]" # check SSL
    value = "--insecure"
  }

  set {
    name  = "server.extraEnv[1].name" # check SLL
    value = "ARGOCD_INSECURE"
  }

  set {
    name  = "server.extraEnv[1].value" # check SSL
    value = "true"
  }

  # Repository configuration
  set_sensitive {
    name  = "configs.repositories.my-git-repo"
    value = <<EOF
url: https://github.com/tbalza/kubernetes-cicd
type: git
name: kubernetes-cicd
EOF
  }

  wait = true

  depends_on = [
    kubernetes_namespace.argo_cd
  ]
}

## Create argocd ALB ingress
resource "kubernetes_ingress_v1" "argo_cd" {
  metadata {
    name      = "argocd-ingress"
    namespace = "argocd"
    annotations = {
      "kubernetes.io/ingress.class"            = "alb"
      "alb.ingress.kubernetes.io/scheme"       = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"  = "ip"
      "alb.ingress.kubernetes.io/listen-ports" = jsonencode([{ HTTP = 80 }]) # jsonencode([{ HTTP = 80 }, { HTTPS = 443 }])
      #"alb.ingress.kubernetes.io/tags"             = "Example=argocd"
      "alb.ingress.kubernetes.io/healthcheck-path" = "/healthz"
      "alb.ingress.kubernetes.io/group.name"       = "argo-cd-cluster" # prevent multiple ALB being created
      "alb.ingress.kubernetes.io/group.order"      = "1"
    }
  }

  spec {
    rule {
      http {
        path {
          path      = "/*"
          path_type = "ImplementationSpecific"
          backend {
            service {
              name = "argo-cd-argocd-server"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
  depends_on = [
    #data.terraform_remote_state.eks.outputs.eks, # wait for cluster to be done
    helm_release.argo_cd # wait for agocd to be deployed by helm before creating ingress.
  ]
}

################################################################################
# Jenkins manifest to trigger argocd deployment
################################################################################

#resource "kubernetes_namespace" "jenkins" {
#  metadata {
#    name = "jenkins"
#  }
#
##  depends_on = [
##    #data.terraform_remote_state.eks.outputs.eks, # needed
##    #helm_release.aws_load_balancer_controller # prevents destroy ingress problems # check
##  ]
#}
#
### Apply the combined applications file using Terraform, moved to argocd-template.yaml.tpl
#resource "kubernetes_manifest" "argo_cd_applications" {
#  manifest = yamldecode(file("${path.module}/../../argo-apps/jenkins/argoapp-jenkins.yaml")) #"${path.module}/argocd-app-global-index.yaml"
#
#  depends_on = [
#    #data.terraform_remote_state.eks.outputs.eks, # wait for cluster to be done
#    helm_release.argo_cd, #
#  ]
#}

########################################################################

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