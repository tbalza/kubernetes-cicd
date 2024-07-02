pipeline {
    agent {
        kubernetes {
            inheritFrom 'default'
        }
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
                        env.GIT_COMMIT = sh(script: "git rev-parse HEAD", returnStdout: true).trim()
                    }
                }
            }
        }
        stage('Check ECR for Images') {
            steps {
                container('jnlp') {
                    script {
                        // Check if there are any images in the ECR repository
                        def imageCount = sh(
                            script: "aws ecr describe-images --repository-name django-production --region us-east-1 | jq '.imageDetails | length'",
                            returnStdout: true
                        ).trim()
                        if (imageCount == "0") {
                            echo "No images found in ECR, initiating build."
                            env.BUILD_NEEDED = 'true'
                        }
                    }
                }
            }
        }
        stage('Check for Django Changes') {
            steps {
                container('jnlp') {
                    script {
                        // Determine if changes affect the Django directory
                        def changesInDjango = sh(
                            script: "git diff --name-only HEAD^ HEAD | grep '^django/'",
                            returnStdout: true
                        ).trim()
                        if (changesInDjango.isEmpty() && env.BUILD_NEEDED != 'true') {
                            echo "No changes in the Django app, skipping build"
                            currentBuild.result = 'ABORTED'
                        } else {
                            echo "Changes detected in Django or no images in repo, proceeding with build."
                            env.BUILD_NEEDED = 'true'
                        }
                    }
                }
            }
        }
        stage('Build and Push Image') {
            when {
                expression {
                    // Proceed only if changes are detected in the Django directory or no images are present in ECR
                    return env.BUILD_NEEDED == 'true'
                }
            }
            steps {
                container('kaniko') {
                    script {
                        sh """
                        /kaniko/executor --dockerfile /home/jenkins/agent/workspace/build-django/django/Dockerfile \
                                          --context /home/jenkins/agent/workspace/build-django/django/ \
                                          --destination ${ECR_REPO}:${GIT_COMMIT} \
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