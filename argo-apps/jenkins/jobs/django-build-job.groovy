job('Build Django Image') {
  scm {
    git('https://github.com/yourusername/yourrepo.git')
  }
  triggers {
    githubPush()
  }
  steps {
    shell('cd django && docker build -t yourdockerhubusername/django:${BUILD_NUMBER} .')
    shell('docker push yourdockerhubusername/django:${BUILD_NUMBER}')
  }
}
