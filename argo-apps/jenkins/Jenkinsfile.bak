pipeline {
    agent {
        kubernetes {
            inheritFrom 'default'
        }
    }
    environment {
        AWS_DEFAULT_REGION = 'us-east-1' // Specify the AWS region
        ECR_URL = "350206045032.dkr.ecr.us-east-1.amazonaws.com/django-production" // Use the direct ECR URL
    }

    stages {
        stage('Checkout Code') {
            steps {
                container('jnlp') {
                    checkout scm: [ $class: 'GitSCM', userRemoteConfigs: [[url: 'https://github.com/tbalza/kubernetes-cicd.git']], branches: [[name: '*/main']]]
                }
            }
        }
        stage('Build and Push Image') {
            steps {
                container('kaniko') {
                    script {
                        sh """
                        /kaniko/executor --dockerfile /home/jenkins/agent/workspace/build-django/django/Dockerfile \
                                          --context /home/jenkins/agent/workspace/build-django/django/ \
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