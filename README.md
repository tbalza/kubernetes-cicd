aws eks update-kubeconfig --name argocd --region us-east-1
# whenever you create a new eks cluster you must update kurbentes context

argocd
argocd login k8s-argocdcluster-91a9400b73-1795188053.us-east-1.elb.amazonaws.com --username admin --password iZKLpgZIbkTLqZRD --insecure

you are better off separating your infrastructure from your applications.
this would be two different statefiles, and you would need to explicitly handle the removal of the applications running on the cluster first, before destroying the cluster
# Necessary to avoid removing Terraform's permissions too soon before its finished
# cleaning up the resources it deployed inside the cluster
terraform state rm 'module.eks.aws_eks_access_entry.this["cluster_creator"]' || true
terraform state rm 'module.eks.aws_eks_access_policy_association.this["cluster_creator_admin"]' || true

https://github.com/terraform-aws-modules/terraform-aws-eks/issues/2923

Solution

output "cluster_endpoint" {
  description = "Endpoint for your Kubernetes API server"
  value       = try(aws_eks_cluster.this[0].endpoint, null)

  depends_on = [
    aws_eks_access_entry.this,
    aws_eks_access_policy_association.this,
  ]
}
output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = try(aws_eks_cluster.this[0].certificate_authority[0].data, null)

  depends_on = [
    aws_eks_access_entry.this,
    aws_eks_access_policy_association.this,
  ]
}

----

Before destroy
export KUBECONFIG=~/.kube/config
tf refresh

#helm
kubectl apply -f service_account.yml
helm install app eks/app

#before deploying ingress, run logs in separate terminal
kubectl logs -f -n kube-system \
-l app.kubernetes.io/name=aws-load-balancer-controller

export KUBECONFIG=~/.kube/config
export KUBE_CONFIG_PATH=~/.kube/config
export DISABLE_TELEMETRY=true #cloud nuke

#consider using aws-iam-authenticator

export TF_LOG=TRACE # most detailed
export TF_LOG=DEBUG # less detailed
export TF_LOG_PATH=terraform.log

kubectl describe svc argo-cd-argocd-server -n argocd
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

#argo default pass
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 --decode
#admin, pass node name complete

#check ENV
kubectl describe pod -n argocd -l app.kubernetes.io/name=argocd-server

#Access Entry
https://github.com/terraform-aws-modules/terraform-aws-eks/issues/2968