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
        /* ───────────────────────────────
 *  PROMETHEUS + GRAFANA
 * ─────────────────────────────── */

   stage('Debug Helm Environment') {
    steps {
        sh '''
        echo ">>> Debug: BEGIN"
        echo "HOME (before override) = $HOME"
        echo "WHOAMI = $(whoami)"
        echo "PATH = $PATH"

        # show kubectl & aws (optional)
        which kubectl || echo "kubectl NOT FOUND"
        kubectl version --client --short || true
        which aws || echo "aws NOT FOUND"
        aws --version || true

        echo ">>> Debug: END"
        '''
    }
}

stage('Monitoring Deployment') {
    steps {
        sh '''
        set -euo pipefail
        echo ">>> Monitoring deployment - starting"

        # Ensure we use Jenkins home and kubeconfig used earlier
        export HOME=/var/lib/jenkins
        export KUBECONFIG=$HOME/.kube/config

        # Add a local bin to avoid sudo permission issues and ensure it's on PATH
        export HELM_INSTALL_DIR=$HOME/.local/bin
        mkdir -p "$HELM_INSTALL_DIR"
        export PATH="$HELM_INSTALL_DIR:$PATH"

        echo "HOME = $HOME"
        echo "KUBECONFIG = $KUBECONFIG"
        echo "PATH = $PATH"

        # If helm is missing, download a stable helm binary and install to $HOME/.local/bin
        if ! command -v helm >/dev/null 2>&1; then
          echo "helm not found — installing helm to $HELM_INSTALL_DIR"
          TMPDIR=$(mktemp -d)
          cd "$TMPDIR"
          HELM_VER="v3.12.3"   # locked version to avoid surprises; change if you prefer another
          curl -LO "https://get.helm.sh/helm-${HELM_VER}-linux-amd64.tar.gz"
          tar -zxvf "helm-${HELM_VER}-linux-amd64.tar.gz"
          mv linux-amd64/helm "$HELM_INSTALL_DIR/helm"
          chmod +x "$HELM_INSTALL_DIR/helm"
          cd -
          rm -rf "$TMPDIR"
        else
          echo "helm found at: $(which helm)"
        fi

        echo ">>> Helm version:"
        helm version

        # Ensure kubeconfig exists
        if [ ! -f "$KUBECONFIG" ]; then
          echo "ERROR: kubeconfig not found at $KUBECONFIG"
          ls -la $(dirname "$KUBECONFIG") || true
          exit 1
        fi

        # Add repo and update (always run to be idempotent)
        echo ">>> Adding prometheus-community repo (idempotent)"
        helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
        echo ">>> Updating helm repos"
        helm repo update

        echo ">>> Current helm repos:"
        helm repo list

        # Install/upgrade the kube-prometheus-stack chart
        echo ">>> Installing/upgrading kube-prometheus-stack"
        helm upgrade --install kube-prometheus-stack \
          prometheus-community/kube-prometheus-stack \
          -n monitoring --create-namespace --wait --timeout 10m

        echo ">>> Monitoring deployment - completed"
        '''
    }
}
        
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

    post {
        success {
            echo "✔ CI/CD PIPELINE COMPLETED SUCCESSFULLY!"
        }
        failure {
            echo "❌ Pipeline Failed. Check logs."
        }
    }
}
