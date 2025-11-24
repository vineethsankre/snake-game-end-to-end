pipeline {
    agent any

    environment {
        DOCKER_CREDS = credentials('docker')
        SONAR = credentials('sonar')
        AWS_CREDS = credentials('aws-jenkins-creds')
        APP_IMAGE = "jithendarramagiri1998/snake-game:latest"
        CLUSTER_NAME = "my-eks-cluster"
        REGION = "ap-south-1"
    }

    stages {

        /* ───────────────────────────────
         *  CHECKOUT APPLICATION CODE
         * ─────────────────────────────── */
        stage('Checkout Code') {
            steps {
                git 'https://github.com/Jithendarramagiri1998/snake-game.git'
            }
        }

        /* ───────────────────────────────
         *  MAVEN BUILD (added newly)
         * ─────────────────────────────── */
        stage('Maven Build') {
            when {
                expression { fileExists('pom.xml') }
            }
            steps {
                sh """
                echo "Maven project detected. Running Maven build..."
                mvn clean package -DskipTests
                """
            }
        }

               /* ───────────────────────────────
         *  SONARQUBE CODE ANALYSIS (FIXED)
         * ─────────────────────────────── */
        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('MySonar') {
                    script {
                        def scannerHome = tool name: 'SonarScanner', type: 'hudson.plugins.sonar.SonarRunnerInstallation'

                        sh """
                            export SONAR_SCANNER_OPTS="-Xmx1024m"
                            export NODE_OPTIONS="--max-old-space-size=1536"

                            # use system node if available
                            if command -v node >/dev/null 2>&1; then
                                echo "Using system Node.js at: \$(which node)"
                                export SONAR_NODEJS_EXECUTABLE=\$(which node)
                            fi

                            ${scannerHome}/bin/sonar-scanner \
                              -Dsonar.projectKey=snake \
                              -Dsonar.sources=. \
                              -Dsonar.host.url=$SONAR_HOST_URL \
                              -Dsonar.token=$SONAR \
                              -Dsonar.javascript.node.maxspace=1536
                        """
                    }
                }
            }
        }

        /* ───────────────────────────────
         *  TRIVY SECURITY SCAN
         * ─────────────────────────────── */
        stage('Trivy Scan') {
            steps {
                sh '''
                trivy fs . --exit-code 0 --severity HIGH,CRITICAL
                '''
            }
        }

        /* ───────────────────────────────
         *  DOCKER BUILD & PUSH
         * ─────────────────────────────── */
        stage('Docker Build & Push') {
            steps {
                sh '''
                docker build -t snake-game:latest .
                docker tag snake-game:latest $APP_IMAGE
                echo "$DOCKER_CREDS_PSW" | docker login -u "$DOCKER_CREDS_USR" --password-stdin
                docker push $APP_IMAGE
                '''
            }
        }

        /* ───────────────────────────────
         *  CONNECT TO EKS
         * ─────────────────────────────── */
        stage('Update kubeconfig') {
            steps {
                sh '''
                aws eks update-kubeconfig \
                  --name $CLUSTER_NAME \
                  --region $REGION
                '''
            }
        }

        /* ───────────────────────────────
         *  DEPLOY TO EKS
         * ─────────────────────────────── */
        stage('Deploy App to EKS') {
            steps {
                sh '''
                sed -i "s|IMAGE_PLACEHOLDER|$APP_IMAGE|g" k8s/deployment.yaml
                kubectl apply -f k8s/deployment.yaml
                kubectl apply -f k8s/service.yaml
                '''
            }
        }

        stage('Verify Rollout') {
            steps {
                sh '''
                kubectl rollout status deployment/snake-game
                '''
            }
        }

        /* ───────────────────────────────
         *  DEPLOY PROMETHEUS + GRAFANA
         * ─────────────────────────────── */
        stage('Monitoring Deployment') {
            steps {
                sh '''
                helm upgrade --install kube-prometheus-stack \
                  prometheus-community/kube-prometheus-stack \
                  -n monitoring \
                  --create-namespace
                '''
            }
        }

        /* ───────────────────────────────
         *  GRAFANA DASHBOARDS
         * ─────────────────────────────── */
        stage('Grafana Dashboards') {
            steps {
                sh '''
                kubectl create configmap grafana-dashboards \
                  --from-file=monitoring/grafana/dashboards \
                  -n monitoring \
                  --dry-run=client -o yaml | kubectl apply -f -

                kubectl rollout restart deployment kube-prometheus-stack-grafana -n monitoring
                '''
            }
        }
    }

    post {
        success {
            echo "✔ CI/CD PIPELINE COMPLETED SUCCESSFULLY!"
        }
        failure {
            echo "❌ Pipeline Failed. Check logs."
        }
    }
}
