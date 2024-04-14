aws eks update-kubeconfig --name argocd --region us-east-1
# whenever you create a new eks cluster you must update kurbentes context

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