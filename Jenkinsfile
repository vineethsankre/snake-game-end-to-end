pipeline {
    agent any

    environment {
        DOCKER_CREDS = credentials('docker')
        SONAR = credentials('sonar')
        APP_IMAGE = "jithendarramagiri1998/snake-game:latest"
        CLUSTER_NAME = "my-eks-cluster"
        REGION = "ap-south-1"
    }

    stages {

        /* ─────────────────────────────────────
         *  CHECKOUT APPLICATION CODE
         * ───────────────────────────────────── */
        stage('Checkout Code') {
            steps {
                git 'https://github.com/Jithendarramagiri1998/snake-game.git'
            }
        }

        /* ─────────────────────────────────────
         *  MAVEN BUILD
         * ───────────────────────────────────── */
        stage('Maven Build') {
            when { expression { fileExists('pom.xml') } }
            steps {
                sh '''
                mvn clean package -DskipTests
                '''
            }
        }

        /* ─────────────────────────────────────
         *  SONARQUBE ANALYSIS
         * ───────────────────────────────────── */
        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('MySonar') {
                    script {
                        def scannerHome = tool name: 'SonarScanner', type: 'hudson.plugins.sonar.SonarRunnerInstallation'
                        sh """
                            export SONAR_SCANNER_OPTS="-Xmx1024m"
                            ${scannerHome}/bin/sonar-scanner \
                              -Dsonar.projectKey=snake \
                              -Dsonar.sources=. \
                              -Dsonar.host.url=$SONAR_HOST_URL \
                              -Dsonar.token=$SONAR
                        """
                    }
                }
            }
        }

        /* ─────────────────────────────────────
         *  TRIVY SECURITY SCAN
         * ───────────────────────────────────── */
        stage('Trivy Scan') {
            steps {
                sh 'trivy fs . --exit-code 0 --severity HIGH,CRITICAL'
            }
        }

        /* ─────────────────────────────────────
         *  DOCKER BUILD + PUSH
         * ───────────────────────────────────── */
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

        /* ─────────────────────────────────────
         *  UPDATE KUBECONFIG
         * ───────────────────────────────────── */
        stage('Update kubeconfig') {
            steps {
                withCredentials([aws(credentialsId: 'aws-jenkins-creds')]) {
                    sh '''
                    export HOME=/root
                    export KUBECONFIG=/root/.kube/config

                    mkdir -p /root/.kube

                    aws eks update-kubeconfig \
                      --name $CLUSTER_NAME \
                      --region $REGION \
                      --kubeconfig /root/.kube/config

                    kubectl --kubeconfig=/root/.kube/config get nodes
                    '''
                }
            }
        }

        /* ─────────────────────────────────────
         *  DEPLOY APP TO EKS
         * ───────────────────────────────────── */
        stage('Deploy to EKS') {
            steps {
                withCredentials([aws(credentialsId: 'aws-jenkins-creds')]) {
                    sh '''
                    export HOME=/root
                    export KUBECONFIG=/root/.kube/config

                    sed -i "s|IMAGE_PLACEHOLDER|$APP_IMAGE|g" k8s/deployment.yaml

                    kubectl apply -f k8s/deployment.yaml --validate=false
                    kubectl apply -f k8s/service.yaml --validate=false
                    '''
                }
            }
        }

        /* ─────────────────────────────────────
         *  VERIFY ROLLOUT
         * ───────────────────────────────────── */
        stage('Verify Rollout') {
            steps {
                sh '''
                export KUBECONFIG=/root/.kube/config
                kubectl rollout status deployment/snake-game
                '''
            }
        }

        /* ─────────────────────────────────────
         *  PROMETHEUS + GRAFANA INSTALLATION
         *  (Using direct chart URL – no repo needed)
         * ───────────────────────────────────── */
        stage('Monitoring Deployment') {
            steps {
                sh '''
                export HOME=/root
                export PATH=/root/.local/bin:/usr/local/bin:/usr/bin:/bin
                export KUBECONFIG=/root/.kube/config

                # Install Helm for root if not installed
                if ! command -v helm >/dev/null 2>&1; then
                  echo "Installing Helm..."
                  curl -LO https://get.helm.sh/helm-v3.12.3-linux-amd64.tar.gz
                  tar -zxvf helm-v3.12.3-linux-amd64.tar.gz
                  mv linux-amd64/helm /root/.local/bin/helm
                  chmod +x /root/.local/bin/helm
                fi

                echo "Installing Monitoring Stack..."

                helm upgrade --install kube-prometheus-stack \
                  https://prometheus-community.github.io/helm-charts/kube-prometheus-stack-65.0.0.tgz \
                  -n monitoring --create-namespace --wait --timeout 10m
                '''
            }
        }

        /* ─────────────────────────────────────
         *  GRAFANA DASHBOARDS CONFIG
         * ───────────────────────────────────── */
        stage('Grafana Dashboards') {
            steps {
                sh '''
                export KUBECONFIG=/root/.kube/config

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
