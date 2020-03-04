#!/bin/sh

trace() {
    TRACE_DATE=$(date '+%F %T.%N')
    echo ">>> $TRACE_DATE: $@"
}

export STORAGE_PREFIX=$1

trace "Setup folder structure ..."
mkdir /runbooks 
cd /runbooks

trace "Cleanup runbooks ..."
for file in $(find -type f -name "*\?*"); do mv $file $(echo $file | cut -d? -f1); done

trace "Connecting Azure ..."
while true; do
    # managed identity isn't avaialble directly - retry
    az login --identity 2>/dev/null && {
        export ARM_USE_MSI=true
        export ARM_MSI_ENDPOINT='http://169.254.169.254/metadata/identity/oauth2/token'
        export ARM_SUBSCRIPTION_ID=$(az account show --output=json | jq -r -M '.id')
        export ARM_TENANT_ID=$(az account show --output=json | jq -r -M '.tenantId')
        export TF_LOG=trace
        break
    } || sleep 5    
done

trace "Connecting AZ Copy ..."
azcopy login --identity --identity-resource-id $EnvironmentUserId

trace export
trace "https://$AZURE_STORAGE_ACCOUNT.blob.core.windows.net/$ARM_STORAGE_CONTAINER$STORAGE_PREFIX/*"

trace "Copying files locally ..."
azcopy copy "https://$AZURE_STORAGE_ACCOUNT.blob.core.windows.net/$ARM_STORAGE_CONTAINER$STORAGE_PREFIX/*" "*" --recursive

trace "Wait for Azure deployment ..."
az group deployment wait --resource-group $EnvironmentResourceGroupName --name $EnvironmentDeploymentName --created

trace "Initializing Terraform ..."
terraform init -backend-config state.tf -reconfigure

trace "Applying Terraform ..."
terraform apply -auto-approve -var "EnvironmentResourceGroupName=$EnvironmentResourceGroupName"

if [ -z "$ContainerGroupId" ]; then
    trace "Completed ..."
    #tail -f /dev/null
else
    trace "Deleting container groups ..."
    az container delete --yes --ids $ContainerGroupId
fi
trace "Set the readiness probe file ..."
touch /tmp/ready