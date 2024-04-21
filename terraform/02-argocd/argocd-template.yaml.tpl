# argocd-template.yaml.tpl
configs:
  repository.credentials: |
    - url: ${repo_url}
      # No need for username/password since the repository is public

  repositories: |
    - url: https://github.com/tbalza/kubernetes-cicd