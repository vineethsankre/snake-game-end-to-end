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

        /* ───────────────────────────────
         *  CHECKOUT APPLICATION CODE
         * ─────────────────────────────── */
        stage('Checkout Code') {
            steps {
                git 'https://github.com/Jithendarramagiri1998/snake-game.git'
            }
        }

        /* ───────────────────────────────
         *  MAVEN BUILD
         * ─────────────────────────────── */
        stage('Maven Build') {
            when { expression { fileExists('pom.xml') } }
            steps {
                sh """
                echo "Maven project detected. Running Maven build..."
                mvn clean package -DskipTests
                """
            }
        }

        /* ───────────────────────────────
         *  SONARQUBE ANALYSIS
         * ─────────────────────────────── */
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

        /* ───────────────────────────────
         *  TRIVY SCAN
         * ─────────────────────────────── */
        stage('Trivy Scan') {
            steps {
                sh 'trivy fs . --exit-code 0 --severity HIGH,CRITICAL'
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
         *  UPDATE KUBECONFIG
         * ─────────────────────────────── */
        stage('Update kubeconfig') {
    steps {
        withCredentials([aws(credentialsId: 'aws-jenkins-creds')]) {
            sh '''
                echo ">>> Setting HOME for Jenkins"
                export HOME=/var/lib/jenkins
                mkdir -p $HOME/.kube

                export KUBECONFIG=$HOME/.kube/config

                aws sts get-caller-identity

                aws eks update-kubeconfig \
                  --name $CLUSTER_NAME \
                  --region $REGION \
                  --kubeconfig $HOME/.kube/config

                echo ">>> kubeconfig created:"
                ls -l $HOME/.kube/
            '''
        }
    }
}

        /* ───────────────────────────────
         *  DEPLOY TO EKS
         * ─────────────────────────────── */
        stage('Deploy to EKS') {
    steps {
        withCredentials([aws(credentialsId: 'aws-jenkins-creds')]) {
            sh '''
                echo ">>> Setting HOME & KUBECONFIG"
                export HOME=/var/lib/jenkins
                export KUBECONFIG=$HOME/.kube/config

                echo ">>> Checking Identity"
                aws sts get-caller-identity

                echo ">>> Checking cluster connectivity"
                kubectl --kubeconfig=$KUBECONFIG get nodes

                echo ">>> Updating deployment image"
                sed -i "s|IMAGE_PLACEHOLDER|$APP_IMAGE|g" k8s/deployment.yaml

                echo ">>> Applying manifests"
                kubectl --kubeconfig=$KUBECONFIG apply -f k8s/deployment.yaml --validate=false
                kubectl --kubeconfig=$KUBECONFIG apply -f k8s/service.yaml --validate=false
            '''
        }
    }
}
        /* ───────────────────────────────
         *  VERIFY ROLLOUT
         * ─────────────────────────────── */
        stage('Verify Rollout') {
    steps {
        withCredentials([aws(credentialsId: 'aws-jenkins-creds')]) {
            sh '''
                export HOME=/var/lib/jenkins
                export KUBECONFIG=$HOME/.kube/config

                kubectl --kubeconfig=$KUBECONFIG rollout status deployment/snake-game
            '''
        }
    }
}

        /* ─────────────────────────────────────
         *  FETCH LOAD BALANCER URL
         * ───────────────────────────────────── */
        stage('Get LoadBalancer URL') {
            steps {
                script {
                    def lb_url = sh(
                        script: '''
                            export KUBECONFIG=/root/.kube/config
                            kubectl get svc ${SERVICE_NAME} -n ${NAMESPACE} -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"
                        ''',
                        returnStdout: true
                    ).trim()

                    echo "*******************************************************"
                    echo "  🚀 Your Application LoadBalancer URL:"
                    echo "  http://${lb_url}"
                    echo "*******************************************************"
                }
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
