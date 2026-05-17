# AWS Hub-and-Spoke EKS — Enterprise DevSecOps Assessment

[![Terraform](https://img.shields.io/badge/Terraform-1.8.x-7B42BC?logo=terraform)](https://www.terraform.io/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.29-326CE5?logo=kubernetes)](https://kubernetes.io/)
[![Istio](https://img.shields.io/badge/Istio-1.21-466BB0?logo=istio)](https://istio.io/)
[![Helm](https://img.shields.io/badge/Helm-3.14-0F1689?logo=helm)](https://helm.sh/)
[![Azure DevOps](https://img.shields.io/badge/Azure%20DevOps-CI%2FCD-0078D7?logo=azure-devops)](https://azure.microsoft.com/en-us/products/devops/)
[![Gitleaks](https://img.shields.io/badge/Gitleaks-Secrets%20Scan-red)](https://github.com/gitleaks/gitleaks)

---

## Executive Summary

This repository delivers a **production-grade, enterprise DevSecOps** solution for an AWS Hub-and-Spoke network topology assessment. The architecture implements a **zero-trust, defense-in-depth** network design where workloads in a private EKS cluster are reachable only through a controlled, observable traffic path — never directly from the internet.

| Layer | Technology | Purpose |
|---|---|---|
| **Edge / Ingress** | AWS ALB (Hub VPC) | Internet-facing entry point, TLS termination |
| **Network Fabric** | AWS Transit Gateway | Secure cross-VPC routing (Hub ↔ Spoke) |
| **Container Platform** | Amazon EKS 1.29 | Managed Kubernetes in private Spoke VPC |
| **Service Mesh** | Istio 1.21 | mTLS, traffic management, observability |
| **App Delivery** | Helm 3 | Versioned, templated microservice deployments |
| **IaC** | Terraform 1.8 (official modules) | Reproducible, auditable infrastructure |
| **CI/CD** | Azure DevOps YAML Pipelines | Gated, automated delivery |
| **Security Scanning** | Gitleaks + tfsec | Shift-left secrets detection + SAST |

---

## Architecture Diagram

```mermaid
flowchart TD
    User(["👤 Internet User"])

    subgraph HubVPC["🌐 Hub VPC — 10.0.0.0/16 (Public)"]
        IGW["Internet Gateway"]
        ALB["Application Load Balancer\n(internet-facing, port 80/443)"]
        ALB_SG["ALB Security Group\n✅ 0.0.0.0/0 → 80, 443"]
    end

    subgraph TGW["🔀 AWS Transit Gateway"]
        TGW_RT_HUB["TGW Route Table — Hub\nPropagates: Spoke CIDR"]
        TGW_RT_SPOKE["TGW Route Table — Spoke\nPropagates: Hub CIDR"]
    end

    subgraph SpokeVPC["🔒 Spoke VPC — 10.1.0.0/16 (Private Only)"]
        subgraph EKS["☸️ Amazon EKS Cluster"]
            ISTIO_GW["Istio Ingress Gateway\n(NLB — internal)"]
            subgraph IstioMesh["Istio Service Mesh (mTLS)"]
                VS["VirtualService\n/app1 → app1-svc\n/app2 → app2-svc"]
                APP1["🐳 app1 Pods\n(nginx:1.27-alpine)\n× 2 replicas"]
                APP2["🐳 app2 Pods\n(nginx:1.27-alpine)\n× 2 replicas"]
            end
        end
        NODE_SG["Node Security Group\n✅ Hub CIDR ONLY → all ports\n❌ No direct internet"]
    end

    User -->|"HTTPS/HTTP"| IGW
    IGW --> ALB_SG --> ALB
    ALB -->|"IP Target (Spoke CIDR)"| TGW
    TGW --> TGW_RT_HUB & TGW_RT_SPOKE
    TGW_RT_SPOKE -->|"Route: 10.0.0.0/16 via TGW"| NODE_SG
    NODE_SG --> ISTIO_GW
    ISTIO_GW --> VS
    VS -->|"/app1"| APP1
    VS -->|"/app2"| APP2
```

### Traffic Flow (Step-by-Step)

1. **User → IGW → ALB**: HTTP/HTTPS hits the ALB Security Group (allows `0.0.0.0/0:80,443`). ALB is in Hub public subnets.
2. **ALB → TGW**: ALB forwards to the Istio Ingress Gateway **IP target** in the Spoke VPC. The Hub route table routes `10.1.0.0/16` via TGW.
3. **TGW → Spoke VPC**: TGW route table for Spoke knows the Hub CIDR via propagation. Return traffic flows back via the same path.
4. **Node SG → Istio GW**: EKS node security group only permits ingress from Hub VPC CIDR (`10.0.0.0/16`) — no other inbound is allowed.
5. **Istio Gateway → VirtualService**: The Istio Gateway CRD accepts the traffic, and the VirtualService routes based on URI prefix (`/app1` or `/app2`).
6. **VirtualService → Pods**: mTLS-encrypted traffic reaches the nginx pods. DestinationRules enforce circuit-breaking and connection pool limits.

---

## Repository Structure

```
aws-hub-spoke-eks-assessment/
├── .gitleaks.toml                          # Secrets scanning configuration
├── README.md                               # This document
│
├── terraform/
│   ├── main.tf                             # Hub VPC, Spoke VPC, TGW, route tables
│   ├── alb.tf                              # Internet-facing ALB, security groups
│   ├── eks.tf                              # EKS cluster, node groups, VPC endpoints
│   ├── variables.tf                        # All input variables
│   └── outputs.tf                          # Key outputs (ALB DNS, cluster endpoint)
│
├── kubernetes/
│   ├── istio/
│   │   ├── gateway.yaml                    # Istio Gateway CRD (port 80/443)
│   │   └── virtualservice.yaml             # VirtualService + DestinationRules
│   └── helm/
│       └── microservice/                   # Generic Helm chart (app1 & app2)
│           ├── Chart.yaml
│           ├── values.yaml
│           └── templates/
│               ├── deployment.yaml         # Nginx + probes + security context
│               ├── service.yaml            # ClusterIP service
│               ├── hpa.yaml                # HorizontalPodAutoscaler
│               ├── pdb.yaml                # PodDisruptionBudget
│               ├── resourcequota.yaml      # ResourceQuota + LimitRange
│               └── configmap.yaml          # Nginx config with security headers
│
└── pipelines/
    ├── terraform-ci-cd.yaml                # ADO: IaC pipeline (validate → plan → apply)
    └── app-ci-cd.yaml                      # ADO: App pipeline (scan → deploy → test)
```

---

## Security Boundaries Matrix

| Component | Boundary | Enforcement |
|---|---|---|
| **ALB Security Group** | Allows `0.0.0.0/0 → 80, 443` | AWS Security Group |
| **ALB Security Group** | Denies all other inbound | Implicit deny |
| **TGW Route Table (Hub)** | Only routes to Spoke CIDR | Explicit route table |
| **TGW Route Table (Spoke)** | Only routes to Hub CIDR | Explicit route table |
| **EKS Node Security Group** | Allows ingress **only** from Hub VPC CIDR `10.0.0.0/16` | AWS Security Group |
| **EKS Node Security Group** | Node-to-node: self-reference only | AWS Security Group |
| **Istio mTLS** | All pod-to-pod traffic encrypted | DestinationRule `ISTIO_MUTUAL` |
| **Namespace ResourceQuota** | CPU/Memory caps, max 20 pods | Kubernetes ResourceQuota |
| **Container Security Context** | `allowPrivilegeEscalation: false` | Kubernetes SecurityContext |
| **Gitleaks** | Blocks commits with embedded secrets | Pre-pipeline scan |
| **tfsec** | Blocks HIGH+ severity IaC findings | Pipeline security stage |

---

## Prerequisites

| Tool | Minimum Version | Install |
|---|---|---|
| Terraform | 1.8.x | [terraform.io](https://www.terraform.io/downloads) |
| AWS CLI | 2.x | [aws.amazon.com/cli](https://aws.amazon.com/cli/) |
| kubectl | 1.29.x | [kubernetes.io](https://kubernetes.io/docs/tasks/tools/) |
| Helm | 3.14.x | [helm.sh](https://helm.sh/docs/intro/install/) |
| istioctl | 1.21.x | [istio.io](https://istio.io/latest/docs/setup/getting-started/) |

---

## Deployment Guide

### Step 1 — AWS Credentials

```bash
export AWS_ACCESS_KEY_ID="your-access-key-id"
export AWS_SECRET_ACCESS_KEY="your-secret-access-key"
export AWS_DEFAULT_REGION="ap-southeast-1"
```

### Step 2 — Deploy Infrastructure (Terraform)

```bash
cd terraform/

# Initialise with remote backend (S3 + DynamoDB)
terraform init \
  -backend-config="bucket=your-tf-state-bucket" \
  -backend-config="key=hub-spoke/terraform.tfstate" \
  -backend-config="region=ap-southeast-1"

# Review plan
terraform plan -var="aws_region=ap-southeast-1"

# Apply
terraform apply -var="aws_region=ap-southeast-1" -auto-approve

# Capture outputs
terraform output
```

### Step 3 — Configure kubectl

```bash
# Output from terraform
aws eks update-kubeconfig \
  --region ap-southeast-1 \
  --name hubspoke-eks-cluster
```

### Step 4 — Install Istio

```bash
# Download istioctl
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.21.0 sh -
export PATH="$PWD/istio-1.21.0/bin:$PATH"

# Install Istio with default profile
istioctl install --set profile=default -y

# Enable automatic sidecar injection in the default namespace
kubectl label namespace default istio-injection=enabled
```

### Step 5 — Apply Istio Gateway & VirtualService

```bash
kubectl apply -f kubernetes/istio/gateway.yaml
kubectl apply -f kubernetes/istio/virtualservice.yaml

# Verify
kubectl get gateway -n istio-system
kubectl get virtualservice -n default
kubectl get destinationrule -n default
```

### Step 6 — Deploy Microservices via Helm

```bash
# Deploy app1
helm upgrade --install app1 kubernetes/helm/microservice \
  --namespace default \
  --set appName=app1 \
  --set image.tag=1.27.0-alpine \
  --wait

# Deploy app2
helm upgrade --install app2 kubernetes/helm/microservice \
  --namespace default \
  --set appName=app2 \
  --set image.tag=1.27.0-alpine \
  --wait

# Verify pods
kubectl get pods -n default
kubectl get svc -n default
```

### Step 7 — Verify End-to-End

```bash
# Get ALB DNS (from Terraform output)
ALB_DNS=$(terraform -chdir=terraform output -raw alb_dns_name)

# Test app1
curl http://$ALB_DNS/app1/

# Test app2
curl http://$ALB_DNS/app2/
```

---

## Azure DevOps CI/CD Pipeline Setup

### Variable Groups (Library)

Create the following Variable Groups in **Azure DevOps → Pipelines → Library**:

#### 1. `aws-credentials`
| Variable | Description | Secret |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | AWS IAM user access key | ✅ Yes |
| `AWS_SECRET_ACCESS_KEY` | AWS IAM user secret key | ✅ Yes |
| `AWS_REGION` | Target region (e.g., `ap-southeast-1`) | No |

#### 2. `tf-backend`
| Variable | Description | Secret |
|---|---|---|
| `TF_BACKEND_BUCKET` | S3 bucket name for Terraform state | No |
| `TF_BACKEND_KEY` | S3 object key (path) for state file | No |
| `TF_BACKEND_REGION` | S3 bucket region | No |

#### 3. `eks-config`
| Variable | Description | Secret |
|---|---|---|
| `EKS_CLUSTER_NAME` | EKS cluster name (e.g., `hubspoke-eks-cluster`) | No |

#### 4. `app-config`
| Variable | Description | Secret |
|---|---|---|
| `APP1_IMAGE_TAG` | Nginx image tag for app1 (e.g., `1.27.0-alpine`) | No |
| `APP2_IMAGE_TAG` | Nginx image tag for app2 (e.g., `1.27.0-alpine`) | No |
| `NAMESPACE` | Kubernetes namespace (e.g., `default`) | No |

### Pipeline Registration

1. In Azure DevOps, go to **Pipelines → New Pipeline**
2. Choose **Azure Repos Git** or **GitHub**
3. Select **Existing Azure Pipelines YAML file**
4. For Terraform pipeline: select `pipelines/terraform-ci-cd.yaml`
5. For App pipeline: select `pipelines/app-ci-cd.yaml`
6. Create a **Production** Environment with an **Approval Gate** (Environments → Approvals and Checks)

### Pipeline Flow

```
terraform-ci-cd.yaml:
  SecurityScan (Gitleaks + tfsec)
      ↓
  Validate (fmt + init + validate)
      ↓
  Plan (terraform plan → artifact)
      ↓
  Apply [APPROVAL GATE] (terraform apply — main branch only)

app-ci-cd.yaml:
  SecurityScan (Gitleaks + Helm lint)
      ↓
  DeployIstio (Gateway + VirtualService)
      ↓
  DeployApps (Helm upgrade app1 + app2 with drift detection)
      ↓
  SmokeTest (curl /app1 + /app2 endpoints)
```

---

## Kubernetes Components

### Probes Summary

| Probe | Path | Initial Delay | Period | Failure Threshold |
|---|---|---|---|---|
| **Startup** | `GET /` port 80 | 0s | 10s | 30 (5 min max) |
| **Liveness** | `GET /` port 80 | 15s | 20s | 3 |
| **Readiness** | `GET /` port 80 | 5s | 10s | 3 |

### Resource Governance

| Resource | Request | Limit |
|---|---|---|
| CPU | 100m | 500m |
| Memory | 128Mi | 256Mi |

### Autoscaling

| Parameter | Value |
|---|---|
| Min Replicas | 2 |
| Max Replicas | 10 |
| CPU Target | 70% |
| Memory Target | 80% |
| Scale-down Cooldown | 5 minutes |

---

## DevSecOps Controls

| Control | Tool | Stage | Severity |
|---|---|---|---|
| Secrets Detection | Gitleaks 8.18 | Pre-pipeline | CRITICAL/HIGH |
| Terraform SAST | tfsec 1.28 | Security stage | HIGH+ |
| Image vulnerability scan | (integrate Trivy in prod) | Build stage | — |
| Network isolation | AWS Security Groups | Infrastructure | — |
| Workload isolation | Kubernetes RBAC + ResourceQuota | Runtime | — |
| mTLS encryption | Istio DestinationRule | Runtime | — |
| Secrets management | AWS Secrets Manager (IRSA) | Runtime | — |

---

## Cost Considerations

> ⚠️ This architecture provisions billable AWS resources. Estimated cost: **~$150–250/month** for a minimal 3-node EKS cluster + Transit Gateway + ALB + VPC endpoints.
>
> **Destroy when not in use:**
> ```bash
> terraform destroy -var="aws_region=ap-southeast-1"
> ```

---

*Prepared by: Vivek J S | Platform Engineering*
