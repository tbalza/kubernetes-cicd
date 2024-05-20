provider "aws" {
  region = local.region
}

data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {}

# local helm v3.14.4
# local kubectl v1.29.3
# aws kubernetes v1.29

locals {
  name            = "argocd"
  cluster_version = "1.29" # 1.29 # check
  region          = "us-east-1"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Example = local.name
  }
}

################################################################################
# EKS Module
################################################################################

# Create iam role for service account for the block device
# IAM additional policy https://github.com/terraform-aws-modules/terraform-aws-eks/issues/2826 # check
module "ebs_csi_driver_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = ">= 5.39.0"

  # create_role      = false
  role_name_prefix = "${module.eks.cluster_name}-ebs-csi"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

# Print addon versions. ebs-csi-driver addon takes 240MB of memory
#output "cluster_addons" {
#  description = "Map of attribute maps for all EKS cluster addons enabled"
#  value       = module.eks.cluster_addons
#}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.8.5"

  cluster_name             = local.name
  cluster_version          = local.cluster_version
  cluster_ip_family        = "ipv4"
  iam_role_use_name_prefix = true
  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  #control_plane_subnet_ids = module.vpc.intra_subnets # Makes API server reachable from internet?

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  enable_irsa = true

  # To add the current caller identity as an administrator
  enable_cluster_creator_admin_permissions = true

  create_kms_key            = false
  cluster_encryption_config = {}

  cluster_addons = {
    coredns = {
      most_recent = true # pin to working version
    }
    kube-proxy = {
      most_recent = true # pin to working version
    }
    vpc-cni = { # https://github.com/terraform-aws-modules/terraform-aws-eks/issues/2968
      resolve_conflicts_on_update = "OVERWRITE"
      resolve_conflicts_on_create = "OVERWRITE"
      most_recent = true # pin to working version
      before_compute = true # ensure the VPC CNI can be created before the associated nodegroups
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true" # increase max pods per node, managed node group bootstrap also needed(?)
          # VPC CNI is configured before nodegroups are created and nodes launched, EKS managed nodegroups will infer from the VPC CNI configuration the proper value for max pods
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    aws-ebs-csi-driver = {
      resolve_conflicts_on_update = "OVERWRITE"
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts = "OVERWRITE"
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
      #addon_version            = "v1.29.1-eksbuild.1"
      most_recent = true # pin to working version
    }
  }

  eks_managed_node_group_defaults = {
    ami_type       = "AL2_x86_64"  # This is custom AMI, `enable_bootstrap_user_data` must be set to True
    instance_types = ["t3.medium"] # "m6i.large", "m5.large", "m5n.large", "m5zn.large"
    #    attach_cluster_primary_security_group = true
    #    vpc_security_group_ids = [aws_security_group.additional] # Check
    #    iam_role_additional_policies = {
    #    additional     = aws_iam_policy.additional.arn
    #    }
  }

  cluster_security_group_additional_rules = {
    ingress_nodes_ephemeral_ports_tcp = {
      description                = "Nodes on ephemeral ports"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "ingress"
      source_node_security_group = true
    }
    egress_nodes_ephemeral_ports_tcp = { # Check
      description                = "To node 1025-65535"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "egress"
      source_node_security_group = true
    }
  }

  #node_security_group_enable_recommended_rules = false
  #create_node_security_group  = false
  #node_security_group_id      = aws_security_group.eks_tooling.id

  # Enable node to node communication
  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols" # Check
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    egress_self_all = { # already created by module
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "egress"
      self        = true
    }
    # Control plane to nodes
    ingress_cluster_to_node_all_traffic = {
      description                   = "Cluster API to Nodegroup all traffic"
      protocol                      = "-1"
      from_port                     = 0
      to_port                       = 0
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  eks_managed_node_groups = {

    argocd-green = { # green

      name = "argocd-eks-nodegroup"

      subnet_ids = module.vpc.private_subnets

      min_size     = 1
      max_size     = 2
      desired_size = 1

      capacity_type = "SPOT" # "ON_DEMAND"

      #      spot = {
      #        desired_size = 1
      #        min_size = 1
      #        max_size = 1
      #
      #        labels = {
      #          role = "spot"
      #        }
      #
      #        taints = [{
      #          key = "market"
      #          value = "spot"
      #          effect = "NO_SCHEDULE"
      #        }]
      #
      #      instance_types = ["t3.micro"]
      #      capacity_type = "SPOT"
      #
      #      }

      ami_id                     = data.aws_ami.eks_default.image_id
      enable_bootstrap_user_data = true # Must be set when using custom AMI i.e. AL2_x86_64

#      bootstrap_extra_args       = "--kubelet-extra-args '--max-pods=50'"
#
#      pre_bootstrap_user_data = <<-EOT
#        export USE_MAX_PODS=false
#      EOT

#      bootstrap_extra_args = <<-EOT
#      "max-pods" = 50
#      EOT

      # VPC CNI
      # https://github.com/terraform-aws-modules/terraform-aws-eks/issues/2551

      labels = {
        role = "cicd-node" # used by k8s by argocd. scheduling, resource selection / grouping, policy enforcement
      }

      #pre_bootstrap_user_data = <<-EOT
      #  export FOO=bar
      #EOT

      #post_bootstrap_user_data = <<-EOT
      #  echo "you are free little kubelet!"
      #EOT


      force_update_version = true
      instance_types       = ["t3.medium"] # Overrides default instance defined above

      description = "EKS managed node group example launch template"

      ebs_optimized           = true
      disable_api_termination = false
      enable_monitoring       = true # Check
      #disk_size               = 40   # Check conflicts with block device? only for non default template?

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size = 30
            volume_type = "gp2" #gp3?
            #iops                  = 3000 # Pending. this is for provisioned IOPS, disabled for testing
            #throughput            = 150 # Pending. this is for provisioned IOPS, disabled for testing
            encrypted = false # Check
            #kms_key_id            = module.ebs_kms_key.key_arn
            delete_on_termination = true
          }
        }
      }

      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 2
        instance_metadata_tags      = "disabled"
      }

      # aws-auth configmap (deprecated?) replaced by "cluster access entries"

      create_iam_role          = true
      iam_role_name            = "argocd-eks-managed-node-group-role"
      iam_role_use_name_prefix = false
      iam_role_description     = "EKS managed node group complete example role"
      iam_role_tags = {
        Purpose = "Protector of the kubelet"
      }
      iam_role_additional_policies = {
        # Check
        AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
        AmazonSSMManagedInstanceCore       = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" # Enable SSM
      }

      launch_template_tags = {
        # enable discovery of autoscaling groups by cluster-autoscaler
        "k8s.io/cluster-autoscaler/enabled" : true,
        "k8s.io/cluster-autoscaler/${local.name}" : "owned",
      }

      tags = {
        ExtraTag = "ci-cd-node" # used for cost allocation, resource mgmt, automation
      }
    }
  }

  access_entries = {
    argocd = {
      kubernetes_groups = []
      principal_arn     = aws_iam_role.argo_cd.arn # Ensure you have an IAM role created for Argo CD

      policy_associations = {
        admin_policy = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }

    jenkins = {
      principal_arn = aws_iam_role.jenkins.arn
      kubernetes_groups = []

      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }

    prometheus = {
      principal_arn = aws_iam_role.prometheus.arn
      kubernetes_groups = []

      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }


  }
}

