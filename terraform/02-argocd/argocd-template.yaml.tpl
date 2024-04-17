# argocd-template.yaml.tpl
# this will be used later on to pass credentials and dynamic values to ArgoCD
repository.credentials: |
  - url: ${repo_url}
    # No need for username/password since the repository is public