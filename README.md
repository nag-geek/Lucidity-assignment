# Lucidity DevOps Assignment

End-to-end deployment of a Hello World microservice on AWS EKS using Terraform, Helm, and GitHub Actions, with Prometheus + Grafana for observability.

# Architecture
• Application: Python Flask service exposing /, /healthz, /metrics on port 8080.

• All three endpoints (`/`, `/healthz`, `/metrics`) are served by the same Flask process on port **8080**, routed by URL path. This simplifies the service and container configuration,Since all three endpoints run on the same Flask app, we just use a single port (8080) for everything. No need to configure multiple ports in the Dockerfile, Service, or Helm chart — keeps things simple.

• A separate metrics port is not configured; in production, `/metrics` would typically be exposed on a dedicated port (e.g., 9090) to restrict external access via network policy or firewall rules.


• Infrastructure: AWS EKS cluster provisioned via Terraform (VPC, EKS, ECR, managed node
groups)

• Deployment: Helm chart for the application

• Monitoring: kube-prometheus-stack (Prometheus + Grafana + Alertmanager + node-exporter + kube-state-metrics).

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

Before running Terraform, create a`terraform.tfvars` file with your environment-specific values.
This file is gitignored and never committed — it holds values that change per environment.


cd terraform

cat > terraform.tfvars << EOF

region = "ap-south-1"

aws_account_id = "account-id"

cicd_iam_user = "github-actions-iam-user"

EOF

terraform init

terraform plan

terraform apply

a. aws_account_id — AWS account ID, used to construct the ECR repository URL and IAM ARNs.

b. cicd_iam_user — the IAM user whose credentials are stored in GitHub Secrets (AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY). This user is granted AmazonEKSClusterAdminPolicy on the cluster via the access_entries block in eks.tf, allowing the GitHub Actions pipeline to authenticate and deploy to EKS.



## This creates:

- VPC :  custom VPC (`10.0.0.0/16`) with 2 public and 2 private subnets spread across 2 availability zones (`ap-south-1a`, `ap-south-1b`). Worker nodes live in private subnets (not internet-accessible). Public subnets are tagged for AWS Load Balancer discovery. A single NAT Gateway handles outbound traffic from private subnets — cost optimized for this assignment (production would use one NAT Gateway per AZ for HA).

- EKS Cluster :  Kubernetes v1.29 control plane with public API endpoint enabled so the GitHub Actions pipeline can authenticate and deploy remotely. Managed node group runs `t3.medium` instances with autoscaling configured (min: 1, max: 3, desired: 2). AWS manages node patching, AMI updates, and graceful drain on upgrades.

- ECR Repository : private container registry for the `hello-world` image with `scan_on_push` enabled. Image scanning checks for known CVEs on every push. Native IAM integration means EKS nodes pull images without separate registry credentials.

- IAM Access Entry : grants the CI/CD IAM user `AmazonEKSClusterAdminPolicy` on the cluster using EKS's modern access management (replaces the old `aws-auth` ConfigMap approach). This allows the GitHub Actions pipeline to run `helm upgrade` against the cluster without manual kubeconfig setup.


## 2. Configure kubectl


Once the cluster is provisioned, configuring local `kubectl` to talk to it:


aws eks update-kubeconfig --region ap-south-1 --name lucidity-cluster

This fetches the cluster endpoint and auth token from AWS and writes them to ~/.kube/config. After this, any kubectl or helm command runs against the EKS cluster — same mechanism the GitHub Actions pipeline uses, just running locally instead of on a runner VM.

Verify the nodes are up and ready:

kubectl get nodes


## 3. Deploy the Application

 GitHub Actions deploys automatically on every push to main

Add the following secrets to the repository (Settings → Secrets and variables → Actions).

These credentials authenticate the pipeline with AWS IAM to push images to ECR and deploy to EKS:

- AWS_ACCESS_KEY_ID
- AWS_SECRET_ACCESS_KEY
- AWS_ACCOUNT_ID

CI/CD Flow: Any push to main branch triggers the GitHub Actions pipeline which builds the Docker image, tags it with the commit SHA (`github.sha`) for traceability, pushes it to ECR, and deploys to EKS via Helm using `helm upgrade --install`.


## 4. Deploy Monitoring Stack

Add the Prometheus community Helm repository and deploy the full monitoring stack:

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
--namespace monitoring \
--create-namespace \
--values helm/monitoring/values.yaml


This deploys the kube-prometheus-stack chart which includes:

Prometheus : scrapes and stores metrics from the cluster and the application

Grafana : visualization dashboards for all collected metrics

Alertmanager : handles alerts fired by Prometheus
node-exporter — collects host-level metrics (CPU, memory, disk) from every node

kube-state-metrics : exposes Kubernetes object metrics (pod status, deployment replicas, resource requests/limits)


Added Custom values in helm/monitoring/values.yaml which includes configure retention (15 days), resource limits, and enable scraping across all namespaces so the application's ServiceMonitor is automatically discovered.


## 5. Access the Services

a. Port-forwarding is used instead of a LoadBalancer or Ingress to keep the setup cost-effective 

b. and simple to evaluate — no DNS configuration, no AWS Load Balancer provisioning required. 

c. In production, an Ingress with AWS Load Balancer Controller would be the correct approach.

d. Grafana credentials are hardcoded in helm/monitoring/values.yaml for evaluation convenience. 

e. In production, these would be stored in Kubernetes Secrets or an external secret manager like AWS Secrets Manager.


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

The application exposes Prometheus metrics at /metrics. The Helm chart includes a ServiceMonitor CRD that registers the service with the Prometheus Operator. Prometheus then scrapes the application every 15 seconds.

Cluster-level metrics (node CPU/memory, pod status, API server health) are collected by
node-exporter and kube-state-metrics, bundled with the kube-prometheus-stack chart.


# Design Decisions:

• Terraform modules over raw resources: Used official terraform-aws-modules/vpc/aws and terraform-aws-modules/eks/aws. Battle-tested, handles IAM, OIDC, security groups
automatically.

• Private subnets for nodes: Worker nodes are not internet-accessible. Egress via NAT
Gateway only

• Managed node groups: AWS handles patching, AMI rotation, graceful drain on upgrades.

• Single NAT Gateway: Cost optimization for assignment. Production would use one per AZ for
HA.

• ECR over DockerHub: Private registry, no rate limits, native IAM integration with EKS.

• github.sha as image tag: Every commit produces a unique, traceable image. Enables clean
rollbacks.

• kube-prometheus-stack over standalone Prometheus: Brings Prometheus Operator, which manages scrape config via ServiceMonitor CRDs instead of manual prometheus.yaml edits.

• REPLACE_ME_IN_CICD placeholder: Forces image reference to come from the pipeline,
prevents accidental hardcoded values.


# Cleanup

helm uninstall hello-world -n lucidity

helm uninstall monitoring -n monitoring

cd terraform

terraform destroy