#module "jenkins_iam_policy" {
#  source = "terraform-aws-modules/iam/aws//modules/iam-policy"
#
#  name        = "myapp"
#  path        = "/"
#  description = "Example policy"
#
#  policy = jsonencode({
#    Version = "2012-10-17"
#    Statement = [
#      {
#        Effect = "Allow"
#        Action = [
#          "*",
#        ]
#        Resource = "*"
#      }
#    ]
#  })
#
#}
#
#module "jenkins_iam_role" {
#  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
#  version = "5.39.0"  # Make sure to use the correct version
#
#  role_name = "JenkinsAppRole"
#  role_description = "IAM role for Jenkins with EKS IRSA integration"
#
#  # Attach any specific policies you require
#  role_policy_arns = {
#    "admin" = module.jenkins_iam_policy.arn
#  }
#
#  # Define the OIDC provider using ARN from your EKS cluster module and link it with your service account
#  oidc_providers = {
#    eks = {
#      provider_arn               = module.eks.oidc_provider_arn
#      namespace_service_accounts = ["jenkins:jenkins"]
#    }
#  }
#}



#resource "aws_iam_role" "this" {
#  for_each = toset(["argocd", "jenkins", "alertmanager", "kubestatemetrics", "nodexporter", "grafana", "prometheus", "prometheusoperator"])
#
#  name = each.key
#
#  assume_role_policy = jsonencode({
#    Version = "2012-10-17"
#    Statement = [
#      {
#        Action = "sts:AssumeRole"
#        Effect = "Allow"
#        Sid    = "Example"
#        Principal = {
#          Service = "ec2.amazonaws.com"
#        }
#      },
#    ]
#  })
#
#  tags = local.tags
#}



