# 🚀 End-to-End DevOps Project
**EKS Cluster + CI/CD + Monitoring (Prometheus & Grafana) + Application Deployment**

This document explains the complete end-to-end setup starting from creating a server, installing all required tools, configuring Jenkins, running Terraform to create EKS, and deploying the application with monitoring.  
Everything below is cleaned, corrected, structured, and ready for your GitHub README.

---
## Project Architecture Diagram

![Architecture](images/architecture-diagram.png)

---
## 📌 1. Create the Server (Amazon Linux / Ubuntu)

### Step 1: Launch EC2 Instance
- Choose **Ubuntu** or **Amazon Linux 2** as the OS.
- Recommended instance type:
  - `t2.medium` / `t3.medium`
  - **30GB storage**

### Step 2: Configure Security Group
Allow the following inbound ports:

| Port | Purpose        |
|------|----------------|
| 22   | SSH            |
| 8080 | Jenkins        |
| 9000 | SonarQube      |
| 3000 | Grafana        |
| 80   | Application    |
| 443  | Application    |

## 📌 2. Install Required Tools

Install all tools used for **CI/CD**, **Infrastructure**, **Image Building**, **Security**, and **Monitoring**.

### ✔ Tools to Install

| Tool            | Purpose                        |
|-----------------|--------------------------------|
| Jenkins         | CI/CD Automation               |
| Docker          | Build & Push Images            |
| AWS CLI         | EKS Authentication             |
| kubectl         | Kubernetes CLI                 |
| Helm            | Install monitoring stack       |
| Trivy           | Container security scanning    |
| Maven           | Build Java applications        |
| SonarScanner    | Code quality scanning          |
| Prometheus & Grafana | Monitoring                |

##  📌 3. Clone or Fork My Repository
git clone https://github.com/<your-repo>.git
cd <your-repo>


Follow my folder structure exactly as it exists in the repository.

## 📌 4. Terraform EKS Cluster Setup

You already created the EKS architecture using Terraform.
The Terraform execution is stored inside:

terraform-eks/Jenkinsfile

You have two options:
Option 1 – Run Terraform using Jenkins pipeline

(Create a Jenkins job → select pipeline → give path terraform-eks/Jenkinsfile)

● Option 2 – Run Terraform manually in CLI

From your instance:

cd terraform-eks
terraform init
terraform plan
terraform apply -auto-approve

## 📌 5. Jenkins Setup
Step 1: Install Jenkins

Login at:
👉 http://<server-ip>:8080

Install required plugins:

● Git

● Pipeline

● Credential Binding

● Docker 

● AWS Credentials

● Kubernetes CLI

● SonarQube Scanner

● Role-based Authorization (optional)

● BlueOcean (optional)

## 📌 6. Configure Credentials in Jenkins
Name	Type	Purpose
AWS Credentials	Secret Text or Access Keys	Terraform & EKS auth
docker	Username/Password	Push Docker Images
sonar	Token	SonarQube scanning
GitHub	SSH/HTTPS	Repository access

Also make sure to attach the correct IAM role to the EC2 for EKS management.

## 📌 7. Create Jenkins Jobs

You need two pipelines:

✔ Pipeline 1 — Terraform EKS Creation

Job name: eks-infra-pipeline
Path to Jenkinsfile:

terraform-eks/Jenkinsfile


This pipeline:

Initializes Terraform

Creates VPC, Subnets, IAM roles

Creates EKS Cluster

Generates kubeconfig

Installs ALB Ingress

After success → EKS will be created.

✔ Pipeline 2 — Application Deployment

Job name: app-deployment-pipeline
Path to Jenkinsfile:

Jenkinsfile


You are providing two pipelines:

