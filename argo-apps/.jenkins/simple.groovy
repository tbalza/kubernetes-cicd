stages {
    stage('Test') {
        steps {
            // Add your testing steps here
            sh 'echo "Testing in Kubernetes"'
        }
    }
}