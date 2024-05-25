#!/bin/bash

# Define the static username
ARGOCD_USERNAME='admin'

# Retrieve the initial admin password from the Kubernetes secret
ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 --decode)

# Log in to Argo CD
argocd login $ARGOCD_SERVER --username $ARGOCD_USERNAME --password $ARGOCD_PASSWORD --insecure

# Get a list of all applications in a format that's easy to parse
app_list=$(argocd app list -o name)

# Initialize an empty array to store namespaces
declare -A namespaces

# Initialize an empty array to store CRDs
declare -A crds

# Collect namespaces and CRDs without deleting anything yet
for app_name in $app_list; do
    # Extract namespace of the application
    namespace=$(argocd app get $app_name --output json | jq -r '.spec.destination.namespace')
    namespaces[$namespace]=1

    # Collect CRDs potentially created by this application
    # Modify this line to match the label selector specific to your CRDs related to Argo CD applications
    for crd in $(kubectl get crds -o json | jq -r '.items[] | select(.metadata.labels.app=="argo-cd") | .metadata.name'); do
        crds[$crd]=1
    done
done

# Delete Argo CD applications
for app_name in $app_list; do
    echo "Deleting application: $app_name"
    argocd app delete $app_name --cascade
    echo "$app_name deleted successfully."
done

# Wait for all applications to be fully deleted
echo "Waiting for Kubernetes to clean up all resources..."
sleep 30

# Delete the namespaces used by the applications
for ns in "${!namespaces[@]}"; do
    echo "Deleting namespace: $ns"
    kubectl delete namespace $ns
    echo "Namespace $ns deleted successfully."
done

# Delete the CRDs collected
for crd in "${!crds[@]}"; do
    echo "Deleting CRD: $crd"
    kubectl delete crd $crd
    echo "CRD $crd deleted successfully."
done

echo "All applications, their namespaces, and CRDs have been deleted."
