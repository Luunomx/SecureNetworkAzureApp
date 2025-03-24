#!/bin/bash
# Skript för att skapa en säker serverarkitektur på Azure med
# Bastion Host, Reverse Proxy och App Server
# Fokus på SSH-agent och ProxyJump för säker åtkomst

# Sätt variabler för resurser
RESOURCE_GROUP="SecureInfraRG"
LOCATION="northeurope"
VNET_NAME="SecureVNet"
BASTION_SUBNET="BastionSubnet"
PROXY_SUBNET="ProxySubnet"
APP_SUBNET="AppSubnet"
NSG_NAME="SubnetNSG"
BASTION_NAME="BastionHost"
REVERSE_PROXY_NAME="ReverseProxy"
APP_SERVER_NAME="AppServer"
BASTION_ASG_NAME="BastionASG"
PROXY_ASG_NAME="ProxyASG"
APP_ASG_NAME="AppASG"
ADMIN_USERNAME="azureuser"
VM_SIZE="Standard_B1s"
VM_IMAGE="Ubuntu2204"

# Skapa säkra SSH-nycklar lokalt
echo "Genererar SSH-nycklar för säker åtkomst..."
ssh-keygen -t rsa -b 4096 -f "./azure_ssh_key" -N ""
SSH_PUBLIC_KEY=$(cat ./azure_ssh_key.pub)

# Sätt korrekta rättigheter för nyckelfilen
chmod 600 ./azure_ssh_key

# Skapa resursfiler för att spara viktig information
touch azure_credentials.txt
touch ssh_guide.txt

echo "SSH-nycklarna har genererats och sparats i ./azure_ssh_key" > azure_credentials.txt

# 1. Skapa resursgrupp
echo "Skapar resursgrupp..."
az group create --name $RESOURCE_GROUP --location $LOCATION

# 2. Skapa Application Security Groups (ASG)
echo "Skapar Application Security Groups..."
az network asg create --resource-group $RESOURCE_GROUP --name $BASTION_ASG_NAME --location $LOCATION
az network asg create --resource-group $RESOURCE_GROUP --name $PROXY_ASG_NAME --location $LOCATION
az network asg create --resource-group $RESOURCE_GROUP --name $APP_ASG_NAME --location $LOCATION

# 3. Skapa Network Security Group (NSG)
echo "Skapar Network Security Group..."
az network nsg create --resource-group $RESOURCE_GROUP --name $NSG_NAME

# 4. Konfigurera NSG-regler
echo "Konfigurerar NSG-regler..."

# 4a. Tillåt SSH (port 22) bara från internet till Bastion Host
az network nsg rule create --resource-group $RESOURCE_GROUP --nsg-name $NSG_NAME \
    --name AllowSSH-ToBastion --priority 1000 \
    --destination-asgs $BASTION_ASG_NAME \
    --destination-port-ranges 22 --protocol Tcp \
    --access Allow --direction Inbound

# 4b. Tillåt SSH från Bastion Host till Reverse Proxy (port 22)
az network nsg rule create --resource-group $RESOURCE_GROUP --nsg-name $NSG_NAME \
    --name AllowSSH-BastionToProxy --priority 1005 \
    --source-asgs $BASTION_ASG_NAME \
    --destination-asgs $PROXY_ASG_NAME \
    --destination-port-ranges 22 --protocol Tcp \
    --access Allow --direction Inbound

# 4c. Tillåt SSH från Bastion Host till App Server (port 22)
az network nsg rule create --resource-group $RESOURCE_GROUP --nsg-name $NSG_NAME \
    --name AllowSSH-BastionToApp --priority 1006 \
    --source-asgs $BASTION_ASG_NAME \
    --destination-asgs $APP_ASG_NAME \
    --destination-port-ranges 22 --protocol Tcp \
    --access Allow --direction Inbound

