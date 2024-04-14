# argocd-template.yaml.tpl
repository.credentials: |
  - url: ${repo_url}
    # No need for username/password since the repository is public