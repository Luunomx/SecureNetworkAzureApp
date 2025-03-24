#!/bin/bash
set -e  # Avbryter skriptet vid fel

################################################################################
# Om du kör i Git Bash på Windows, förhindra path-konvertering:
# export MSYS_NO_PATHCONV=1
################################################################################

# ==============================
# 🔹 Variabler
# ==============================
RESOURCE_GROUP="SecureInfraRG"
LOCATION="northeurope"
COSMOS_DB_NAME="securecosmosdb$RANDOM"  # Slumpmässigt suffix
VNET_NAME="SecureVNet"
SUBNET_NAME="AppSubnet"
PRIVATE_ENDPOINT_NAME="${COSMOS_DB_NAME}-pe"
PRIVATE_DNS_ZONE="privatelink.mongo.cosmos.azure.com"

# Hämta prenumerations-ID
SUBSCRIPTION_ID=$(az account show --query "id" -o tsv)
if [[ -z "$SUBSCRIPTION_ID" ]]; then
  echo "❌ Du verkar inte vara inloggad. Kör 'az login' först!"
  exit 1
fi
echo "✅ Använder prenumeration: $SUBSCRIPTION_ID"

# ==============================
# 🔹 1. Skapa Cosmos DB med public access avstängd
# ==============================
echo "🚀 Skapar Cosmos DB: $COSMOS_DB_NAME..."
az cosmosdb create \
  --name "$COSMOS_DB_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --kind MongoDB \
  --server-version 4.0 \
  --locations regionName="$LOCATION" failoverPriority=0 \
  --default-consistency-level "Session" \
  --enable-multiple-write-locations false \
  --public-network-access "Disabled"

# ==============================
# 🔹 2. Hämta Cosmos DB ID
# ==============================
COSMOS_DB_ID=$(az cosmosdb show --name "$COSMOS_DB_NAME" --resource-group "$RESOURCE_GROUP" --query "id" -o tsv)
if [[ -z "$COSMOS_DB_ID" ]]; then
  echo "❌ ERROR: Cosmos DB kunde inte skapas eller hittas."
  exit 1
fi
echo "✅ Cosmos DB ID: $COSMOS_DB_ID"

# ==============================
# 🔹 3. Aktivera Virtual Network Filtering
# ==============================
echo "🔄 Aktiverar Virtual Network Filtering på Cosmos DB..."
az cosmosdb update \
  --name "$COSMOS_DB_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --enable-virtual-network true
echo "✅ Virtual Network Filtering aktiverat!"

# ==============================
# 🔹 4. Hämta Subnet ID
# ==============================
SUBNET_ID=$(az network vnet subnet show --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "$SUBNET_NAME" --query "id" -o tsv)
if [[ -z "$SUBNET_ID" ]]; then
  echo "❌ ERROR: Kunde inte hitta subnet $SUBNET_NAME i $VNET_NAME"
  exit 1
fi
echo "✅ Subnet ID: $SUBNET_ID"

# ==============================
# 🔹 5. Lägg till Subnet i Cosmos DB nätverksregler
# ==============================
echo "🔄 Lägger till Subnet i Cosmos DB nätverksregler..."
az cosmosdb network-rule add \
  --name "$COSMOS_DB_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --subnet "$SUBNET_NAME" \
  --vnet-name "$VNET_NAME"
echo "✅ Nätverksregel lagts till!"

# ==============================
# 🔹 6. Bygg Private Endpoint Resource ID manuellt
# ==============================
PRIVATE_CONNECTION_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DocumentDB/databaseAccounts/$COSMOS_DB_NAME"

# ==============================
# 🔹 7. Skapa Private Endpoint om den inte redan finns
# ==============================
PE_EXISTING=$(az network private-endpoint show --name "$PRIVATE_ENDPOINT_NAME" --resource-group "$RESOURCE_GROUP" --query "name" -o tsv 2>/dev/null || true)
if [[ -n "$PE_EXISTING" ]]; then
  echo "🔹 Private Endpoint $PRIVATE_ENDPOINT_NAME finns redan, hoppar över skapandet."
else
  echo "🚀 Skapar Private Endpoint: $PRIVATE_ENDPOINT_NAME..."
  az network private-endpoint create \
    --name "$PRIVATE_ENDPOINT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --vnet-name "$VNET_NAME" \
    --subnet "$SUBNET_NAME" \
    --private-connection-resource-id "$PRIVATE_CONNECTION_ID" \
    --group-ids "MongoDB" \
    --connection-name "${COSMOS_DB_NAME}-conn"
fi

