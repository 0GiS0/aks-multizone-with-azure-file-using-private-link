#Variables
RESOURCE_GROUP="aks-multi-zones"
AKS_NAME="ha-aks"
LOCATION="northeurope"
VNET="aks-vnet"
SUBNET_AKS="aks-subnet"
SUBNET_ENDPOINTS="endpoints"
PRIVATE_DNS_ZONE="private.file.core.windows.net"

#Create Resource Group
az group create --name $RESOURCE_GROUP --location $LOCATION

#Create a VNET
az network vnet create --resource-group $RESOURCE_GROUP \
--name $VNET --address-prefixes 192.168.0.0/16 \
--subnet-name $SUBNET_AKS \
--subnet-prefixes 192.168.1.0/24

VNET_ID=$(az network vnet show --name $VNET --resource-group $RESOURCE_GROUP --query "id" --output tsv)
SUBNET_AKS_ID=$(az network vnet subnet show --name $SUBNET_AKS --resource-group $RESOURCE_GROUP --vnet-name $VNET --query "id" --output tsv)

#Create a subnet for the endpoints
az network vnet subnet create --resource-group $RESOURCE_GROUP \
--vnet-name $VNET --name $SUBNET_ENDPOINTS --address-prefixes 192.168.2.0/24 \
--disable-private-endpoint-network-policies true

#Create a private DNS zone
az network private-dns zone create --resource-group $RESOURCE_GROUP \
--name $PRIVATE_DNS_ZONE

#Create an association between the VNET and the private DNS zone
az network private-dns link vnet create \
--name "link_between_dns_and_vnet" \
--resource-group $RESOURCE_GROUP \
--zone-name $PRIVATE_DNS_ZONE \
--virtual-network $VNET \
--registration-enabled false

# Create an Azure Storage only accesible via private link
# So you need:
# 1. Create a storage account
PRIVATE_STORAGE_ACCOUNT="webapache"
az storage account create -g $RESOURCE_GROUP \
--name $PRIVATE_STORAGE_ACCOUNT \
--sku Standard_ZRS \
--default-action Deny

STORAGE_ACCOUNT_ID=$(az storage account show --name $PRIVATE_STORAGE_ACCOUNT --resource-group $RESOURCE_GROUP --query "id" --output tsv)

# 1. Create a private endpoint for the storage account
az network private-endpoint create --resource-group $RESOURCE_GROUP \
--name $PRIVATE_STORAGE_ACCOUNT \
--vnet-name $VNET \
--subnet $SUBNET_ENDPOINTS \
--location $LOCATION \
--connection-name $PRIVATE_STORAGE_ACCOUNT \
--group-id file \
--private-connection-resource-id $STORAGE_ACCOUNT_ID 

#Get the ID of the azure storage NIC
STORAGE_NIC_ID=$(az network private-endpoint show --name $PRIVATE_STORAGE_ACCOUNT -g $RESOURCE_GROUP --query 'networkInterfaces[0].id' -o tsv)

#Get the IP of the azure storage NIC
STORAGE_ACCOUNT_PRIVATE_IP=$(az resource show --ids $STORAGE_NIC_ID --query 'properties.ipConfigurations[0].properties.privateIPAddress' --output tsv)

#Setup DNS with the new private endpoint
# The record set name to the private IP of the storage account
RECORD_SET_NAME="web-apache-storage"
az network private-dns record-set a add-record \
--record-set-name $RECORD_SET_NAME \
--resource-group $RESOURCE_GROUP \
--zone-name $PRIVATE_DNS_ZONE \
--ipv4-address $STORAGE_ACCOUNT_PRIVATE_IP


#Create a Service Principal
az ad sp create-for-rbac -n $AKS_NAME --role Contributor \
--scopes $STORAGE_ACCOUNT_ID $VNET_ID > auth.json

appId=$(jq -r ".appId" auth.json)
password=$(jq -r ".password" auth.json)

#Create AKS cluster
az aks create \
    --resource-group $RESOURCE_GROUP \
    --name $AKS_NAME \
    --generate-ssh-keys \
    --load-balancer-sku standard \
    --node-count 3 \
    --zones 1 2 3 \
    --vnet-subnet-id $SUBNET_AKS_ID \
    --service-principal $appId \
    --client-secret $password
    

# Get AKS credentials
az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_NAME

#See the zone for the nodes
kubectl get nodes -o custom-columns=NAME:'{.metadata.name}',REGION:'{.metadata.labels.topology\.kubernetes\.io/region}',ZONE:'{metadata.labels.topology\.kubernetes\.io/zone}'

# Install CSI Driver for Azure Files
curl -skSL https://raw.githubusercontent.com/kubernetes-sigs/azurefile-csi-driver/v1.5.0/deploy/install-driver.sh | bash -s v1.5.0 --

# Create Apache Web server using Azure Files
kubectl apply -f k8s/.
k get pod -o wide
k get pvc
k get svc

#Get azure storage account key 
STORAGE_KEY=$(az storage account keys list -g $RESOURCE_GROUP -n $PRIVATE_STORAGE_ACCOUNT --query '[0].value' -o tsv)

# Upload file to azure files share
az storage file upload --source apache-content/index.php \
--account-name $PRIVATE_STORAGE_ACCOUNT \
--account-key $STORAGE_KEY \
--share-name content