Pipeline A → Deploy only into EKS
```groovy
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

        /* ─────────────────────────────────────────────
         * CHECKOUT CODE
         * ───────────────────────────────────────────── */
        stage('Checkout Code') {
            steps {
                git 'https://github.com/Jithendarramagiri1998/snake-game.git'
            }
        }

        /* ─────────────────────────────────────────────
         * MAVEN BUILD
         * ───────────────────────────────────────────── */
        stage('Maven Build') {
            when { expression { fileExists('pom.xml') } }
            steps {
                sh '''
                mvn clean package -DskipTests
                '''
            }
        }

        /* ─────────────────────────────────────────────
         * SONAR SCAN
         * ───────────────────────────────────────────── */
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
                          -Dsonar.exclusions=**/.terraform/**,**/terraform-eks/**,**/k8s/**,**/.git/**,**/*.gz,**/*.tar,**/*.tar.gz \
                          -Dsonar.javascript.exclusions=**/* \
                          -Dsonar.typescript.exclusions=**/*
                    """
                    }
                }
            }
        }
    }

        /* ─────────────────────────────────────────────
         * TRIVY SCAN
         * ───────────────────────────────────────────── */
        stage('Trivy Scan') {
            steps {
                sh 'trivy fs . --exit-code 0 --severity HIGH,CRITICAL'
            }
        }

        /* ─────────────────────────────────────────────
         * DOCKER BUILD + PUSH
         * ───────────────────────────────────────────── */
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

        /* ─────────────────────────────────────────────
         * UPDATE KUBECONFIG FOR JENKINS USER
         * ───────────────────────────────────────────── */
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

        /* ─────────────────────────────────────────────
         * DEPLOY TO EKS
         * ───────────────────────────────────────────── */
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

        /* ─────────────────────────────────────────────
         * VERIFY ROLLOUT
         * ───────────────────────────────────────────── */
                stage('Verify Rollout') {
            steps {
                sh '''
                export PATH=$BIN_PATH:$PATH
                export KUBECONFIG=$KUBECONFIG_PATH
                kubectl rollout status deployment/snake-game
                '''
            }
        }

    }   // ✅ CLOSE stages
    post {
        success {
            echo "✔ Pipeline Completed Successfully"
        }
        failure {
            echo "❌ Pipeline Failed"
        }
    }
}   // ✅ CLOSE pipeline

```

