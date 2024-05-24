pipeline {
  agent any
  stages {
    stage('Build') {
      steps {
        script {
          load 'argo-apps/jenkins/scripts/docker-build-script.sh'
        }
      }
    }
    stage('Deploy') {
      steps {
        script {
          // Include deployment scripts or kubectl commands
        }
      }
    }
  }
}
