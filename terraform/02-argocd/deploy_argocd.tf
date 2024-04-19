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

# kubectl can wait till eks is ready, and then apply yaml
provider "kubectl" {
  host                   = data.terraform_remote_state.eks.outputs.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.eks.outputs.cluster_certificate_authority_data) # Get module.eks.cluster_certificate_authority_data through remote state
  load_config_file       = false
  exec {
    api_version = "client.authentication.k8s.io/v1beta1" # /v1alpha1"
    args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.eks.outputs.cluster_name]
    command     = "aws"
  }
}

# kubernetes provider cannot wait until eks is provisioned before applying yaml
provider "kubernetes" {
  host                   = data.terraform_remote_state.eks.outputs.cluster_endpoint                                 # var.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.eks.outputs.cluster_certificate_authority_data) # var.cluster_ca_cert
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"                          # /v1alpha1"
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
# Jenkins Configuration as Code (JCasC), Job DSL Plugin, Pipeline as Code (Jenkinsfiles)
# brew install jq (in readme) # check

## Create namespace
#resource "kubernetes_namespace" "argo_cd" {
#  metadata {
#    name = "argocd"
#  }
#
#  depends_on = [
#    data.terraform_remote_state.eks.outputs.eks, # needed
#    #helm_release.aws_load_balancer_controller # prevents destroy ingress problems # check
#  ]
#}
#
#resource "kubernetes_namespace" "jenkins" {
#  metadata {
#    name = "jenkins"
#  }
#
#  depends_on = [
#    data.terraform_remote_state.eks.outputs.eks, # needed
#    #helm_release.aws_load_balancer_controller # prevents destroy ingress problems # check
#  ]
#}

resource "helm_release" "argo_cd" {
  name       = "argo-cd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "4.5.7"

  namespace = "argocd" # "argocd" # check

  # Assuming the chart supports CRD installation:
  set {
    name  = "installCRDs"
    value = "true"
  }

  values = [templatefile("${path.module}/argocd-template.yaml.tpl", { # instead of using ArgoCD configmap
    repo_url = "https://github.com/tbalza/kubernetes-cicd"
    # Add other dynamic values or configurations if needed
  })]

  set {
    name  = "server.service.type"
    value = "ClusterIP" # LoadBalancer also launched a CLB
  }

  set {
    name  = "server.service.port"
    value = "80"
  }

  set {
    name  = "server.service.targetPort"
    value = "8080"
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

  set {
    name  = "server.extraEnv[2].name"
    value = "ARGOCD_AUTH_PASSWORD"
  }

  set {
    name  = "server.extraEnv[2].value" # doesn't change pw, but needed
    value = "pass"
  }

  set {
    name  = "server.extraEnv[3].name"
    value = "ARGOCD_AUTH_USERNAME"
  }

  set {
    name  = "server.extraEnv[3].value"
    value = "admin"
  }

  wait = true # false = Don't wait for confirmation of successful creation, tf destroy fix

#  depends_on = [
#    data.terraform_remote_state.eks.outputs.eks, # needed
#    #helm_release.aws_load_balancer_controller # prevents destroy ingress problems # check
#  ]
}

# Create ingress
resource "kubernetes_ingress_v1" "argo_cd" {
  metadata {
    name      = "argocd-ingress"
    namespace = "argocd"
    annotations = {
      "kubernetes.io/ingress.class"                = "alb"
      "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"      = "ip"
      "alb.ingress.kubernetes.io/listen-ports"     = jsonencode([{ HTTP = 80 }]) # jsonencode([{ HTTP = 80 }, { HTTPS = 443 }])
      "alb.ingress.kubernetes.io/tags"             = "Example=${data.terraform_remote_state.eks.outputs.name}"
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


# Apply the combined applications file using Terraform
resource "kubernetes_manifest" "argo_cd_applications" {
  manifest = yamldecode(file("${path.module}/../../argocd-applications.yaml"))

  depends_on = [
    #data.terraform_remote_state.eks.outputs.eks, # wait for cluster to be done
    helm_release.argo_cd, #
  ]
}