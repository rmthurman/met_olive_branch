#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 -resource <Resource name> -location <Region> -apikey <API_KEY> -apiurl <API_BASE_URL> -acrname <ACR_NAME> -laname <LA_NAME>"
    exit 1
}

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -resource) RESOURCE_NAME="$2"; shift ;;
        -location) REGION="$2"; shift ;;
        -apikey) API_KEY="$2"; shift ;;
        -apiurl) API_URL="$2"; shift ;;
        -acrname) ACR_NAME="$2"; shift ;;
        -laname) LA_NAME="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; usage ;;
    esac
    shift
done

# Check if all required arguments are provided
if [ -z "$RESOURCE_NAME" ] || [ -z "$REGION" ] || [ -z "$API_KEY" ] || [ -z "$API_URL" ] || [ -z "$ACR_NAME" ] || [ -z "$LA_NAME" ]; then
    usage
fi

# Build the Docker image
docker build -f ./frontend/Dockerfile -t frontnl2sql ./frontend

# Create an azure container registry
#ACR_NAME="crnl2sql"  #RT:  hardcoded is a bad approach

#if it already exists, in any resource group, dont create it
if az acr show --name $ACR_NAME &> /dev/null; then
    echo "Azure Container Registry $ACR_NAME already exists."
else
    echo "Creating Azure Container Registry $ACR_NAME..."
    az acr create --resource-group $RESOURCE_NAME --name $ACR_NAME --sku Basic --location $REGION --admin-enabled true
fi

# Get the Azure Container Registry name from the resource group
az acr login --name $ACR_NAME 

# Tag the Docker image
docker tag frontnl2sql:latest $ACR_NAME.azurecr.io/insight_engine/frontnl2sql:latest

# Push the Docker image to the Azure Container Registry
docker push $ACR_NAME.azurecr.io/insight_engine/frontnl2sql:latest

# Get ACR credentials
az acr update -n $ACR_NAME --admin-enabled true 2> /dev/null
ACR_USERNAME=$(az acr credential show --name $ACR_NAME --query "username" --output tsv 2> /dev/null)
ACR_PASSWORD=$(az acr credential show --name $ACR_NAME --query "passwords[0].value" --output tsv 2> /dev/null)
ACR_LOCATION=$(az acr show --name $ACR_NAME --query "location" --output tsv 2> /dev/null)

az resource update --resource-group $ --name $LA_NAME--resource-type Microsoft.OperationalInsights/workspaces --set properties.features.enableLogAccessUsingOnlyResourcePermissions=false

# Deploy the container to Azure Container App Service
env_name=cae-frontnl2sql
app_name=ca-frontnl2sql

# Assumes existing LA workspace
LA_ID=$(az monitor log-analytics workspace show --resource-group $RESOURCE_NAME --workspace-name $LA_NAME --query "customerId" --output tsv 2> /dev/null)
if [ -z "$LA_ID" ]; then
    echo "Log Analytics workspace $LA_NAME not found."
    exit 1
fi
#do not output to console, use dev/null
#LA_KEY=$(az monitor log-analytics workspace get-shared-keys --resource-group $RESOURCE_NAME --workspace-name $LA_NAME --query "primarySharedKey" --output tsv 2> /dev/null)

if [ -z "$LA_KEY" ]; then
    echo "Failed to get Log Analytics workspace key."
    exit 1
fi

printf "Log Analytics ID: %b\n" "$LA_ID"
printf "Log Analytics Key: %b\n" "$LA_KEY"

if [ -z "$LA_ID" ] || [ -z "$LA_KEY" ]; then
    echo "Creating Container App env with new Log Analytics resource."
    az containerapp env create \
    --name $env_name \
    --resource-group $RESOURCE_NAME \
    --location $REGION 
else
    echo "Creating Container App env with existing Log Analytics resource: $LA_NAME"
    az containerapp env create \
    --name $env_name \
    --resource-group $RESOURCE_NAME \
    --location $REGION \
    --logs-destination log-analytics \
    --logs-workspace-id $LA_ID \
    --logs-workspace-key $LA_KEY 
fi

az containerapp create \
    --resource-group $RESOURCE_NAME \
    --name $app_name \
    --image $ACR_NAME.azurecr.io/insight_engine/frontnl2sql:latest \
    --cpu 3 \
    --memory 6 \
    --registry-server $ACR_NAME.azurecr.io \
    --registry-username $ACR_USERNAME \
    --registry-password $ACR_PASSWORD \
    --environment $env_name \
    --ingress external \
    --target-port 8501 \
    --env-vars API_URL=$API_URL API_KEY=$API_KEY \
    --secrets 'rathurazurecrio-rathur'=$ACR_PASSWORD \