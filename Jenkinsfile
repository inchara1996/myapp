// Jenkinsfile
pipeline {

    agent none

    options {
        timeout(time: 60, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10'))
        disableConcurrentBuilds()
    }

    environment {
        JFROG_URL      = 'http://20.211.26.35:8082'
        JFROG_REPO     = 'docker-artifacts'
        IMAGE_NAME     = 'myapp'
        IMAGE_TAG      = "${BUILD_NUMBER}"
        ARTIFACT_NAME  = "myapp-${BUILD_NUMBER}.tar"
        JFROG_CREDS    = credentials('jfrog-credentials')
    }

    stages {

        stage('Checkout Code') {
            agent any
            steps {
                echo '=== Stage 1: Checking out source code from Git ==='
                checkout scm
                sh 'ls -la'
                sh 'git log --oneline -5'
            }
        }

        stage('Build and Test') {
            agent {
                docker {
                    image 'python:3.11-slim'
                    args  '-u root'
                    reuseNode true
                }
            }
            steps {
                echo '=== Stage 2: Running build and tests inside Docker slave ==='
                sh '''
                    pip install --no-cache-dir -r requirements.txt
                    pip install pytest
                '''
                sh '''
                    python -c "
import sys
sys.path.insert(0, '.')
from app import app

client = app.test_client()

response = client.get('/')
assert response.status_code == 200, f'Home route failed: {response.status_code}'
print('Test 1 PASSED: / returns 200')

response = client.get('/health')
assert response.status_code == 200, f'Health route failed: {response.status_code}'
print('Test 2 PASSED: /health returns 200')

print('All tests passed!')
"
                '''
            }
        }

        stage('Save and Push to JFrog Generic Repo') {
            agent any
            steps {
                echo '=== Stage 3: Building Docker image and uploading artifact to JFrog ==='
                script {
                    sh """
                        docker build -t ${IMAGE_NAME}:${BUILD_NUMBER} .
                    """
                    sh """
                        docker save ${IMAGE_NAME}:${BUILD_NUMBER} \
                          -o ${ARTIFACT_NAME}
                    """
                    sh """
                        curl -u ${JFROG_CREDS_USR}:${JFROG_CREDS_PSW} \
                          -T ${ARTIFACT_NAME} \
                          "${JFROG_URL}/artifactory/${JFROG_REPO}/${ARTIFACT_NAME}"
                    """
                    echo "Artifact uploaded: ${JFROG_URL}/artifactory/${JFROG_REPO}/${ARTIFACT_NAME}"
                    sh "rm -f ${ARTIFACT_NAME}"
                }
            }
        }

        stage('Deploy to Kubernetes') {
            agent any
            steps {
                echo '=== Stage 4: Deploying to Kubernetes ==='
                script {
                    withCredentials([file(credentialsId: 'k8s-kubeconfig', variable: 'K8S_CONFIG')]) {
                        sh """
                            sed -i 's|IMAGE_PLACEHOLDER|${IMAGE_NAME}:${BUILD_NUMBER}|g' \
                              k8s-deployment.yaml
                        """
                        sh """
                            export KUBECONFIG=\$K8S_CONFIG
                            kubectl apply -f k8s-deployment.yaml
                        """
                        sh """
                            export KUBECONFIG=\$K8S_CONFIG
                            kubectl rollout status deployment/myapp-deployment \
                              --timeout=120s
                        """
                        sh """
                            export KUBECONFIG=\$K8S_CONFIG
                            kubectl get pods -l app=myapp
                        """
                        echo 'Deployment successful!'
                    }
                }
            }
        }

        stage('Verify Deployment') {
            agent any
            steps {
                echo '=== Stage 5: Verifying deployment is healthy ==='
                script {
                    withCredentials([file(credentialsId: 'k8s-kubeconfig', variable: 'K8S_CONFIG')]) {
                        def nodePort = sh(
                            script: """
                                export KUBECONFIG=\$K8S_CONFIG
                                kubectl get service myapp-service \
                                  -o jsonpath='{.spec.ports[0].nodePort}'
                            """,
                            returnStdout: true
                        ).trim()

                        def nodeIP = sh(
                            script: "minikube ip 2>/dev/null || echo '127.0.0.1'",
                            returnStdout: true
                        ).trim()

                        echo "App is accessible at: http://${nodeIP}:${nodePort}"
                        sleep(time: 10, unit: 'SECONDS')

                        def response = sh(
                            script: """
                                curl -s -o /dev/null -w "%{http_code}" \
                                  http://${nodeIP}:${nodePort}/health \
                                  || echo "000"
                            """,
                            returnStdout: true
                        ).trim()

                        if (response == '200') {
                            echo "Health check PASSED — HTTP ${response}"
                        } else {
                            error("Health check FAILED — HTTP ${response}")
                        }
                    }
                }
            }
        }

        stage('Destroy Kubernetes Deployment') {
            agent any
            input {
                message "Deployment verified and confirmed. Ready to destroy?"
                ok      "Yes, destroy it"
                submitter "admin"
            }
            steps {
                echo '=== Stage 6: Destroying Kubernetes deployment ==='
                script {
                    withCredentials([file(credentialsId: 'k8s-kubeconfig', variable: 'K8S_CONFIG')]) {
                        sh """
                            export KUBECONFIG=\$K8S_CONFIG
                            kubectl delete deployment myapp-deployment \
                              --ignore-not-found=true
                        """
                        sh """
                            export KUBECONFIG=\$K8S_CONFIG
                            kubectl delete service myapp-service \
                              --ignore-not-found=true
                        """
                        echo 'Kubernetes deployment destroyed successfully'
                        sh """
                            export KUBECONFIG=\$K8S_CONFIG
                            kubectl get pods -l app=myapp \
                              || echo 'No pods found — cleanup complete'
                        """
                    }
                }
            }
        }
    }

    post {
        always {
            echo '=== Post Build: Cleaning up ==='
            node('built-in') {
                sh 'rm -f kubeconfig || true'
                sh "docker rmi ${IMAGE_NAME}:${BUILD_NUMBER} || true"
            }
            echo 'Cleanup complete'
        }
        success {
            echo '=== Pipeline SUCCEEDED ==='
        }
        failure {
            echo '=== Pipeline FAILED ==='
        }
    }
}