# ==============================
# 🔹 8. Skapa Private DNS-zon om den inte redan finns
# ==============================
echo "🔄 Kontrollerar om Private DNS-zon finns..."
EXISTING_DNS_ZONE=$(az network private-dns zone list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[?name=='$PRIVATE_DNS_ZONE'].name" -o tsv)
if [[ -z "$EXISTING_DNS_ZONE" ]]; then
  echo "🚀 Skapar Private DNS-zon: $PRIVATE_DNS_ZONE..."
  az network private-dns zone create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$PRIVATE_DNS_ZONE"
else
  echo "🔹 Private DNS-zon $PRIVATE_DNS_ZONE finns redan, hoppar över skapandet."
fi

# ==============================
# 🔹 9. Länka DNS-zonen till VNet om länken inte redan finns
# ==============================
DNS_LINK_EXISTS=$(az network private-dns link vnet list \
  --resource-group "$RESOURCE_GROUP" \
  --zone-name "$PRIVATE_DNS_ZONE" \
  --query "[?name=='${VNET_NAME}-dns-link']" -o tsv)
if [[ -z "$DNS_LINK_EXISTS" ]]; then
  echo "🔄 Länkar Private DNS-zon till VNet..."
  az network private-dns link vnet create \
    --resource-group "$RESOURCE_GROUP" \
    --zone-name "$PRIVATE_DNS_ZONE" \
    --name "${VNET_NAME}-dns-link" \
    --virtual-network "$VNET_NAME" \
    --registration-enabled false
  echo "✅ DNS-zon kopplad!"
else
  echo "🔹 DNS-länk finns redan, hoppar över skapandet."
fi

# ==============================
# 🔹 10. Vänta på att Private Endpoint är "Succeeded" och skapa DNS-poster
# ==============================
echo "Väntar på att Private Endpoint provisioningState blir 'Succeeded'..."
PE_STATE=""
while [ "$PE_STATE" != "Succeeded" ]; do
    sleep 5
    PE_STATE=$(az network private-endpoint show \
      --name "$PRIVATE_ENDPOINT_NAME" \
      --resource-group "$RESOURCE_GROUP" \
      --query "provisioningState" -o tsv)
done
echo "✅ Private Endpoint provisioningState är nu 'Succeeded'!"

# Hämta IP för huvuddomänen (customDnsConfigs[0])
PRIVATE_IP=$(az network private-endpoint show \
  --name "$PRIVATE_ENDPOINT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "customDnsConfigs[0].ipAddresses[0]" -o tsv)
echo "✅ Private Endpoint IP (huvuddomän): $PRIVATE_IP"

# Skapa DNS-post för huvuddomänen (ex: securecosmosdb9871)
echo "🔄 Skapar DNS-post för huvuddomänen..."
EXISTING_DNS_RECORD=$(az network private-dns record-set a list \
  --resource-group "$RESOURCE_GROUP" \
  --zone-name "$PRIVATE_DNS_ZONE" \
  --query "[?name=='$COSMOS_DB_NAME']" -o tsv)

if [[ -z "$EXISTING_DNS_RECORD" ]]; then
  az network private-dns record-set a add-record \
    --resource-group "$RESOURCE_GROUP" \
    --zone-name "$PRIVATE_DNS_ZONE" \
    --record-set-name "$COSMOS_DB_NAME" \
    --ipv4-address "$PRIVATE_IP"
  echo "✅ DNS-post skapad för huvuddomänen ($COSMOS_DB_NAME)!"
else
  echo "🔹 DNS-post för $COSMOS_DB_NAME finns redan, hoppar över skapandet."
fi

# ==============================
# 🔹 10b. Skapa DNS-post för region-specifik subdomän (ex: securecosmosdb9871-northeurope)
# ==============================
REGIONAL_PRIVATE_IP=$(az network private-endpoint show \
  --name "$PRIVATE_ENDPOINT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "customDnsConfigs[1].ipAddresses[0]" -o tsv)

if [[ -n "$REGIONAL_PRIVATE_IP" ]]; then
  # Bygg subdomännamnet (ex: "securecosmosdb9871-northeurope")
  REGIONAL_DB_NAME="${COSMOS_DB_NAME}-northeurope"
  echo "✅ Private Endpoint IP (region-specifik): $REGIONAL_PRIVATE_IP"

  echo "🔄 Skapar DNS-post för region-specifik subdomän..."
  EXISTING_REGIONAL_DNS_RECORD=$(az network private-dns record-set a list \
    --resource-group "$RESOURCE_GROUP" \
    --zone-name "$PRIVATE_DNS_ZONE" \
    --query "[?name=='$REGIONAL_DB_NAME']" -o tsv)

  if [[ -z "$EXISTING_REGIONAL_DNS_RECORD" ]]; then
    az network private-dns record-set a add-record \
      --resource-group "$RESOURCE_GROUP" \
      --zone-name "$PRIVATE_DNS_ZONE" \
      --record-set-name "$REGIONAL_DB_NAME" \
      --ipv4-address "$REGIONAL_PRIVATE_IP"
    echo "✅ DNS-post skapad för $REGIONAL_DB_NAME!"
  else
    echo "🔹 DNS-post för $REGIONAL_DB_NAME finns redan, hoppar över skapandet."
  fi
else
  echo "🔹 Ingen region-specifik IP hittades (customDnsConfigs[1]). Skapar ingen extra DNS-post."
fi

# ==============================
# 🔹 11. Verifiera Private Endpoint
# ==============================
echo "✅ Verifierar Private Endpoint..."
az network private-endpoint show \
  --name "$PRIVATE_ENDPOINT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "provisioningState" -o tsv || echo "❌ Private Endpoint hittades ej."

# ==============================
# 🔹 12. Lista DNS-länkar i zonen
# ==============================
echo "✅ Verifierar DNS-länk..."
az network private-dns link vnet list \
  --resource-group "$RESOURCE_GROUP" \
  --zone-name "$PRIVATE_DNS_ZONE" \
  -o table

echo "✅ Cosmos DB: $COSMOS_DB_NAME är nu skapad med Private Endpoint!"
echo "🚀 Klart!"
