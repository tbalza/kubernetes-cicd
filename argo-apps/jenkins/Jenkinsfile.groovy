pipeline {
    agent {
        kubernetes {
            yaml '''
            apiVersion: v1
            kind: Pod
            metadata:
                name: kaniko
            spec:
              containers:
              - name: kaniko
                image: gcr.io/kaniko-project/executor:debug:v1.23.1-debug
                ttyEnabled: true
                volumeMounts:
                - name: django-app
                  mountPath: "/django"
              restartPolicy: Never
              volumes:
              - name: django-app
                persistentVolumeClaim:
                  claimName: "django-pvc"
            '''
        }
    }
    environment {
        AWS_DEFAULT_REGION = 'us-east-1' // Specify the AWS region
        ECR_URL = "350206045032.dkr.ecr.us-east-1.amazonaws.com/django-production" // Use the direct ECR URL
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