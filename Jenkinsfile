pipeline {
    agent any

    environment {
        DOCKER_CREDS = credentials('docker')
        SONAR = credentials('sonar-token')
        AWS_CREDS = credentials('aws-jenkins-creds')
        APP_IMAGE = "jithendarramagiri1998/snake-game:latest"
        CLUSTER_NAME = "my-eks-cluster"
        REGION = "ap-south-1"
    }

    stages {

        /* ───────────────────────────────
         *  CHECKOUT APPLICATION CODE
         * ─────────────────────────────── */
        stage('Checkout App Code') {
            steps {
                git 'https://github.com/Jithendarramagiri1998/snake-game.git'
            }
        }

        /* ───────────────────────────────
         *  SONARQUBE CODE ANALYSIS
         * ─────────────────────────────── */
        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('sonar-server') {
                    sh '''
                    sonar-scanner \
                      -Dsonar.projectKey=snake \
                      -Dsonar.sources=.
                    '''
                }
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
         *  CHECKOUT MONITORING CONFIG
         * ─────────────────────────────── */
        stage('Checkout Monitoring') {
            steps {
                dir('monitoring') {
                    git 'https://github.com/your-repo/monitoring-infra.git'
                }
            }
        }

        /* ───────────────────────────────
         *  CONNECT TO EKS CLUSTER
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
         *  DEPLOY APPLICATION TO EKS
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

        stage('Verify App Rollout') {
            steps {
                sh '''
                kubectl rollout status deployment/snake-game
                '''
            }
        }

        /* ───────────────────────────────
         *  DEPLOY PROMETHEUS
         * ─────────────────────────────── */
        stage('Deploy Prometheus') {
            steps {
                sh '''
                helm upgrade --install kube-prometheus-stack \
                  prometheus-community/kube-prometheus-stack \
                  -n monitoring \
                  -f monitoring/prometheus/values.yaml \
                  --create-namespace
                '''
            }
        }

        /* ───────────────────────────────
         *  DEPLOY GRAFANA DASHBOARDS
         * ─────────────────────────────── */
        stage('Deploy Grafana Dashboards') {
            steps {
                sh '''
                kubectl create configmap grafana-dashboards \
                  --from-file=monitoring/grafana/dashboards \
                  -n monitoring \
                  --dry-run=client -o yaml | kubectl apply -f -
                '''
            }
        }

        /* ───────────────────────────────
         *  RESTART GRAFANA
         * ─────────────────────────────── */
        stage('Restart Grafana') {
            steps {
                sh '''
                kubectl rollout restart deployment kube-prometheus-stack-grafana -n monitoring
                '''
            }
        }

        /* ───────────────────────────────
         *  VALIDATE PROMETHEUS & GRAFANA
         * ─────────────────────────────── */
        stage('Validate Monitoring') {
            steps {
                sh '''
                echo "=== Checking Prometheus ==="
                curl -I $(kubectl get svc kube-prometheus-stack-prometheus -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

                echo "=== Checking Grafana ==="
                curl -I $(kubectl get svc kube-prometheus-stack-grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
                '''
            }
        }
    }

    /* ───────────────────────────────
     *  POST ACTIONS
     * ─────────────────────────────── */
    post {
        success {
            echo "✔ CI/CD + Monitoring Deployment Completed Successfully!"
        }
        failure {
            echo "❌ Pipeline Failed. Check console logs!"
        }
    }
}

