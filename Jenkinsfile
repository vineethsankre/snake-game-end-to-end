pipeline {
    agent any

    environment {
        DOCKER_CREDS = credentials('docker')
        SONAR = credentials('sonar')
        APP_IMAGE = "jithendarramagiri1998/snake-game:latest"
        CLUSTER_NAME = "my-eks-cluster"
        REGION = "ap-south-1"
        SERVICE_NAME = "snake-game"
        NAMESPACE = "default"
        HOME_DIR = "/var/lib/jenkins"
        KUBECONFIG_PATH = "/var/lib/jenkins/.kube/config"
        BIN_PATH = "/var/lib/jenkins/.local/bin"
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
                    script {
                        def scannerHome = tool name: 'SonarScanner', type: 'hudson.plugins.sonar.SonarRunnerInstallation'
                        sh """
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
                echo "$DOCKER_CREDS_PSW" | docker login -u "$DOCKER_CREDS_USR" --password-stdin
                docker push $APP_IMAGE
                '''
            }
        }

        stage('Update kubeconfig') {
            steps {
                withCredentials([aws(credentialsId: 'aws-jenkins-creds')]) {
                    sh '''
                    export HOME=$HOME_DIR
                    export PATH=$BIN_PATH:$PATH
                    export KUBECONFIG=$KUBECONFIG_PATH

                    mkdir -p $HOME_DIR/.kube

                    aws eks update-kubeconfig \
                      --name $CLUSTER_NAME \
                      --region $REGION \
                      --kubeconfig $KUBECONFIG_PATH

                    kubectl get nodes
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

        stage('Get LoadBalancer URL') {
            steps {
                script {
                    def lb_url = sh(
                        script: '''
                        export PATH=/var/lib/jenkins/.local/bin:$PATH
                        export KUBECONFIG=/var/lib/jenkins/.kube/config
                        kubectl get svc snake-game -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"
                        ''',
                        returnStdout: true
                    ).trim()

                    echo "***************************************************"
                    echo "  🚀 Application Deployed Successfully!"
                    echo "  🌐 URL: http://${lb_url}"
                    echo "***************************************************"
                }
            }
        }
    }

    post {
        success {
            echo "✔ Pipeline Completed Successfully"
        }
        failure {
            echo "❌ Pipeline Failed"
        }
    }
}