# 4d. Tillåt HTTP bara till Reverse Proxy
az network nsg rule create --resource-group $RESOURCE_GROUP --nsg-name $NSG_NAME \
    --name AllowHTTP-ToProxy --priority 1010 \
    --destination-asgs $PROXY_ASG_NAME \
    --destination-port-ranges 80 --protocol Tcp \
    --access Allow --direction Inbound

# 5. Skapa virtuellt nätverk och subnät
echo "Skapar virtuellt nätverk med subnät..."
az network vnet create \
    --resource-group $RESOURCE_GROUP \
    --name $VNET_NAME \
    --address-prefix 10.0.0.0/16 \

# 6. Skapa separata subnät för varje server och koppla NSG till varje subnät
echo "Skapar separata subnät för varje server..."
az network vnet subnet create \
    --resource-group $RESOURCE_GROUP \
    --vnet-name $VNET_NAME \
    --name $BASTION_SUBNET \
    --address-prefix 10.0.1.0/24 \
    --network-security-group $NSG_NAME

az network vnet subnet create \
    --resource-group $RESOURCE_GROUP \
    --vnet-name $VNET_NAME \
    --name $PROXY_SUBNET \
    --address-prefix 10.0.2.0/24 \
    --network-security-group $NSG_NAME

az network vnet subnet create \
    --resource-group $RESOURCE_GROUP \
    --vnet-name $VNET_NAME \
    --name $APP_SUBNET \
    --address-prefix 10.0.3.0/24 \
    --network-security-group $NSG_NAME

# 7. Skapa publika IP-adresser för Bastion och Reverse Proxy
echo "Skapar publika IP-adresser..."
az network public-ip create --resource-group $RESOURCE_GROUP --name "${BASTION_NAME}-IP" --allocation-method Static
az network public-ip create --resource-group $RESOURCE_GROUP --name "${REVERSE_PROXY_NAME}-IP" --allocation-method Static

# 8. Skapa nätverksgränssnitt för alla VM:er
echo "Skapar nätverksgränssnitt..."

# Bastion Host NIC med publik IP, kopplad till BastionSubnet
az network nic create \
    --resource-group $RESOURCE_GROUP \
    --name "${BASTION_NAME}-NIC" \
    --vnet-name $VNET_NAME \
    --subnet $BASTION_SUBNET \
    --public-ip-address "${BASTION_NAME}-IP" \
    --application-security-groups $BASTION_ASG_NAME

# Reverse Proxy NIC med publik IP, kopplad till ProxySubnet
az network nic create \
    --resource-group $RESOURCE_GROUP \
    --name "${REVERSE_PROXY_NAME}-NIC" \
    --vnet-name $VNET_NAME \
    --subnet $PROXY_SUBNET \
    --public-ip-address "${REVERSE_PROXY_NAME}-IP" \
    --application-security-groups $PROXY_ASG_NAME

# App Server NIC utan publik IP, kopplad till AppSubnet
az network nic create \
    --resource-group $RESOURCE_GROUP \
    --name "${APP_SERVER_NAME}-NIC" \
    --vnet-name $VNET_NAME \
    --subnet $APP_SUBNET \
    --application-security-groups $APP_ASG_NAME

# 9. Skapa virtuella maskiner
echo "Skapar virtuella maskiner..."

# Bastion Host
az vm create \
    --resource-group $RESOURCE_GROUP \
    --name $BASTION_NAME \
    --nics "${BASTION_NAME}-NIC" \
    --image $VM_IMAGE \
    --admin-username $ADMIN_USERNAME \
    --ssh-key-values "./azure_ssh_key.pub" \
    --size $VM_SIZE

# Reverse Proxy
az vm create \
    --resource-group $RESOURCE_GROUP \
    --name $REVERSE_PROXY_NAME \
    --nics "${REVERSE_PROXY_NAME}-NIC" \
    --image $VM_IMAGE \
    --admin-username $ADMIN_USERNAME \
    --ssh-key-values "./azure_ssh_key.pub" \
    --size $VM_SIZE

