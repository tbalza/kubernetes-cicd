pipeline {
    agent {
        kubernetes {
            label 'jenkins-jenkins-agent'
            defaultContainer 'jnlp'
        }
    }
    environment {
        AWS_DEFAULT_REGION = 'us-east-1' // Specify the AWS region
        ECR_URL = "350206045032.dkr.ecr.us-east-1.amazonaws.com/django-production" //"${env.ECR_URL}"
    }

    stages {
        stage('Build and Push Image') {
            steps {
                container('kaniko') {
                    script {
                        sh """
                        /kaniko/executor --dockerfile /django/Dockerfile \
                                          --context /django/ \
                                          --destination ${ECR_URL}:${BUILD_NUMBER} \
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