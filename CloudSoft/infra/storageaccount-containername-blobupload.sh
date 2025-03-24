#!/bin/bash

# 1. Variabler
RESOURCE_GROUP="SecureInfraRG"
LOCATION="northeurope"
STORAGE_ACCOUNT_NAME="securestorage$(date +%s)"  # Unikt namn för Storage Account
CONTAINER_NAME="securecontainer$(date +%s)"  # Unikt namn för Container
STORAGE_SKU="Standard_LRS"
BLOB_NAME="hero.jpg"
LOCAL_FILE_PATH="C:/Users/hugoh/Desktop/storageaccount-containername-blobupload/$BLOB_NAME"

# 2. Skapa Storage Account med anonym åtkomst aktiverad
echo "Skapar Storage Account '$STORAGE_ACCOUNT_NAME'..."
az storage account create \
    --name $STORAGE_ACCOUNT_NAME \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --sku $STORAGE_SKU \
    --kind StorageV2 \
    --allow-blob-public-access true

echo "✅ Storage Account '$STORAGE_ACCOUNT_NAME' skapades framgångsrikt."

# 3. Säkerställ att nätverksåtkomst är öppen för alla nätverk
echo "Ställer in nätverksåtkomst till 'Enable public access from all networks'..."
az storage account update \
    --name $STORAGE_ACCOUNT_NAME \
    --resource-group $RESOURCE_GROUP \
    --default-action Allow

# 4. Hämta Storage Account Key
echo "Hämtar Storage Account Key..."
STORAGE_KEY=$(az storage account keys list \
    --resource-group $RESOURCE_GROUP \
    --account-name $STORAGE_ACCOUNT_NAME \
    --query "[0].value" \
    --output tsv)

# 5. Skapa en container med anonym åtkomst för blobar
echo "Skapar container '$CONTAINER_NAME'..."
az storage container create \
    --name $CONTAINER_NAME \
    --account-name $STORAGE_ACCOUNT_NAME \
    --account-key $STORAGE_KEY \
    --public-access blob

echo "✅ Container '$CONTAINER_NAME' skapades framgångsrikt med anonym åtkomst för blobs!"

# 6. Ladda upp blob (bildfilen)
echo "Laddar upp bilden '$BLOB_NAME' till containern '$CONTAINER_NAME'..."
az storage blob upload \
    --account-name $STORAGE_ACCOUNT_NAME \
    --container-name $CONTAINER_NAME \
    --name $BLOB_NAME \
    --file "$LOCAL_FILE_PATH" \
    --auth-mode key \
    --tier Hot

echo "✅ Bilden '$BLOB_NAME' laddades upp framgångsrikt!"

# 7. Verifiera inställningarna
echo "Verifierar inställningar..."

# Kontrollera anonym åtkomst
ACCESS_SETTING=$(az storage account show \
    --name $STORAGE_ACCOUNT_NAME \
    --resource-group $RESOURCE_GROUP \
    --query "allowBlobPublicAccess" \
    --output tsv)

if [ "$ACCESS_SETTING" == "true" ]; then
    echo "✅ Anonym åtkomst kan aktiveras på containernivå!"
else
    echo "❌ Något gick fel, anonym åtkomst är inte aktiverad."
fi

# Kontrollera nätverksåtkomst
NETWORK_ACCESS=$(az storage account show \
    --name $STORAGE_ACCOUNT_NAME \
    --resource-group $RESOURCE_GROUP \
    --query "networkRuleSet.defaultAction" \
    --output tsv)

if [ "$NETWORK_ACCESS" == "Allow" ]; then
    echo "✅ Nätverksåtkomst är satt till 'Enable public access from all networks'."
else
    echo "❌ Något gick fel, nätverksåtkomst är inte korrekt inställd."
fi

echo "🎉 Deployment färdig! Storage Account: $STORAGE_ACCOUNT_NAME, Container: $CONTAINER_NAME, Blob: $BLOB_NAME"