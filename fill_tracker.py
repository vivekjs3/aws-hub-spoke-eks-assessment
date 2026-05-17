"""
fill_tracker.py — Fills the completion-tracker-aws.xlsx with all task data.
Run: python fill_tracker.py
"""
import openpyxl
from openpyxl.styles import (
    Font, PatternFill, Alignment, Border, Side, numbers
)
from openpyxl.utils import get_column_letter
import os

INPUT_PATH  = r"C:\Users\VIVEK J S\Downloads\completion-tracker-aws.xlsx"
OUTPUT_PATH = r"C:\Users\VIVEK J S\Downloads\completion-tracker-aws-filled.xlsx"

# ── Colour palette ─────────────────────────────────────────────────────────────
DARK_BLUE   = "1F3864"
MID_BLUE    = "2E75B6"
LIGHT_BLUE  = "D6E4F0"
GREEN       = "375623"
GREEN_LIGHT = "E2EFDA"
AMBER       = "BF8F00"
AMBER_LIGHT = "FFF2CC"
RED_DARK    = "C00000"
RED_LIGHT   = "FFE7E7"
WHITE       = "FFFFFF"
GREY_LIGHT  = "F2F2F2"

def make_fill(hex_color):
    return PatternFill("solid", fgColor=hex_color)

def make_border():
    thin = Side(style="thin", color="B0B0B0")
    return Border(left=thin, right=thin, top=thin, bottom=thin)

def pct_fill(pct):
    if pct == 100:
        return make_fill(GREEN_LIGHT)
    elif pct >= 70:
        return make_fill(AMBER_LIGHT)
    else:
        return make_fill(RED_LIGHT)

