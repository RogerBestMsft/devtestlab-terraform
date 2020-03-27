#!/bin/sh

trace() {
    TRACE_DATE=$(date '+%F %T.%N')
    echo ">>> $TRACE_DATE: $@"
}

trace "Deployment Type: $DEPLOYMENT_TYPE"
#trace "Prefix: $STORAGE_PREFIX"
#trace "EnvRG: $EnvironmentResourceGroupName"
trace "Setup folder structure ..."
mkdir /runbooks 
cd ./runbooks

trace "Cleanup runbooks ..."
for file in $(find -type f -name "*\?*"); do mv $file $(echo $file | cut -d? -f1); done

trace "Connecting Azure ..."
while true; do
    # managed identity isn't available directly - retry
    az login --identity -u $EnvironmentUserId 2>/dev/null && {
        export ARM_USE_MSI=true
        export ARM_MSI_ENDPOINT='http://169.254.169.254/metadata/identity/oauth2/token'
        export ARM_SUBSCRIPTION_ID=$(az account show --output=json | jq -r -M '.id')
        export ARM_TENANT_ID=$(az account show --output=json | jq -r -M '.tenantId')
        export TF_LOG=trace
        break
    } || sleep 5    
done

trace "Connecting AZ Copy ..."
azcopy login --identity --identity-resource-id $EnvironmentUserId --tenantId $ARM_TENANT_ID

trace "Set SOURCE_URI"
export SOURCE_URI="https://$AZURE_STORAGE_ACCOUNT.blob.core.windows.net/$AZURE_STORAGE_CONTAINER$STORAGE_PREFIX/*"
trace "SourceURI: $SOURCE_URI"

trace "Copying files locally ..."

azcopy copy "$SOURCE_URI" "/runbooks" --overwrite=prompt --recursive --from-to=BlobLocal --check-md5 "FailIfDifferent" --log-level INFO

sleep 10

#az storage blob download-batch -d '/runbooks' -s $AZURE_STORAGE_CONTAINER --pattern $STORAGE_PREFIX --account-name $AZURE_STORAGE_ACCOUNT --account-key $AZURE_STORAGE_KEY

#sleep 10

#azcopy copy "https://$AZURE_STORAGE_ACCOUNT.blob.core.windows.net$AZURE_STORAGE_CONTAINER$STORAGE_PREFIX/*" "/runbooks" --recursive
#azcopy copy "https://crpstoretcspbmuiw6fc2.blob.core.windows.net/environments-src-files/subscriptions/da8f3095-ac12-4ef2-9b35-fcd24842e207/resourceGroups/testcustomrp-BravoEnv-035234/*" "/runbooks" --recursive

#trace "Wait for Azure deployment ..."
#az group deployment wait --resource-group $EnvironmentResourceGroupName --name $EnvironmentDeploymentName --exists

#trace "Sleeping ..."
#sleep 20
#trace "Client ID: $CLIENT_ID"
#while true: do
#    az role assignment list --assignee 
    #curl -H Metadata:true "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fmanagement.azure.com/&client_id=$CLIENT_ID" 2>/dev/null && {
    #    trace "in loop ******************"
#    } || sleep 5
#done    
#az role assignment list --all --assignee $EnvironmentUserId

trace "Initializing Terraform ..."
terraform init -backend-config state.tf -reconfigure

#export DEPLOY_CREATE="create"
trace "Before apply or destroy: $DEPLOYMENT_TYPE "
trace "Checking to apply or destroy ..."
#if [ $DEPLOYMENT_TYPE == "delete" ]; then
if [ -z "$DEPLOYMENT_TYPE" ]; then
    trace "Deleting Terraform ..."
    terraform destroy -auto-approve -var "EnvironmentResourceGroupName=$EnvironmentResourceGroupName"
    az storage blob delete-batch -s $AZURE_STORAGE_CONTAINER --pattern $STORAGE_PREFIX --account-name $AZURE_STORAGE_ACCOUNT
else
    trace "Applying Terraform ..."
    terraform apply -auto-approve -var "EnvironmentResourceGroupName=$EnvironmentResourceGroupName"
fi

if [ -z "$ContainerGroupId" ]; then
    trace "Completed ..."
else
    trace "Deleting container groups ..."
    az container delete --yes --ids $ContainerGroupId
fi
trace "Set the readiness probe file ..."
echo 'Completed' > ready.txt