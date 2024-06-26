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
                    script {
                        checkout scm: [
                            $class: 'GitSCM',
                            userRemoteConfigs: [[url: 'https://github.com/tbalza/kubernetes-cicd.git']],
                            branches: [[name: '*/main']]
                        ]
                    }
                    script {
                        COMMIT_ID = sh(
                            script: "git log -n 1 --pretty=format:'%H'",
                            returnStdout: true
                        ).trim()
                    }
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
                                          --destination ${ECR_URL}:${COMMIT_ID} \
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