// Jenkinsfile
// Updated: JFrog Generic repo for artifacts + simple mail post build

pipeline {

    // ── WHERE TO RUN ──────────────────────────────────────────────────────
    // "none" means each stage declares its own agent
    agent none

    // ── PIPELINE-WIDE SETTINGS ────────────────────────────────────────────
    options {
        timeout(time: 60, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10'))
        disableConcurrentBuilds()
    }

    // ── ENVIRONMENT VARIABLES ─────────────────────────────────────────────
    environment {
        // JFrog Artifactory address — update YOUR_SERVER_IP to 20.211.26.35
        JFROG_URL        = 'http://20.211.26.35:8082'

        // Generic repo name you created in JFrog (select Generic, not Docker)
        JFROG_REPO       = 'docker-artifacts'

        // Your app image name
        IMAGE_NAME       = 'myapp'

        // Each build gets a unique tag using Jenkins build number
        IMAGE_TAG        = "${BUILD_NUMBER}"

        // The tar file name that gets uploaded to JFrog
        ARTIFACT_NAME    = "myapp-${BUILD_NUMBER}.tar"

        // JFrog credentials — must match ID in Jenkins credentials store
        JFROG_CREDS      = credentials('jfrog-credentials')

        // Kubernetes config file — must match ID in Jenkins credentials store
        K8S_CONFIG       = credentials('k8s-kubeconfig')

        // Email recipient for post build notifications
        EMAIL_RECIPIENT  = 'your.email@gmail.com'
    }

    // ── STAGES ────────────────────────────────────────────────────────────
    stages {

        // ══════════════════════════════════════════════════════════════════
        // STAGE 1 — Checkout Code from Git
        // Runs on Jenkins master directly, no Docker needed here
        // ══════════════════════════════════════════════════════════════════
        stage('Checkout Code') {
            agent any

            steps {
                echo '=== Stage 1: Checking out source code from Git ==='

                // Pull code from the configured Git repository
                checkout scm

                // Print files and recent commits for confirmation
                sh 'ls -la'
                sh 'git log --oneline -5'
            }
        }

        // ══════════════════════════════════════════════════════════════════
        // STAGE 2 — Build and Test using Docker as the slave agent
        // Jenkins spins up a python:3.11-slim Docker container
        // All steps inside run INSIDE that container, not on the host
        // This satisfies the "Docker as slave" requirement
        // ══════════════════════════════════════════════════════════════════
        stage('Build and Test') {
            agent {
                docker {
                    // This Docker image becomes the build slave
                    image 'python:3.11-slim'

                    // Run as root so pip install works without permission errors
                    args  '-u root'

                    // Reuse the same container node across stages if possible
                    reuseNode true
                }
            }

            steps {
                echo '=== Stage 2: Running build and tests inside Docker slave ==='

                // Install app dependencies inside the Docker slave container
                sh '''
                    pip install --no-cache-dir -r requirements.txt
                    pip install pytest
                '''

                // Run inline tests against the Flask app
                sh '''
                    python -c "
import sys
sys.path.insert(0, '.')
from app import app

client = app.test_client()

# Test 1: home route
response = client.get('/')
assert response.status_code == 200, f'Home route failed: {response.status_code}'
print('Test 1 PASSED: / returns 200')

# Test 2: health route
response = client.get('/health')
assert response.status_code == 200, f'Health route failed: {response.status_code}'
print('Test 2 PASSED: /health returns 200')

print('All tests passed!')
"
                '''
            }
            // Docker container is automatically removed after this stage ends
        }

        // ══════════════════════════════════════════════════════════════════
        // STAGE 3 — Build Docker Image and Push to JFrog Generic Repo
        //
        // CHANGE FROM ORIGINAL:
        // Since Docker package type is not available in JFrog OSS free tier,
        // we save the Docker image as a .tar file and upload it to a
        // Generic repository in JFrog using curl.
        //
        // How it works:
        //   docker build  → creates the image locally
        //   docker save   → exports image to a .tar file (like a zip of the image)
        //   curl upload   → sends the .tar file to JFrog Generic repo
        //   rm            → deletes the local .tar file to save disk space
        // ══════════════════════════════════════════════════════════════════
        stage('Save and Push to JFrog Generic Repo') {
            agent any

            steps {
                echo '=== Stage 3: Building Docker image and uploading artifact to JFrog ==='

                script {

                    // Step 3a: Build the Docker image normally
                    // The image is tagged with the build number for traceability
                    sh """
                        docker build -t ${IMAGE_NAME}:${BUILD_NUMBER} .
                    """

                    // Step 3b: Save the Docker image as a tar file
                    // docker save exports the full image including all layers
                    // The output file is: myapp-<build_number>.tar
                    sh """
                        docker save ${IMAGE_NAME}:${BUILD_NUMBER} \
                          -o ${ARTIFACT_NAME}
                    """

                    // Step 3c: Upload the tar file to JFrog Generic repo
                    // curl -u = username:password authentication
                    // curl -T = upload this file
                    // The URL path puts the file inside docker-artifacts repo
                    sh """
                        curl -u ${JFROG_CREDS_USR}:${JFROG_CREDS_PSW} \
                          -T ${ARTIFACT_NAME} \
                          "${JFROG_URL}/artifactory/${JFROG_REPO}/${ARTIFACT_NAME}"
                    """

                    echo "Artifact uploaded to JFrog: ${JFROG_URL}/artifactory/${JFROG_REPO}/${ARTIFACT_NAME}"

                    // Step 3d: Remove the tar file from the Jenkins server
                    // The artifact is already safe in JFrog, no need to keep it locally
                    sh "rm -f ${ARTIFACT_NAME}"
                }
            }
        }

        // ══════════════════════════════════════════════════════════════════
        // STAGE 4 — Deploy to Kubernetes Pod
        // Pulls the locally built image and deploys it to K8s
        // Uses the kubeconfig credential to connect to the cluster
        // ══════════════════════════════════════════════════════════════════
        stage('Deploy to Kubernetes') {
            agent any

            steps {
                echo '=== Stage 4: Deploying to Kubernetes ==='

                script {
                    // Write the kubeconfig to a local file so kubectl can use it
                    writeFile file: 'kubeconfig', text: K8S_CONFIG

                    // Replace the placeholder image name in k8s-deployment.yaml
                    // with the actual image:tag built in Stage 3
                    sh """
                        sed -i 's|IMAGE_PLACEHOLDER|${IMAGE_NAME}:${BUILD_NUMBER}|g' \
                          k8s-deployment.yaml
                    """

                    // Apply the deployment manifest to Kubernetes
                    sh """
                        export KUBECONFIG=\$(pwd)/kubeconfig
                        kubectl apply -f k8s-deployment.yaml
                    """

                    // Wait for the deployment to finish rolling out
                    // Fails the stage if it takes more than 120 seconds
                    sh """
                        export KUBECONFIG=\$(pwd)/kubeconfig
                        kubectl rollout status deployment/myapp-deployment \
                          --timeout=120s
                    """

                    echo 'Deployment successful!'

                    // Print the list of running pods for confirmation
                    sh """
                        export KUBECONFIG=\$(pwd)/kubeconfig
                        kubectl get pods -l app=myapp
                    """
                }
            }
        }

        // ══════════════════════════════════════════════════════════════════
        // STAGE 5 — Verify Deployment
        // Hits the /health endpoint to confirm the app is alive and responding
        // ══════════════════════════════════════════════════════════════════
        stage('Verify Deployment') {
            agent any

            steps {
                echo '=== Stage 5: Verifying deployment is healthy ==='

                script {
                    writeFile file: 'kubeconfig', text: K8S_CONFIG

                    // Get the NodePort that Kubernetes assigned to the service
                    def nodePort = sh(
                        script: """
                            export KUBECONFIG=\$(pwd)/kubeconfig
                            kubectl get service myapp-service \
                              -o jsonpath='{.spec.ports[0].nodePort}'
                        """,
                        returnStdout: true
                    ).trim()

                    // Get the cluster node IP
                    // If minikube is not found, fall back to localhost
                    def nodeIP = sh(
                        script: "minikube ip 2>/dev/null || echo '127.0.0.1'",
                        returnStdout: true
                    ).trim()

                    echo "App is accessible at: http://${nodeIP}:${nodePort}"

                    // Give the app 10 seconds to fully initialise
                    sleep(time: 10, unit: 'SECONDS')

                    // Send a request to /health and capture the HTTP status code
                    def response = sh(
                        script: """
                            curl -s -o /dev/null -w "%{http_code}" \
                              http://${nodeIP}:${nodePort}/health \
                              || echo "000"
                        """,
                        returnStdout: true
                    ).trim()

                    // Pass only if HTTP 200 is returned
                    if (response == '200') {
                        echo "Health check PASSED — HTTP ${response}"
                    } else {
                        error("Health check FAILED — HTTP ${response}")
                    }
                }
            }
        }

        // ══════════════════════════════════════════════════════════════════
        // STAGE 6 — Destroy Kubernetes Deployment
        // Pauses and waits for a human to click approve before deleting
        // This satisfies: "after confirmation of deployment, destroy it"
        // ══════════════════════════════════════════════════════════════════
        stage('Destroy Kubernetes Deployment') {
            agent any

            // Jenkins pauses here — someone must click "Yes, destroy it"
            // in the Jenkins UI before this stage continues
            input {
                message "Deployment verified and confirmed. Ready to destroy?"
                ok      "Yes, destroy it"
                submitter "admin"
            }

            steps {
                echo '=== Stage 6: Destroying Kubernetes deployment ==='

                script {
                    writeFile file: 'kubeconfig', text: K8S_CONFIG

                    // Delete the Deployment (removes all pods)
                    sh """
                        export KUBECONFIG=\$(pwd)/kubeconfig
                        kubectl delete deployment myapp-deployment \
                          --ignore-not-found=true
                    """

                    // Delete the Service (removes the network endpoint)
                    sh """
                        export KUBECONFIG=\$(pwd)/kubeconfig
                        kubectl delete service myapp-service \
                          --ignore-not-found=true
                    """

                    echo 'Kubernetes deployment destroyed successfully'

                    // Confirm no pods remain
                    sh """
                        export KUBECONFIG=\$(pwd)/kubeconfig
                        kubectl get pods -l app=myapp \
                          || echo 'No pods found — cleanup complete'
                    """
                }
            }
        }

    }
    // ── END OF STAGES ─────────────────────────────────────────────────────


    // ── POST BUILD ACTIONS ────────────────────────────────────────────────
    // CHANGE FROM ORIGINAL:
    // Removed emailext plugin entirely.
    // Using simple built-in mail() step instead.
    // mail() is available in Jenkins without any extra plugin.
    // It sends a plain text email using the SMTP settings configured
    // in Manage Jenkins → Configure System → E-mail Notification.
    // ─────────────────────────────────────────────────────────────────────
    post {

    success {
        echo '=== Pipeline SUCCEEDED ==='
        mail(
            to:      'incharanbhushan1996@gmail.com',
            subject: "BUILD SUCCESS: ${JOB_NAME} #${BUILD_NUMBER}",
            body:    """
Hi Team,

The Jenkins pipeline completed successfully.

Job Name     : ${JOB_NAME}
Build Number : #${BUILD_NUMBER}
Status       : SUCCESS
Duration     : ${currentBuild.durationString}
Build URL    : ${BUILD_URL}

-- Jenkins Automation
            """
        )
    }

    failure {
        echo '=== Pipeline FAILED ==='
        mail(
            to:      'incharanbhushan1996@gmail.com',
            subject: "BUILD FAILED: ${JOB_NAME} #${BUILD_NUMBER}",
            body:    """
Hi Team,

The Jenkins pipeline has FAILED. Please check immediately.

Job Name     : ${JOB_NAME}
Build Number : #${BUILD_NUMBER}
Status       : FAILED
Build URL    : ${BUILD_URL}
Console Log  : ${BUILD_URL}console

-- Jenkins Automation
            """
        )
    }

    fixed {
        echo '=== Pipeline recovered from failure ==='
        mail(
            to:      'incharanbhushan1996@gmail.com',
            subject: "BUILD FIXED: ${JOB_NAME} #${BUILD_NUMBER}",
            body:    """
Hi Team,

Pipeline is back to normal after a previous failure.

Job Name     : ${JOB_NAME}
Build Number : #${BUILD_NUMBER}
Status       : FIXED
Build URL    : ${BUILD_URL}

-- Jenkins Automation
            """
        )
    }

    always {
        echo '=== Post Build: Cleaning up ==='
        // ✅ FIX: wrap sh commands in node{} block
        node('built-in') {
            sh 'rm -f kubeconfig || true'
            sh 'docker rmi myapp:${BUILD_NUMBER} || true'
        }
        echo 'Cleanup complete'
    }
}