resource "aws_iam_role" "argo_cd" {
  name = "ArgoCDRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Effect = "Allow"
        Sid    = ""
      }
    ]
  })
}

resource "aws_iam_role" "jenkins" {
  name = "JenkinsRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Effect = "Allow"
        Sid    = ""
      }
    ]
  })
}

resource "aws_iam_role" "prometheus" {
  name = "PrometheusRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Effect = "Allow"
        Sid    = ""
      }
    ]
  })
}

#resource "aws_iam_role_policy_attachment" "argo_cd_admin" {
#  role       = aws_iam_role.argo_cd.name
#  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
#}
#
#resource "aws_iam_role_policy_attachment" "jenkins_basic" {
#  role       = aws_iam_role.jenkins.name
#  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
#}
#
#resource "aws_iam_role_policy_attachment" "argo_cd_admin" {
#  role       = aws_iam_role.prometheus.name
#  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
#}

output "argo_cd_iam_role_arn" {
  value = aws_iam_role.argo_cd.arn
}

output "jenkins_iam_role_arn" {
  value = aws_iam_role.jenkins.arn
}


################################################################################
# VPC
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]
  #intra_subnets   = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 52)] # used for control_plane_subnet_ids cluster

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false
  #create_egress_only_igw = true

  enable_dns_hostnames = true # needed for EFS
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1 # required for load balancer controller
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1 # required for load balancer controller
  }

  tags = local.tags
}

module "ebs_kms_key" {
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 2.1"

  description = "Customer managed key to encrypt EKS managed node group volumes"

  # Policy
  key_administrators = [
    data.aws_caller_identity.current.arn # Check
  ]

  key_service_roles_for_autoscaling = [
    # required for the ASG to manage encrypted volumes for nodes
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling", # Check
    # required for the cluster / persistentvolume-controller to create encrypted PVCs
    module.eks.cluster_iam_role_arn,
  ]

  # Aliases
  aliases = ["eks/${local.name}/ebs"]

  tags = local.tags
}

################################################################################
# Permissions
################################################################################
## https://www.youtube.com/watch?v=kRKmcYC71J4
## Role for other user/team members to assume. get access to cluster
#module "allow_eks_access_iam_policy" {
#  source        = "terraform-aws-modules/iam/aws//modules/iam-policy"
#  version       = "5.3.1"
#  name          = "allow-eks-access"
#  create_policy = true
#
#  policy = jsonencode({
#    Version = "2012-10-17"
#    Statement = [
#      {
#        Action = [
#          "eks:DescribeCluster",
#        ]
#        Effect   = "ALLow"
#        Resource = "*"
#      },
#    ]
#  })
#}
#
## Role for other user/team members to assume. get access to cluster
#module "eks_admins_iam_role" {
#  source                  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role"
#  version                 = "5.3.1"
#  role_name               = "eks-admin" # full access to kubernetes API
#  create_role             = true
#  role_requires_mfa       = false
#  custom_role_policy_arns = [module.allow_eks_access_iam_policy.arn] # attach policy above
#  trusted_role_arns = [
#    "arn:aws:iam::${module.vpc.vpc_owner_id}:root" # allow any user in account to assume role
#  ]
#}
#
## Create users
#module "user1_iam_user" {
#  source                        = "terraform-aws-modules/iam/aws//modules/iam-user"
#  version                       = "5.3.1"
#  name                          = "user1"
#  create_iam_access_key         = false
#  create_iam_user_login_profile = false
#  force_destroy                 = true
#}
#
## Allow assume
#module "allow_assume_eks_admin_iam_policy" {
#  source  = "terraform-aws-modules/iam/aws//modules/iam-policy"
#  version = "5.3.1"
#  name    = "allow-assume-eks-admin-iam-role"
#
#  policy = jsonencode({
#    Version = "2012-10-17"
#    Statement = [
#      {
#        Action = [
#          "sts:AssumeRole",
#        ]
#        Effect   = "ALLow"
#        Resource = module.eks_admins_iam_role.iam_role_arn
#      },
#    ]
#  })
#}
#
## Create group, add user to group
#module "eks_admins_iam_group" {
#  source                            = "terraform-aws-modules/iam/aws//modules/iam-group-with-policies"
#  version                           = "5.3.1"
#  name                              = "eks-admin"
#  attach_iam_self_management_policy = false
#  create_group                      = true
#  group_users                       = [module.user1_iam_user.iam_user_name]
#  custom_group_policy_arns          = [module.allow_assume_eks_admin_iam_policy.arn]
#}

