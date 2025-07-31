#!/bin/bash

# Deploy Azure Services for Dapr Components
# This script deploys Azure Service Bus and Cosmos DB, then updates Kubernetes secrets

set -e

# Check if required tools are installed
if ! command -v az &> /dev/null; then
    echo "❌ Azure CLI is not installed. Please install it first."
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed. Please install it first."
    exit 1
fi

# Variables
RESOURCE_GROUP_NAME="${AZURE_RESOURCE_GROUP:-aks-store-dapr-rg}"
LOCATION="${AZURE_LOCATION:-eastus}"
ENV_NAME="${AZURE_ENV_NAME:-dev}"
SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}"

echo "🚀 Deploying Azure Services for Dapr Components..."
echo "Resource Group: $RESOURCE_GROUP_NAME"
echo "Location: $LOCATION"
echo "Environment: $ENV_NAME"

# Check if logged in to Azure
if ! az account show &> /dev/null; then
    echo "❌ Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

# Set subscription if provided
if [ -n "$SUBSCRIPTION_ID" ]; then
    echo "Setting subscription to $SUBSCRIPTION_ID"
    az account set --subscription "$SUBSCRIPTION_ID"
fi

# Create resource group if it doesn't exist
echo "📦 Creating resource group..."
az group create --name "$RESOURCE_GROUP_NAME" --location "$LOCATION" --tags "azd-env-name=$ENV_NAME"

# Deploy the Bicep template
echo "🔧 Deploying Azure services..."
DEPLOYMENT_OUTPUT=$(az deployment group create \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --template-file "infra/bicep/dapr-azure-services.bicep" \
    --parameters "location=$LOCATION" "environmentName=$ENV_NAME" \
    --query 'properties.outputs' \
    --output json)

# Extract outputs
SERVICE_BUS_CONNECTION_STRING=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.serviceBusConnectionString.value')
COSMOS_ENDPOINT=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.cosmosEndpoint.value')
COSMOS_PRIMARY_KEY=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.cosmosPrimaryKey.value')

echo "✅ Azure services deployed successfully!"
echo "Service Bus Connection String: ${SERVICE_BUS_CONNECTION_STRING:0:50}..."
echo "Cosmos DB Endpoint: $COSMOS_ENDPOINT"

# Update Kubernetes secrets
echo "🔐 Updating Kubernetes secrets..."

# Encode connection strings to base64
SERVICE_BUS_CONNECTION_B64=$(echo -n "$SERVICE_BUS_CONNECTION_STRING" | base64)
COSMOS_KEY_B64=$(echo -n "$COSMOS_PRIMARY_KEY" | base64)

# Update the dapr-components-azure.yaml file with actual values
sed -i.bak "s|connectionstring: .*|connectionstring: $SERVICE_BUS_CONNECTION_B64|g" dapr-components-azure.yaml
sed -i.bak "s|masterkey: .*|masterkey: $COSMOS_KEY_B64|g" dapr-components-azure.yaml
sed -i.bak "s|https://your-cosmosdb-account.documents.azure.com:443/|$COSMOS_ENDPOINT|g" dapr-components-azure.yaml

echo "✅ Updated dapr-components-azure.yaml with actual connection strings"

# Apply the Dapr components to Kubernetes
echo "🎯 Applying Dapr components to Kubernetes..."
kubectl apply -f dapr-components-azure.yaml

echo "🎉 Deployment complete!"
echo ""
echo "Next steps:"
echo "1. Update your application deployment to use the Azure Dapr components:"
echo "   kubectl apply -f aks-store-all-in-one-dapr-custom.yaml"
echo ""
echo "2. Verify the components are loaded:"
echo "   kubectl get components"
echo ""
echo "3. Check Dapr sidecar logs for any issues:"
echo "   kubectl logs -l app=order-service -c daprd"
echo "   kubectl logs -l app=makeline-service -c daprd"
echo ""
echo "Services created:"
echo "- Service Bus Namespace: $(echo "$DEPLOYMENT_OUTPUT" | jq -r '.serviceBusNamespace.value')"
echo "- Cosmos DB Account: $(echo "$DEPLOYMENT_OUTPUT" | jq -r '.cosmosAccountName.value')"
