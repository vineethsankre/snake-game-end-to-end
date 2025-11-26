pipeline {
    agent any

    environment {
        DOCKER_CREDS     = credentials('docker')
        SONAR            = credentials('sonar')
        APP_IMAGE        = "jithendarramagiri1998/snake-game:latest"
        CLUSTER_NAME     = "my-eks-cluster"
        REGION           = "ap-south-1"
        SERVICE_NAME     = "snake-game"
        NAMESPACE        = "default"
        HOME_DIR         = "/var/lib/jenkins"
        KUBECONFIG_PATH  = "/var/lib/jenkins/.kube/config"
        BIN_PATH         = "/var/lib/jenkins/.local/bin"
    }

    stages {

        stage('Checkout Code') {
            steps {
                git 'https://github.com/Jithendarramagiri1998/snake-game.git'
            }
        }

        stage('Maven Build') {
            when { expression { fileExists('pom.xml') } }
            steps {
                sh 'mvn clean package -DskipTests'
            }
        }

        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('MySonar') {
                    withCredentials([string(credentialsId: 'sonar', variable: 'SONAR_TOKEN')]) {
                        script {
                            def scannerHome = tool name: 'SonarScanner', type: 'hudson.plugins.sonar.SonarRunnerInstallation'
                            sh """
                                ${scannerHome}/bin/sonar-scanner \
                                -Dsonar.projectKey=snake \
                                -Dsonar.sources=. \
                                -Dsonar.host.url=${env.SONAR_HOST_URL} \
                                -Dsonar.token=${SONAR_TOKEN} \
                                -Dsonar.exclusions=**/.terraform/**,**/terraform-eks/**,**/k8s/**,**/.git/**,**/*.gz,**/*.tar,**/*.tar.gz
                            """
                        }
                    }
                }
            }
        }

        stage('Trivy Scan') {
            steps {
                sh 'trivy fs . --exit-code 0 --severity HIGH,CRITICAL'
            }
        }

        stage('Docker Build & Push') {
            steps {
                sh '''
                docker build -t snake-game:latest .
                docker tag snake-game:latest $APP_IMAGE

                echo "$DOCKER_CREDS_PSW" | docker login \
                    -u "$DOCKER_CREDS_USR" --password-stdin

                docker push $APP_IMAGE
                '''
            }
        }

        stage('Update kubeconfig') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-jenkins-creds']]) {
                    sh '''
                    export HOME=$HOME_DIR
                    export PATH=$BIN_PATH:$PATH
                    export AWS_REGION=$REGION
                    export KUBECONFIG=$KUBECONFIG_PATH

                    export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
                    export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
                    export AWS_SESSION_TOKEN=${AWS_SESSION_TOKEN}

                    mkdir -p $HOME_DIR/.kube
                    chown -R jenkins:jenkins $HOME_DIR/.kube

                    aws eks update-kubeconfig \
                      --name $CLUSTER_NAME \
                      --region $REGION \
                      --kubeconfig $KUBECONFIG_PATH

                    kubectl version --client
                    '''
                }
            }
        }

        stage('Deploy to EKS') {
            steps {
                sh '''
                export PATH=$BIN_PATH:$PATH
                export KUBECONFIG=$KUBECONFIG_PATH

                sed -i "s|IMAGE_PLACEHOLDER|$APP_IMAGE|g" k8s/deployment.yaml

                kubectl apply -f k8s/deployment.yaml --validate=false
                kubectl apply -f k8s/service.yaml --validate=false
                '''
            }
        }

        stage('Verify Rollout') {
            steps {
                sh '''
                export PATH=$BIN_PATH:$PATH
                export KUBECONFIG=$KUBECONFIG_PATH
                kubectl rollout status deployment/snake-game
                '''
            }
        }

        stage('Deploy Monitoring') {
            steps {
                sh '''
                export PATH=$BIN_PATH:$PATH
                export KUBECONFIG=$KUBECONFIG_PATH

                helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
                helm repo update

                kubectl get ns monitoring || kubectl create namespace monitoring

                helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring
                '''
            }
        }

       stage('Verify Monitoring') {
    steps {
        sh '''
        export PATH=$BIN_PATH:$PATH
        export KUBECONFIG=$KUBECONFIG_PATH

        echo "🔍 Checking Grafana..."
        kubectl rollout status deployment/kube-prometheus-stack-grafana -n monitoring --timeout=180s

        echo "🔍 Checking Prometheus Pod..."
        kubectl get pods -n monitoring | grep prometheus-kube-prometheus-stack-prometheus || true

        echo "🔍 Waiting for Prometheus Ready..."
        kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n monitoring --timeout=180s

        echo "✅ Monitoring Ready"
        '''
    }
}
        stage('Get Application URL') {
            steps {
                script {
                    sh '''
                    export KUBECONFIG=$KUBECONFIG_PATH
                    echo "🌐 Application URL:"
                    kubectl get svc snake-game -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"
                    echo
                    '''
                }
            }
        }

        stage('Get Grafana URL') {
            steps {
                script {
                    sh '''
                    export KUBECONFIG=$KUBECONFIG_PATH
                    echo "🌐 Grafana URL:"
                    kubectl get svc -n monitoring kube-prometheus-stack-grafana -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"
                    echo
                    '''
                }
            }
        }

        stage('Import Dashboards') {
            steps {
                script {
                    sh '''
                    export KUBECONFIG=$KUBECONFIG_PATH

                    GRAFANA_HOST=$(kubectl get svc -n monitoring kube-prometheus-stack-grafana -o jsonpath="{.status.loadBalancer.ingress[0].hostname}")

                    ADMIN_PASS=$(kubectl get secret --namespace monitoring kube-prometheus-stack-grafana \
                        -o jsonpath="{.data.admin-password}" | base64 -d)

                    curl -X POST http://admin:${ADMIN_PASS}@${GRAFANA_HOST}/api/dashboards/import \
                        -H "Content-Type: application/json" \
                        -d '{"dashboard": {"id": 15759},"overwrite": true,"inputs":[{"name":"DS_PROMETHEUS","type":"datasource","pluginId":"prometheus","value":"Prometheus"}]}'

                    curl -X POST http://admin:${ADMIN_PASS}@${GRAFANA_HOST}/api/dashboards/import \
                        -H "Content-Type: application/json" \
                        -d '{"dashboard": {"id": 1860},"overwrite": true,"inputs":[{"name":"DS_PROMETHEUS","type":"datasource","pluginId":"prometheus","value":"Prometheus"}]}'
                    '''
                }
            }
        }

    }

    post {
        success { echo "✔ Pipeline Completed Successfully" }
        failure { echo "❌ Pipeline Failed" }
    }
}
