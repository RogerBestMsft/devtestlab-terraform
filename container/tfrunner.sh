#!/bin/sh

trace() {
    TRACE_DATE=$(date '+%F %T.%N')
    echo ">>> $TRACE_DATE: $@"
}

export STORAGE_PREFIX=$1
export APPLY_DEPLOYMENT=true
trace "Setup folder structure ..."
mkdir /runbooks 
cd /runbooks

trace "Cleanup runbooks ..."
for file in $(find -type f -name "*\?*"); do mv $file $(echo $file | cut -d? -f1); done

trace "Connecting Azure ..."
while true; do
    # managed identity isn't avaialble directly - retry
    az login --identity -u $EnvironmentUserId 2>/dev/null && {
        export ARM_USE_MSI=true
        export ARM_MSI_ENDPOINT='http://169.254.169.254/metadata/identity/oauth2/token'
        export ARM_SUBSCRIPTION_ID=$(az account show --output=json | jq -r -M '.id')
        export ARM_TENANT_ID=$(az account show --output=json | jq -r -M '.tenantId')
        export TF_LOG=trace
        break
    } || sleep 5    
done

trace $EnvironmentUserId

trace "Connecting AZ Copy ..."
azcopy login --identity --identity-resource-id $EnvironmentUserId --tenant-id=$ARM_TENANT_ID

trace "$AZURE_STORAGE_ACCOUNT"
trace "$AZURE_STORAGE_CONTAINER"
trace "$STORAGE_PREFIX"
trace "https://$AZURE_STORAGE_ACCOUNT.blob.core.windows.net/$AZURE_STORAGE_CONTAINER$STORAGE_PREFIX/*"

trace "Copying files locally ..."
azcopy copy "https://$AZURE_STORAGE_ACCOUNT.blob.core.windows.net$AZURE_STORAGE_CONTAINER$STORAGE_PREFIX/*" "." --recursive

trace "SAS Copying files locally ..."
azcopy copy "https://$AZURE_STORAGE_ACCOUNT.blob.core.windows.net$AZURE_STORAGE_CONTAINER$STORAGE_PREFIX/*?sv=2019-02-02&ss=bfqt&srt=sco&sp=rwdlacup&se=2020-03-07T02:53:09Z&st=2020-03-06T18:53:09Z&spr=https&sig=H3zNbtn7wWfh%2B%2BWuXoLpp9z7MkAn%2FU7zd%2F85NQixsX4%3D" "." --recursive

trace "Wait for Azure deployment ..."
az group deployment wait --resource-group $EnvironmentResourceGroupName --name $EnvironmentDeploymentName --created

trace "Initializing Terraform ..."
terraform init -backend-config state.tf -reconfigure

trace "Checking to apply or destroy ..."
if [$APPLY_DEPLOYMENT]; then
    trace "Applying Terraform ..."
    terraform apply -auto-approve -var "EnvironmentResourceGroupName=$EnvironmentResourceGroupName"
else
    trace "Deleting Terraform ..."
    terraform destroy -auto-approve -var "EnvironmentResourceGroupName=$EnvironmentResourceGroupName"
fi

if [ -z "$ContainerGroupId" ]; then
    trace "Completed ..."
    #tail -f /dev/null
else
    trace "Deleting container groups ..."
    az container delete --yes --ids $ContainerGroupId
fi
trace "Set the readiness probe file ..."
touch /tmp/ready