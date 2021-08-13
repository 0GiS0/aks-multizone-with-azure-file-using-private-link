#Variables
RESOURCE_GROUP="AKS-DynamicStorage"
AKS_NAME="aks-dynamicstore"
LOCATION="northeurope"

#Create Resource Group
az group create --name $RESOURCE_GROUP --location $LOCATION

#Create AKS cluster
az aks create \
    --resource-group $RESOURCE_GROUP \
    --name $AKS_NAME \
    --generate-ssh-keys \
    --node-count 3 \
    --zones 1 2 3

#Get AKS node resource group name
AKS_RESOURCE_GROUP=$(az aks show --resource-group $RESOURCE_GROUP --name $AKS_NAME --query nodeResourceGroup --output tsv)

#Get AKS node resource group id
AKS_RESOURCE_GROUP_ID=$(az group show --name $AKS_RESOURCE_GROUP --query id --output tsv)

#Get Managed identity id
MANAGED_IDENTITY_ID=$(az aks show --name ${AKS_NAME} -g $RESOURCE_GROUP --query identityProfile.kubeletidentity.clientId --output tsv)

# Give Contributor permissions to the managed identity of the cluster
az role assignment create --assignee $MANAGED_IDENTITY_ID --role contributor --scope $AKS_RESOURCE_GROUP_ID
    
# Get AKS credentials
az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_NAME

#See the zone for the nodes
kubectl get nodes -o custom-columns=NAME:'{.metadata.name}',REGION:'{.metadata.labels.topology\.kubernetes\.io/region}',ZONE:'{metadata.labels.topology\.kubernetes\.io/zone}'

# Install CSI Driver
curl -skSL https://raw.githubusercontent.com/kubernetes-sigs/azurefile-csi-driver/v1.5.0/deploy/install-driver.sh | bash -s v1.5.0 --
k get pod -A

### Preview ####
az aks create \
    --resource-group $RESOURCE_GROUP \
    --name $AKS_NAME \
    --generate-ssh-keys \
    --node-count 3 \
    --zones 1 2 3 \
    --aks-custom-headers EnableAzureDiskFileCSIDriver=true

# Create Apache Web server using Azure Files
kubectl apply -f k8s/.
k get pod -o wide
k get pv,pvc
k get svc

#Get azure storage account key 
STORAGE_KEY=$(az storage account keys list -g $RESOURCE_GROUP -n $PRIVATE_STORAGE_ACCOUNT --query '[0].value' -o tsv)

# Upload file to azure files share
az storage file upload --source apache-content/index.php \
--account-name $PRIVATE_STORAGE_ACCOUNT \
--account-key $STORAGE_KEY \
--share-name <NAME_OF_THE_SHARE_FILE>