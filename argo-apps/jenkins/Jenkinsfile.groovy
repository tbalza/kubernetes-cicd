pipeline {
    agent {
        kubernetes {
            label 'jenkins-jenkins-agent'
            defaultContainer 'jnlp'
        }
    }
    environment {
        AWS_DEFAULT_REGION = 'your-aws-region' // Specify the AWS region
        IMAGE_NAME = "${env.ECR_URL}/my-django-app" // Ensure the ECR URL is correctly defined
    }

    stages {
        stage('Build and Push Image') {
            steps {
                container('kaniko') {
                    script {
                        sh """
                        /kaniko/executor --dockerfile ${WORKSPACE}/Django/Dockerfile \
                                          --context ${WORKSPACE}/Django/ \
                                          --destination ${IMAGE_NAME}:${BUILD_NUMBER} \
                                          --cache=true
                        """
                    }
                }
            }
        }
    }
    post {
        always {
            echo "Cleaning up post build"
        }
    }
}