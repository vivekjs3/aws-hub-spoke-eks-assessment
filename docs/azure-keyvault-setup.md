# Azure Key Vault Secrets Integration Setup Guide

This guide details how to configure **Azure Key Vault (AKV)** and **Azure DevOps (ADO)** to securely retrieve and inject AWS credentials, backend secrets, and EKS configuration at pipeline runtime, removing the need for local or ADO Variable Group secrets storage.

---

## 1. Create Azure Key Vault & Add Secrets

### Step 1: Provision Key Vault in Azure
Create a Key Vault using the Azure CLI or Azure Portal. Ensure that **Azure Role-Based Access Control (Azure RBAC)** or **Access Policies** are configured.
```bash
az keyvault create \
  --name "hubspoke-vault" \
  --resource-group "your-resource-group" \
  --location "ap-southeast-1" \
  --sku "standard"
```

### Step 2: Add Required Secrets to Key Vault
Run the following commands to add all the secrets required by the `terraform-ci-cd` and `app-ci-cd` pipelines. Replace the placeholder values with your actual secrets.

```bash
# AWS Credentials
az keyvault secret set --vault-name "hubspoke-vault" --name "AWS-ACCESS-KEY-ID" --value "AKIAIOSFODNN7EXAMPLE"
az keyvault secret set --vault-name "hubspoke-vault" --name "AWS-SECRET-ACCESS-KEY" --value "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
az keyvault secret set --vault-name "hubspoke-vault" --name "AWS-REGION" --value "ap-southeast-1"

# Terraform Backend Config
az keyvault secret set --vault-name "hubspoke-vault" --name "TF-BACKEND-BUCKET" --value "hubspoke-tfstate-ap-southeast-1"
az keyvault secret set --vault-name "hubspoke-vault" --name "TF-BACKEND-KEY" --value "hub-spoke/terraform.tfstate"
az keyvault secret set --vault-name "hubspoke-vault" --name "TF-BACKEND-REGION" --value "ap-southeast-1"

# EKS & App Deployment Config
az keyvault secret set --vault-name "hubspoke-vault" --name "EKS-CLUSTER-NAME" --value "hubspoke-eks-cluster"
az keyvault secret set --vault-name "hubspoke-vault" --name "APP1-IMAGE-TAG" --value "1.27.0-alpine"
az keyvault secret set --vault-name "hubspoke-vault" --name "APP2-IMAGE-TAG" --value "1.27.0-alpine"
```

*Note: Azure Key Vault secrets must use hyphens (`-`) instead of underscores (`_`) due to character validation constraints.*

---

## 2. Configure Azure DevOps Service Connection

### Step 1: Create an Azure Resource Manager (ARM) Service Connection
1. In Azure DevOps, go to your Project Settings → **Service Connections** → **New Service Connection**.
2. Select **Azure Resource Manager** and click Next.
3. Select **Service Principal (automatic)** or **Service Principal (manual)**.
4. Set the scope to the **Subscription** or **Resource Group** containing your Key Vault.
5. Name the connection (e.g., `Azure-ARM-Service-Connection`). Keep this name ready to populate in ADO variables.

### Step 2: Grant Permissions on Key Vault
The service principal backing the Service Connection needs permission to fetch secrets:

#### Option A: If Key Vault uses Vault Access Policies (Default)
1. Go to the Azure Portal → your Key Vault → **Access Policies** → **Create**.
2. Select **Secret Permissions** → Select **Get** and **List**.
3. Search for and select the **Service Principal** created for the ADO Service Connection.
4. Complete the wizard and click **Save**.

#### Option B: If Key Vault uses Azure RBAC
Assign the **Key Vault Secrets User** role to the Service Principal:
```bash
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee "<Service-Principal-Application-ID>" \
  --scope "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/hubspoke-vault"
```

---

## 3. Create the Variable Group in Azure DevOps

Create a **non-secret** Variable Group in **Pipelines → Library** named `pipeline-config` with these plain text values:

| Name | Value | Description |
|---|---|---|
| `AKV_NAME` | `hubspoke-vault` | The exact name of your Azure Key Vault |
| `AZURE_SERVICE_CONNECTION` | `Azure-ARM-Service-Connection` | The exact name of the Service Connection created in ADO |
| `NAMESPACE` | `default` | Target namespace for Helm microservice deploy |

No AWS credentials or backend keys are stored in ADO library variable groups anymore. They are safely brought in on-demand at runtime.