# App Server
az vm create \
    --resource-group $RESOURCE_GROUP \
    --name $APP_SERVER_NAME \
    --nics "${APP_SERVER_NAME}-NIC" \
    --image $VM_IMAGE \
    --admin-username $ADMIN_USERNAME \
    --ssh-key-values "./azure_ssh_key.pub" \
    --size $VM_SIZE

# 10. Vänta en kort stund för att se till att VM:erna är tillgängliga
echo "Väntar på att VM:erna ska startas upp..."
sleep 60

# 11. Hämta IP-adresser för konfiguration
echo "Hämtar IP-adresser för konfiguration..."
BASTION_IP=$(az network public-ip show --resource-group $RESOURCE_GROUP --name "${BASTION_NAME}-IP" --query ipAddress -o tsv)
PROXY_IP=$(az network public-ip show --resource-group $RESOURCE_GROUP --name "${REVERSE_PROXY_NAME}-IP" --query ipAddress -o tsv)
APP_PRIVATE_IP=$(az vm list-ip-addresses --resource-group $RESOURCE_GROUP --name $APP_SERVER_NAME --query "[0].virtualMachine.network.privateIpAddresses[0]" -o tsv)
PROXY_PRIVATE_IP=$(az vm list-ip-addresses --resource-group $RESOURCE_GROUP --name $REVERSE_PROXY_NAME --query "[0].virtualMachine.network.privateIpAddresses[0]" -o tsv)

echo "Bastion IP: $BASTION_IP" >> azure_credentials.txt
echo "Reverse Proxy IP: $PROXY_IP" >> azure_credentials.txt
echo "Reverse Proxy Privat IP: $PROXY_PRIVATE_IP" >> azure_credentials.txt
echo "App Server Privat IP: $APP_PRIVATE_IP" >> azure_credentials.txt

# 12. Konfigurera SSH på Bastion för att säkerställa att agentvidarebefordran tillåts
echo "Konfigurerar Bastion Host för SSH-agentvidarebefordran..."
SSH_CONFIG="Host *
    ForwardAgent yes
    ServerAliveInterval 60
    StrictHostKeyChecking accept-new"

az vm run-command invoke \
  --resource-group $RESOURCE_GROUP \
  --name $BASTION_NAME \
  --command-id RunShellScript \
  --scripts "echo '$SSH_CONFIG' | sudo tee /etc/ssh/ssh_config.d/99-azure-custom.conf && sudo systemctl reload sshd"

# 13. Konfigurera App Server med .NET Runtime
echo "Konfigurerar App Server med .NET Runtime..."
az vm run-command invoke \
  --resource-group $RESOURCE_GROUP \
  --name $APP_SERVER_NAME \
  --command-id RunShellScript \
  --scripts "wget https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb && \
             sudo dpkg -i packages-microsoft-prod.deb && \
             rm packages-microsoft-prod.deb && \
             sudo apt-get update && \
             sudo apt-get install -y aspnetcore-runtime-9.0"
             