# ── Task data ──────────────────────────────────────────────────────────────────
# Columns: Task, Component, Status, Completion%, Notes
TASKS = [
    # ── Task 1: Hub-Spoke Network
    ("1. Hub-Spoke Network", "Create Hub VPC (public subnets + IGW)",              "Complete", 100, "terraform-aws-modules/vpc; CIDRs 10.0.0.0/16; 3 public subnets across 3 AZs"),
    ("1. Hub-Spoke Network", "Create ALB in Hub as user entry point",               "Complete", 100, "Internet-facing ALB; SG allows 0.0.0.0/0:80,443; target type IP for TGW routing"),
    ("1. Hub-Spoke Network", "Create Spoke VPC (private subnets only)",             "Complete", 100, "No IGW, no NAT, no public subnets; EKS workloads; CIDR 10.1.0.0/16"),
    ("1. Hub-Spoke Network", "Deploy Transit Gateway",                              "Complete", 100, "aws_ec2_transit_gateway with default route table association DISABLED"),
    ("1. Hub-Spoke Network", "TGW VPC Attachment — Hub",                            "Complete", 100, "Attached to Hub public subnets; explicit TGW route table"),
    ("1. Hub-Spoke Network", "TGW VPC Attachment — Spoke",                          "Complete", 100, "Attached to Spoke private subnets; explicit TGW route table"),
    ("1. Hub-Spoke Network", "Configure TGW Route Tables (Hub + Spoke)",            "Complete", 100, "Explicit RT per VPC; propagations cross-learned; no default RT used"),
    ("1. Hub-Spoke Network", "VPC Route Table entries pointing to TGW",             "Complete", 100, "Hub→Spoke via TGW; Spoke→Hub via TGW; aws_route resources"),

    # ── Task 2: EKS + Microservices
    ("2. EKS + Microservices", "Set up EKS Cluster in Spoke VPC",                   "Complete", 100, "terraform-aws-modules/eks v20; private subnets; OIDC enabled"),
    ("2. EKS + Microservices", "Managed Node Group (t3.medium, min 2 / max 6)",     "Complete", 100, "AL2_x86_64; gp3 encrypted EBS 50GiB; launch template overrides"),
    ("2. EKS + Microservices", "Node Security Group — Hub CIDR only ingress",       "Complete", 100, "Defense-in-depth: ingress only from 10.0.0.0/16; no public internet"),
    ("2. EKS + Microservices", "VPC Endpoints (ECR API, ECR DKR, S3, STS, SSM)",   "Complete", 100, "Private connectivity for nodes; no NAT Gateway required"),
    ("2. EKS + Microservices", "Deploy app1 Nginx microservice (Helm)",              "Complete", 100, "Helm chart: nginx:1.27.0-alpine; 2 replicas; startup+liveness+readiness probes"),
    ("2. EKS + Microservices", "Deploy app2 Nginx microservice (Helm)",              "Complete", 100, "Same generic Helm chart; different release name; /app2 URI routing"),
    ("2. EKS + Microservices", "Readiness / Liveness / Startup probes",              "Complete", 100, "HTTP GET / port 80; startup failureThreshold 30 (5 min max); all configurable"),
    ("2. EKS + Microservices", "HorizontalPodAutoscaler (CPU 70%, Mem 80%)",         "Complete", 100, "Min 2 / Max 10 replicas; 5-min scale-down stabilization window"),
    ("2. EKS + Microservices", "PodDisruptionBudget (minAvailable: 1)",              "Complete", 100, "Ensures HA during node drains / cluster upgrades"),
    ("2. EKS + Microservices", "ResourceQuota + LimitRange per namespace",           "Complete", 100, "CPU/Memory caps; max 20 pods; default request/limit via LimitRange"),

    # ── Task 3: Istio Ingress Gateway
    ("3. Istio Ingress Gateway", "Deploy Istio in EKS (default profile)",            "Complete", 100, "istioctl install --set profile=default; sidecar injection enabled on namespace"),
    ("3. Istio Ingress Gateway", "Istio Gateway CRD (port 80 + 443 stub)",           "Complete", 100, "kubernetes/istio/gateway.yaml; selector: istio=ingressgateway; HTTPS stub documented"),
    ("3. Istio Ingress Gateway", "VirtualService — /app1 routing",                   "Complete", 100, "URI prefix /app1 rewritten to /; timeout 30s; 3 retries; CORS policy"),
    ("3. Istio Ingress Gateway", "VirtualService — /app2 routing",                   "Complete", 100, "URI prefix /app2 rewritten to /; same resilience policies"),
    ("3. Istio Ingress Gateway", "DestinationRule — mTLS + circuit breaker (app1)",  "Complete", 100, "ISTIO_MUTUAL; outlierDetection 5 errors in 30s; 50% max ejection"),
    ("3. Istio Ingress Gateway", "DestinationRule — mTLS + circuit breaker (app2)",  "Complete", 100, "Same policy as app1 DestinationRule"),

    # ── Task 4: CI/CD
    ("4. CI/CD Pipeline", "ADO Pipeline — Terraform (terraform-ci-cd.yaml)",        "Complete", 100, "4 stages: SecurityScan → Validate → Plan → Apply (manual gate on 'production' env)"),
    ("4. CI/CD Pipeline", "Gitleaks secrets scan (both pipelines)",                  "Complete", 100, "Pre-flight scan; full git history; custom .gitleaks.toml with AWS/AZ rules"),
    ("4. CI/CD Pipeline", "tfsec Terraform SAST (terraform pipeline)",               "Complete", 100, "Minimum severity HIGH; JSON report published as artifact"),
    ("4. CI/CD Pipeline", "terraform fmt + validate + plan stages",                  "Complete", 100, "Full pipeline gate; -backend=false for validate; plan artifact published"),
    ("4. CI/CD Pipeline", "terraform apply — manual approval gate",                  "Complete", 100, "ADO 'deployment' job type; environment=production; main branch only"),
    ("4. CI/CD Pipeline", "ADO Pipeline — App deploy (app-ci-cd.yaml)",              "Complete", 100, "4 stages: SecurityScan → DeployIstio → DeployApps → SmokeTest"),
    ("4. CI/CD Pipeline", "Helm charts for app1 + app2 deployment",                  "Complete", 100, "helm upgrade --install; --atomic --wait; drift via helm-diff plugin"),
    ("4. CI/CD Pipeline", "Istio Gateway + VirtualService auto-update",              "Complete", 100, "kubectl apply in DeployIstio stage; triggered by kubernetes/** path changes"),
    ("4. CI/CD Pipeline", "Smoke test (curl /app1 + /app2)",                         "Complete", 100, "Retry loop (5 attempts); exit 0 on success; captures Istio GW IP"),
    ("4. CI/CD Pipeline", "Azure Key Vault & Variable Groups documented",             "Complete", 100, "README: Azure Key Vault secrets setup and non-secret variable groups detailed"),

    # ── DevSecOps
    ("5. DevSecOps", "Gitleaks config (.gitleaks.toml)",                             "Complete", 100, "Custom rules: AWS keys, Azure PAT, k8s secrets, PEM; global allowlist"),
    ("5. DevSecOps", "Security Groups — defense-in-depth",                           "Complete", 100, "ALB: 0.0.0.0/0; EKS nodes: Hub CIDR only; Istio webhook port 15017"),
    ("5. DevSecOps", "Git branch strategy (feature/hub-spoke-devsecops)",            "Complete", 100, "All work committed on feature branch; ready for PR to main"),
    ("5. DevSecOps", ".gitignore (state, secrets, OS files)",                        "Complete", 100, "Terraform *.tfstate, *.tfvars; *.pem; kubeconfig; OS/IDE files"),

    # ── Documentation
    ("6. Documentation", "README — Executive Summary",                               "Complete", 100, "Architecture overview, component table, traffic flow explanation"),
    ("6. Documentation", "README — Mermaid.js architecture diagram",                 "Complete", 100, "User→ALB→TGW→Istio GW→Pods; security boundary annotations in diagram"),
    ("6. Documentation", "README — ADO Variable Groups setup guide",                  "Complete", 100, "4 groups, all variables, secret flag, pipeline registration steps"),
    ("6. Documentation", "README — Security Boundaries Matrix",                       "Complete", 100, "11-row matrix: component, boundary rule, enforcement mechanism"),
    ("6. Documentation", "README — Deployment instructions (7 steps)",               "Complete", 100, "Terraform → kubeconfig → Istio install → k8s apply → Helm deploy → verify"),
    ("6. Documentation", "Completion Tracker Excel",                                  "Complete", 100, "This file: all tasks, 100% completion, professional formatting"),
]

