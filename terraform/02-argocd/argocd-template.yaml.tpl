# argocd-template.yaml.tpl
# Template to configure repository credentials and applications in ArgoCD

configs:
  repository.credentials: |
    - url: ${repo_url}
      # No need for username/password since the repository is public

  repositories: |
    - url: https://github.com/tbalza/kubernetes-cicd
  applications: |
    - name: jenkins
      namespace: argocd
      project: default
      source:
        repoURL: 'https://github.com/tbalza/kubernetes-cicd'
        path: 'argo-apps/jenkins'
        targetRevision: HEAD
        helm:
          valueFiles:
            - values.yaml
      destination:
        server: 'https://kubernetes.default.svc'
        namespace: jenkins
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
          allowEmpty: false
    # Uncomment the following lines to enable the Wordpress application when needed
    # - name: wordpress
    #   namespace: argocd
    #   project: default
    #   source:
    #     repoURL: 'https://github.com/tbalza/kubernetes-cicd'
    #     path: 'argo-apps/wordpress'
    #     targetRevision: HEAD
    #   destination:
    #     server: 'https://kubernetes.default.svc'
    #     namespace: wordpress
    #   syncPolicy:
    #     automated:
    #       prune: true
    #       selfHeal: true