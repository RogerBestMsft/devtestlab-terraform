#!/bin/sh

trace() {
    TRACE_DATE=$(date '+%F %T.%N')
    echo ">>> $TRACE_DATE: $@"
}

trace "Setup folder structure ..."
mkdir /runbooks 
cd /runbooks

//trace "Downloading runbooks ..."
#for url in $*; do wget ${url}; done


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

export ARM_STORAGE_CONTAINER='https://crpstoretcspbmuiw6fc2.blob.core.windows.net/environments-src-files/'


trace "Downloading storage files"
az storage blob download -s $ARM_STORAGE_CONTAINER -d ./local --pattern /subscriptions/da8f3095-ac12-4ef2-9b35-fcd24842e207/resourceGroups/testcustomrp-EchoEnv-669175/*.*

trace "Wait for Azure deployment ..."
az group deployment wait --resource-group $EnvironmentResourceGroupName --name $EnvironmentDeploymentName --created

trace "Initializing Terraform ..."
terraform init -backend-config state.tf -reconfigure

trace "Applying Terraform ..."
terraform apply -auto-approve -var "EnvironmentResourceGroupName=$EnvironmentResourceGroupName"

if [ -z "$ContainerGroupId" ]; then
    trace "Waiting for termination ..."
    tail -f /dev/null
else
    trace "Deleting container groups ..."
    az container delete --yes --ids $ContainerGroupId
fi