# Node SG
resource "aws_security_group" "remote_access" {
  name_prefix = "${local.name}-remote-access"
  description = "Allow remote SSH access"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  ingress {
    description = "argo_cd access"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "argo_cd access HTTPS"
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = merge(local.tags, { Name = "${local.name}-remote" })
}

resource "aws_iam_policy" "node_additional" {
  name        = "${local.name}-additional"
  description = "Example usage of node additional policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:*", # "ec2:Describe*" # check
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })

  tags = local.tags
}

data "aws_ami" "eks_default" { # Retrieve the latest EKS optimized AMI
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amazon-eks-node-${local.cluster_version}-v*"]
  }
}

###############################################################################
# Providers
###############################################################################

# kubectl can wait till eks is ready, and then apply yaml
provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false
  exec {
    api_version = "client.authentication.k8s.io/v1beta1" # /v1alpha1"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    command     = "aws"
  }
}

# kubernetes provider cannot wait until eks is provisioned before applying yaml
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint                                 # var.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data) # var.cluster_ca_cert
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"                          # /v1alpha1"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name] # var.cluster_name
    command     = "aws"
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint                                 # var.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data) # var.cluster_ca_cert
    exec {
      api_version = "client.authentication.k8s.io/v1beta1" # /v1alpha1"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
      command     = "aws"
    }
  }
}

#data "aws_eks_cluster" "cluster" {
#  name = module.eks.cluster_name
#}
#
#data "aws_eks_cluster_auth" "cluster" {
#  name = module.eks.cluster_name
#}

###############################################################################
# Load balancer
###############################################################################
# https://www.youtube.com/watch?v=ZfjpWOC5eoE

# by default ALB creates one per ingress, to combine use annotation
# alb.ingress.kubernetes.io/group.name: argo-cd-cluster
# alb.ingress.kubernetes.io/group.order: '1'

# echo server
# kubectl apply -f k8s/echoserver.yaml
# kubectl get ingress
# create cname dns records in hosting provider
# host name echo, CNAME, k8s-default.etc.amazonaws.com

module "aws_load_balancer_controller_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = ">= 5.39.0"

  role_name                              = "aws-load-balancer-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    sts = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

#resource "aws_iam_role_policy_attachment" "alb_controller_policy_attachment" {
#  role       = module.aws_load_balancer_controller_irsa_role.iam_role_name
#  policy_arn = aws_iam_policy.aws_load_balancer_controller.arn
#}

# Load balancer controller uses tags to discover subnets in which it can in which in can create load balancers
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.7.2" # AWS LBC ver v2.7.2, requires Kubernetes 1.22+
  #wait = false # might fix destroy issue?

  set {
    name  = "replicaCount" # by default it creates 2 replicas
    value = 1
  }

  set {
    name  = "clusterName" # check important
    value = module.eks.cluster_name
  }

  set {
    name  = "serviceAccount.name" # check important
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn" # annotation to allows service account to assume aws role
    value = module.aws_load_balancer_controller_irsa_role.iam_role_arn
  }

  # Resource requests and limits
  #  set {
  #    name  = "resources.requests.cpu"
  #    value = "100m"
  #  }
  #  set {
  #    name  = "resources.requests.memory"
  #    value = "128Mi"
  #  }
  #  set {
  #    name  = "resources.limits.memory"
  #    value = "128Mi"
  #  }

  depends_on = [                                   # checkk
    module.aws_load_balancer_controller_irsa_role, # important
    #aws_iam_role_policy_attachment.alb_controller_policy_attachment,
    module.eks # important
  ]
}

resource "kubectl_manifest" "ebs_sc" {
  yaml_body = <<-EOT
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-sc
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
allowVolumeExpansion: true
EOT

  depends_on = [
    module.eks
  ]
}