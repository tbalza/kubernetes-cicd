#!/bin/bash

# Define the static username
ARGOCD_USERNAME='admin'

# Retrieve the initial admin password from the Kubernetes secret
ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 --decode)

# Log in to Argo CD
argocd login $ARGOCD_SERVER --username $ARGOCD_USERNAME --password $ARGOCD_PASSWORD --insecure

# Get a list of all applications in a format that's easy to parse
app_list=$(argocd app list -o name)

# Initialize arrays to store various resources
declare -A namespaces
declare -A crds
declare -A pvcs
declare -A pvs
declare -A ingresses

# Collect data phase
for app_name in $app_list; do
    # Extract namespace of the application
    namespace=$(argocd app get $app_name --output json | jq -r '.spec.destination.namespace')
    namespaces[$namespace]=1

    # Collect PVCs and Ingresses associated with the application
    for pvc in $(kubectl get pvc -n $namespace -o name); do
        pvcs[$pvc]=1
    done
    for ingress in $(kubectl get ingress -n $namespace -o name); do
        ingresses[$ingress]=1
    done
done

# Collect CRDs and PVs potentially associated with applications
for crd in $(kubectl get crds -o json | jq -r '.items[] | select(.metadata.labels.app=="argo-cd") | .metadata.name'); do
    crds[$crd]=1
done
for pv in $(kubectl get pv -o json | jq -r '.items[] | select(.status.phase=="Released" or .status.phase=="Available") | .metadata.name'); do
    pvs[$pv]=1
done

# Deletion phase

# Delete Argo CD applications
for app_name in $app_list; do
    echo "Deleting application: $app_name"
    argocd app delete $app_name --cascade
    echo "$app_name deleted successfully."
done

# Wait for all applications to be fully deleted
echo "Waiting for Kubernetes to clean up all resources..."
sleep 30

# Delete the namespaces and associated resources
for ns in "${!namespaces[@]}"; do
    echo "Deleting PVCs in namespace: $ns"
    kubectl delete pvc --all -n $ns
    echo "Deleting Ingresses in namespace: $ns"
    kubectl delete ingress --all -n $ns
    echo "Deleting namespace: $ns"
    kubectl delete namespace $ns
    echo "Namespace $ns deleted successfully."
done

# Delete unbound PVs not associated with any namespace
for pv in "${!pvs[@]}"; do
    echo "Deleting PV: $pv"
    kubectl delete pv $pv
    echo "PV $pv deleted successfully."
done

# Delete the CRDs collected
for crd in "${!crds[@]}"; do
    echo "Deleting CRD: $crd"
    kubectl delete crd $crd
    echo "CRD $crd deleted successfully."
done

echo "All resources cleaned up."
