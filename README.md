# Lucidity DevOps Assignment

End-to-end deployment of a Hello World microservice on AWS EKS using Terraform, Helm, and GitHub Actions, with Prometheus + Grafana for observability.

# Architecture
• Application: Python Flask service exposing /, /healthz, /metrics on port 8080
• Infrastructure: AWS EKS cluster provisioned via Terraform (VPC, EKS, ECR, managed node
groups)
• Deployment: Helm chart for the application
• Monitoring: kube-prometheus-stack (Prometheus + Grafana + Alertmanager + node-exporter
+ kube-state-metrics)
• CI/CD: GitHub Actions pipeline for build, push, and deploy

# Prerequisites
• AWS account with IAM user (programmatic access)
• Terraform >= 1.5
• kubectl
• Helm 3
• Docker
• AWS CLI configured

# Setup Instructions 

## 1. Provision Infrastructure

cd terraform
cat > terraform.tfvars << EOF
region = "ap-south-1"
aws_account_id = "account-id"
cicd_iam_user = "github-actions-iam-user"
EOF
terraform init
terraform plan
terraform apply

## This creates:
• VPC with 2 public + 2 private subnets across 2 AZs
• EKS cluster (v1.29) with managed node group (t3.medium, 1-3 nodes)
• ECR repository for the application image
• IAM access entry for the CI/CD user

## 2. Configure kubectl

aws eks update-kubeconfig --region ap-south-1 --name lucidity-cluster
kubectl get nodes

## 3. Deploy the Application

 GitHub Actions (automatic on push to main)
Add these secrets to the repo (Settings -> Secrets and variables -> Actions):
• AWS_ACCESS_KEY_ID
• AWS_SECRET_ACCESS_KEY
• AWS_ACCOUNT_ID

Push to main and the pipeline builds, pushes to ECR, and deploys via Helm.

## 4. Deploy Monitoring Stack

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
--namespace monitoring \
--create-namespace \
--values helm/monitoring/values.yaml


## 5. Access the Services

# Application
kubectl port-forward svc/hello-world 8080:80 -n lucidity
curl http://localhost:8080/

# Grafana
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring

# Open http://localhost:3000 - login: admin / admin123
# Prometheus
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring

# Grafana Dashboards

After logging in, import these dashboards via Dashboards -> New -> Import:

Dashboard                                     ID

Kubernetes Cluster Overview                   315
Node Exporter Full                            1860
Pod Resource Usage                            6417

# How Monitoring Works

The application exposes Prometheus metrics at /metrics. The Helm chart includes a
ServiceMonitor CRD that registers the service with the Prometheus Operator. Prometheus then scrapes the application every 15 seconds.

Cluster-level metrics (node CPU/memory, pod status, API server health) are collected by
node-exporter and kube-state-metrics, bundled with the kube-prometheus-stack chart.


# Design Decisions:

• Terraform modules over raw resources: Used official terraform-aws-modules/vpc/aws
and terraform-aws-modules/eks/aws. Battle-tested, handles IAM, OIDC, security groups
automatically.
• Private subnets for nodes: Worker nodes are not internet-accessible. Egress via NAT
Gateway only
• Managed node groups: AWS handles patching, AMI rotation, graceful drain on upgrades.
• Single NAT Gateway: Cost optimization for assignment. Production would use one per AZ for
HA.
• ECR over DockerHub: Private registry, no rate limits, native IAM integration with EKS.
• github.sha as image tag: Every commit produces a unique, traceable image. Enables clean
rollbacks.
• kube-prometheus-stack over standalone Prometheus: Brings Prometheus Operator, which
manages scrape config via ServiceMonitor CRDs instead of manual prometheus.yaml
edits.
• REPLACE_ME_IN_CICD placeholder: Forces image reference to come from the pipeline,
prevents accidental hardcoded values.


# Cleanup

helm uninstall hello-world -n lucidity
helm uninstall monitoring -n monitoring
cd terraform
terraform destroy