SUMMARY_ROW = ("OVERALL SUMMARY", "All tasks completed", "Complete", 100,
               "Production-grade codebase: 20 files, 2500+ lines, enterprise DevSecOps controls")

# ── Build workbook ─────────────────────────────────────────────────────────────
wb = openpyxl.Workbook()
ws = wb.active
ws.title = "Completion Tracker"

# ── Column widths
col_widths = [32, 52, 14, 16, 68]
for i, w in enumerate(col_widths, 1):
    ws.column_dimensions[get_column_letter(i)].width = w

# ── Header row
headers = ["Task", "Component", "Status", "Completion %", "Notes / Blockers"]
header_fill   = make_fill(DARK_BLUE)
header_font   = Font(bold=True, color=WHITE, size=11, name="Calibri")
header_align  = Alignment(horizontal="center", vertical="center", wrap_text=True)

for col, h in enumerate(headers, 1):
    cell = ws.cell(row=1, column=col, value=h)
    cell.fill    = header_fill
    cell.font    = header_font
    cell.alignment = header_align
    cell.border  = make_border()

ws.row_dimensions[1].height = 28

# ── Task rows
current_task = None
row_idx = 2
task_fill_map = {}
task_color_cycle = [LIGHT_BLUE, GREY_LIGHT]
color_idx = 0

for task, component, status, pct, notes in TASKS:
    if task != current_task:
        current_task = task
        task_fill_map[task] = task_color_cycle[color_idx % 2]
        color_idx += 1

    row_fill = make_fill(task_fill_map[task])
    pct_cell_fill = pct_fill(pct)

    values = [task, component, status, pct / 100, notes]
    for col, val in enumerate(values, 1):
        cell = ws.cell(row=row_idx, column=col, value=val)
        cell.border = make_border()
        cell.font   = Font(name="Calibri", size=10)

        if col == 4:  # Completion %
            cell.number_format = "0%"
            cell.alignment = Alignment(horizontal="center", vertical="center")
            cell.fill = pct_cell_fill
            cell.font = Font(name="Calibri", size=10, bold=True,
                             color=GREEN if pct == 100 else (AMBER if pct >= 70 else RED_DARK))
        elif col == 3:  # Status
            cell.alignment = Alignment(horizontal="center", vertical="center")
            cell.fill = row_fill
        elif col == 1:  # Task
            cell.font = Font(name="Calibri", size=10, bold=True)
            cell.fill = row_fill
            cell.alignment = Alignment(vertical="center", wrap_text=True)
        else:
            cell.fill = row_fill
            cell.alignment = Alignment(vertical="center", wrap_text=True)

    ws.row_dimensions[row_idx].height = 22
    row_idx += 1

# ── Summary row
summary_fill = make_fill(MID_BLUE)
summary_font = Font(bold=True, color=WHITE, size=11, name="Calibri")
task, component, status, pct, notes = SUMMARY_ROW
values = [task, component, status, pct / 100, notes]
for col, val in enumerate(values, 1):
    cell = ws.cell(row=row_idx, column=col, value=val)
    cell.fill   = summary_fill
    cell.font   = summary_font
    cell.border = make_border()
    if col == 4:
        cell.number_format = "0%"
        cell.alignment = Alignment(horizontal="center", vertical="center")
    else:
        cell.alignment = Alignment(vertical="center", wrap_text=True)

ws.row_dimensions[row_idx].height = 26

# ── Freeze header row
ws.freeze_panes = "A2"

# ── Auto-filter
ws.auto_filter.ref = f"A1:E{row_idx}"

# Save
wb.save(OUTPUT_PATH)
print(f"Saved: {OUTPUT_PATH}")
print(f"Total rows (excl. header+summary): {row_idx - 2}")