# 14. Konfigurera Reverse Proxy med Nginx
echo "Konfigurerar Reverse Proxy..."
PROXY_CONFIG="server {
    listen 80 default_server;
    listen [::]:80 default_server;
    
    location / {
        proxy_pass http://$APP_PRIVATE_IP:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection keep-alive;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}"

az vm run-command invoke \
  --resource-group $RESOURCE_GROUP \
  --name $REVERSE_PROXY_NAME \
  --command-id RunShellScript \
  --scripts "sudo apt-get update && sudo apt-get install -y nginx && echo '$PROXY_CONFIG' | sudo tee /etc/nginx/sites-available/default && sudo nginx -t && sudo systemctl restart nginx"

# 15. Skapa en SSH config-fil lokalt för enkel åtkomst
echo "Skapar SSH konfigurationsfil..."
mkdir -p ~/.ssh

cat > ~/.ssh/config << EOF
# SSH-konfiguration för säker åtkomst till Azure-miljön

# Bastion Host
Host bastion
    HostName $BASTION_IP
    User $ADMIN_USERNAME
    IdentityFile $(pwd)/azure_ssh_key
    ForwardAgent yes

# Reverse Proxy via Bastion
Host reverse-proxy
    HostName $PROXY_PRIVATE_IP
    User $ADMIN_USERNAME
    ProxyJump bastion
    ForwardAgent yes

# App Server via Bastion
Host app-server
    HostName $APP_PRIVATE_IP
    User $ADMIN_USERNAME
    ProxyJump bastion
    ForwardAgent yes
EOF

chmod 600 ~/.ssh/config

echo "SSH-konfiguration har sparats i ~/.ssh/config" >> azure_credentials.txt

# 16. Skapa utförliga SSH-instruktioner
echo "Skapar SSH-konfigurationsguide..."
cat > ssh_guide.txt << EOF
========= GUIDE FÖR SÄKER SSH-ÅTKOMST =========

SSH-konfiguration har automatiskt skapats i din ~/.ssh/config-fil.
Nu kan du ansluta till servrarna med enkla kommandon!

Steg 1: Starta SSH-agenten och lägg till din nyckel
----------------------------------------------
eval \$(ssh-agent)
ssh-add $(pwd)/azure_ssh_key

Steg 2: Anslut till servrarna
------------------------
Till Bastion Host:
  ssh bastion

Till Reverse Proxy (genom Bastion):
  ssh reverse-proxy

Till App Server (genom Bastion):
  ssh app-server

Alternativa direkta kommandon (om du inte vill använda config-filen):
------------------------------------------------------------
Till Bastion Host:
  ssh -A -i $(pwd)/azure_ssh_key $ADMIN_USERNAME@$BASTION_IP

Till Reverse Proxy (genom Bastion), med ProxyJump:
  ssh -A -i $(pwd)/azure_ssh_key -J $ADMIN_USERNAME@$BASTION_IP $ADMIN_USERNAME@$PROXY_PRIVATE_IP

Till App Server (genom Bastion), med ProxyJump:
  ssh -A -i $(pwd)/azure_ssh_key -J $ADMIN_USERNAME@$BASTION_IP $ADMIN_USERNAME@$APP_PRIVATE_IP

Filöverföring med SCP och ProxyJump:
---------------------------------
Kopiera en fil till App Server:
  scp -o "ProxyJump $ADMIN_USERNAME@$BASTION_IP" ./minfil.txt $ADMIN_USERNAME@$APP_PRIVATE_IP:~/

Åtkomst till webbapplikationen:
-------------------------
För att nå webbapplikationen (som proxyas vidare till App Server):
  http://$PROXY_IP

För direkt åtkomst till App Server via SSH-tunnel:
  ssh -L 8080:$APP_PRIVATE_IP:80 bastion

Då kan du besöka http://localhost:8080 i din webbläsare.

VIKTIGT OM SSH-AGENT OCH SÄKERHET:
-----------------------------
- SSH-agenten (-A) vidarebefordrar din autentisering tillfälligt
- Ingen kopia av din privata nyckel lämnar din dator
- Denna metod är mycket säkrare än att kopiera privata nycklar till servrar
- ProxyJump (-J) är modernare och säkrare än äldre SSH-tunneltekniker
EOF

echo "======== KONFIGURATION KLAR ========"
echo "Se azure_credentials.txt för IP-adresser och andra detaljer"
echo "Se ssh_guide.txt för utförliga anslutningsinstruktioner"
echo ""
echo "För att komma igång direkt, kör följande kommandon:"
echo "eval \$(ssh-agent)"
echo "ssh-add $(pwd)/azure_ssh_key"
echo "ssh app-server  # För att ansluta direkt till App Server genom Bastion"