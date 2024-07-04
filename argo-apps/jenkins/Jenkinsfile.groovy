pipeline {
    agent {
        kubernetes {
            inheritFrom 'default'
        }
    }
    triggers {
        // Poll SCM every 5 minutes
        //pollSCM('H/5 * * * *')
        githubPush()
    }
    stages {
        stage('Checkout Code') {
            steps {
                container('jnlp') {
                    script {
                        // Clone the repository and check out the main branch
                        sh "git clone ${REPO_URL} ."
                        sh "git checkout main"
                        env.GIT_COMMIT = sh(script: "git rev-parse HEAD", returnStdout: true).trim()
                        echo "Current GIT COMMIT: ${env.GIT_COMMIT}"
                    }
                }
            }
        }
        stage('Check ECR for Latest Image Commit') { // pipeline-aws plugin outputs ecr images in a non-standard way, that needs to be filtered
            steps {
                container('jnlp') {
                    script {
                        def images = ecrListImages(repositoryName: 'django-production')
                        def tagList = []

                        if (images) {
                            echo "Images Object: ${images}"
                            images.each { item ->
                                if (item && item.imageTag) {
                                    echo "Found Tag: ${item.imageTag}"
                                    tagList << item.imageTag
                                }
                            }
                        } else {
                            echo "Images Object is null or unavailable"
                        }

                        if (tagList.isEmpty()) {
                            echo "No tagged images found in ECR. Proceeding with build."
                            env.LATEST_ECR_COMMIT = ''
                            env.BUILD_NEEDED = 'true'
                        } else {
                            tagList.each {
                                echo "Extracted Image Tag: $it"
                            }
                            env.LATEST_ECR_COMMIT = tagList.last()
                            echo "Latest ECR Image Commit ID: ${env.LATEST_ECR_COMMIT}"
                        }
                    }
                }
            }
        }
        stage('Check for Django Changes') { // check the diff of the the commit id (which is the name of image tag) vs. the current comment and check for changes in django
            steps {
                container('jnlp') {
                    script {
                        if (env.LATEST_ECR_COMMIT) {
                            def changes = sh(script: "git diff --name-only ${env.LATEST_ECR_COMMIT} ${env.GIT_COMMIT} | grep '^django/' || true", returnStdout: true).trim()
                            echo "Git diff completed between ${env.LATEST_ECR_COMMIT} and ${env.GIT_COMMIT}."
                            if (changes.isEmpty()) {
                                echo "No changes in the Django directory since the last ECR image commit. No build needed."
                                env.BUILD_NEEDED = 'false' // Explicitly marking no build needed
                            } else {
                                echo "Changes detected in Django. Proceeding with build."
                                env.BUILD_NEEDED = 'true'
                            }
                        } else {
                            echo "No valid ECR image commit found or no image tags available. Proceeding with build as fallback."
                            env.BUILD_NEEDED = 'true'
                        }
                    }
                }
            }
        }
        stage('Build and Push Image') {
            when {
                expression { env.BUILD_NEEDED == 'true' }
            }
            steps {
                container('kaniko') {
                    sh """
                    /kaniko/executor --dockerfile /home/jenkins/agent/workspace/build-django/django/Dockerfile \
                                      --context /home/jenkins/agent/workspace/build-django/django/ \
                                      --destination ${ECR_REPO}:${env.GIT_COMMIT} \
                                      --cache=true
                    """
                }
            }
        }
    }
    post {
        always {
            echo "Build completed successfully."
        }
    }
}