Pipeline B → Complete CI/CD + Monitoring + URLs
```groovy
pipeline {
    agent any

    triggers {
        githubPush()
    }

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
                                -Dsonar.token=${SONAR_TOKEN}
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
                sh """
                docker build -t snake-game:latest .
                docker tag snake-game:latest $APP_IMAGE

                echo "$DOCKER_CREDS_PSW" | docker login \
                    -u "$DOCKER_CREDS_USR" --password-stdin

                docker push $APP_IMAGE
                """
            }
        }

        stage('Update kubeconfig') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-jenkins-creds']]) {
                    sh """
                    export HOME=$HOME_DIR
                    export PATH=$BIN_PATH:$PATH
                    export AWS_REGION=$REGION
                    export KUBECONFIG=$KUBECONFIG_PATH

                    aws eks update-kubeconfig \
                      --name $CLUSTER_NAME \
                      --region $REGION \
                      --kubeconfig $KUBECONFIG_PATH
                    """
                }
            }
        }

        stage('Deploy to EKS') {
            steps {
                sh """
                export PATH=$BIN_PATH:$PATH
                export KUBECONFIG=$KUBECONFIG_PATH

                kubectl apply -f k8s/
                kubectl set image deployment/snake-game snake-game=$APP_IMAGE -n $NAMESPACE
                """
            }
        }

        stage('Verify Rollout') {
            steps {
                sh """
                export PATH=$BIN_PATH:$PATH
                export KUBECONFIG=$KUBECONFIG_PATH

                kubectl rollout status deployment/snake-game -n $NAMESPACE --timeout=180s
                """
            }
        }

        stage('Deploy Monitoring') {
            steps {
                sh """
                export PATH=$BIN_PATH:$PATH
                export KUBECONFIG=$KUBECONFIG_PATH

                helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
                helm repo update

                kubectl get ns monitoring || kubectl create namespace monitoring

                helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
                    -n monitoring --wait --timeout 5m
                """
            }
        }

        stage('Verify Monitoring') {
            steps {
                sh """
                export PATH=$BIN_PATH:$PATH
                export KUBECONFIG=$KUBECONFIG_PATH

                kubectl rollout status deployment/kube-prometheus-stack-grafana -n monitoring --timeout=300s

                kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus \
                    -n monitoring --timeout=300s
                """
            }
        }

        /* 
stage('Get Application URL') {
    steps {
        script {
            sh """
            export KUBECONFIG=$KUBECONFIG_PATH
            echo "🌐 Application URL:"

            SVC=\$(kubectl get svc -n $NAMESPACE \
                -o jsonpath='{.items[0].metadata.name}')

            APP_HOST=\$(kubectl get svc \$SVC -n $NAMESPACE \
                -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

            echo "✅ Application URL: http://\$APP_HOST"
            """
        }
    }
}
*/ 
        stage('Get Grafana URL & Credentials + Import Dashboards') {
            steps {
                script {
                    sh """
                    export KUBECONFIG=$KUBECONFIG_PATH

                    until kubectl get svc -n monitoring kube-prometheus-stack-grafana \
                        -o jsonpath="{.status.loadBalancer.ingress[0].hostname}" | grep -qE '[a-z]'; do
                        echo "⏳ Waiting for Grafana LoadBalancer..."
                        sleep 5
                    done

                    GRAFANA_HOST=\$(kubectl get svc -n monitoring kube-prometheus-stack-grafana \
                        -o jsonpath="{.status.loadBalancer.ingress[0].hostname}")

                    ADMIN_PASS=\$(kubectl get secret --namespace monitoring kube-prometheus-stack-grafana \
                        -o jsonpath="{.data.admin-password}" | base64 -d)

                    echo "✅ Grafana URL: http://\$GRAFANA_HOST"
                    echo "👤 Username: admin"
                    echo "🔑 Password: \$ADMIN_PASS"

                    curl -X POST http://admin:\$ADMIN_PASS@\$GRAFANA_HOST/api/dashboards/import \
                        -H "Content-Type: application/json" \
                        -d '{"dashboard": {"id": 15759},"overwrite": true,"inputs":[{"name":"DS_PROMETHEUS","type":"datasource","pluginId":"prometheus","value":"Prometheus"}]}'

                    curl -X POST http://admin:\$ADMIN_PASS@\$GRAFANA_HOST/api/dashboards/import \
                        -H "Content-Type: application/json" \
                        -d '{"dashboard": {"id": 1860},"overwrite": true,"inputs":[{"name":"DS_PROMETHEUS","type":"datasource","pluginId":"prometheus","value":"Prometheus"}]}'

                    echo "✅ Dashboards Imported Successfully"
                    """
                }
            }
        }
    }

    post {
        success { echo "✔ Pipeline Completed Successfully 🚀" }
        failure { echo "❌ Pipeline Failed" }
    }
}
```
Based on your requirement, you can run either pipeline.

## 📌 8. Accessing Application URLs

After the application pipeline succeeds, you can access the application using:

CLI Method (EKS Service URL)
export KUBECONFIG=/var/lib/jenkins/.kube/config
APP_SVC=$(kubectl get svc -n default -o jsonpath='{.items[0].metadata.name}')
kubectl get svc $APP_SVC -n default -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

## 📌 9. Monitoring: Prometheus & Grafana

Monitoring is installed using Helm in your pipeline.

✔ Get Grafana URL
kubectl get svc -n monitoring kube-prometheus-stack-grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

✔ Get Grafana Admin Password
kubectl get secret --namespace monitoring kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d

✔ Login Credentials
username: admin
password: <decoded_password>

## 📌 10. Web UI Access
Tool	URL
Jenkins	http://<server-ip>:8080
SonarQube	http://<server-ip>:9000
Grafana	http://<server-ip>:3000
Application	ALB DNS from EKS

## 📌 11. Notes

You can use both Jenkinsfiles (Terraform + Application) or use only the Application Jenkinsfile if you prefer running Terraform manually.

Terraform can be executed either through the Jenkins pipeline or manually using CLI commands.

When using the Application Jenkinsfile (Pipeline B), the pipeline automatically prints:

Application DNS URL

Grafana URL

Grafana Admin Password

These outputs will appear directly in the Jenkins console after the pipeline finishes.

If you face any issues during the setup or execution, you can troubleshoot or contact me anytime.

Make sure to follow your repository folder structure exactly when creating Jenkins jobs to avoid path-related errors.

## 📸 12. Output Screenshots (Add Here)

Jenkins Pipelines Success

EKS Cluster Screenshot

Grafana Dashboard

Application UI

Terraform apply output

SonarQube report
