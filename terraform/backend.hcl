################################################################################
# backend.hcl — Backend config override for CI / local use
#
# Usage:
#   terraform init -backend-config=backend.hcl
#
# This file keeps sensitive backend coordinates OUT of main.tf so the bucket
# name and region can differ per environment without changing source code.
# Add this file to .gitignore if it contains environment-specific values,
# OR commit a templated version and override in CI via pipeline variables.
################################################################################

bucket         = "hubspoke-tfstate-ap-southeast-1"
key            = "hub-spoke/terraform.tfstate"
region         = "ap-southeast-1"
encrypt        = true
dynamodb_table = "hubspoke-tfstate-lock"
