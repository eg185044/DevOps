pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    environment {
        IMAGE_TAG = "${env.BUILD_NUMBER}"
    }

    stages {
        stage('Validate Project Structure') {
            steps {
                sh '''
                    test -f README.md
                    test -f terraform/main.tf
                    test -f ansible/site.yml
                    test -f ansible/roles/nginx/tasks/main.yml
                    echo "Project structure looks good."
                '''
            }
        }

        stage('Build Backend Image') {
            steps {
                sh "docker build -t cv-backend:${IMAGE_TAG} app/backend"
            }
        }

        stage('Build Frontend Image') {
            steps {
                sh "docker build -t cv-frontend:${IMAGE_TAG} app/frontend"
            }
        }

        stage('Build Worker Image') {
            steps {
                sh "docker build -t cv-worker:${IMAGE_TAG} app/worker"
            }
        }
    }

    post {
        success {
            echo "Build #${IMAGE_TAG} succeeded: backend, frontend, and worker images built."
        }
        failure {
            echo "Build #${IMAGE_TAG} failed. Check the stage logs above."
        }
    }
}
