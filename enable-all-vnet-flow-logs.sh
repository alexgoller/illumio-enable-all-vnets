#!/bin/bash

# =============================================================================
# Enable VNet Flow Logs Across Multiple Azure Subscriptions
# Creates one storage account per subscription, enables flow logs for all VNets
# =============================================================================

# -----------------------------------------------------------------------------
# Usage: ./enable-vnet-flowlogs.sh [--dry-run]
#        --dry-run    Show all commands without executing them
# -----------------------------------------------------------------------------

DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
  DRY_RUN=true
  echo "╔═══════════════════════════════════════════════════════════════════════╗"
  echo "║                           DRY RUN MODE                                ║"
  echo "║         No changes will be made. Commands shown for review.          ║"
  echo "╚═══════════════════════════════════════════════════════════════════════╝"
  echo ""
fi

# Configuration
STORAGE_SKU="Standard_LRS"
FLOW_LOG_RETENTION_DAYS=30
STORAGE_NAME_PREFIX="flowlogs"

# Optional: Specify subscription IDs, or leave empty to process all
SUBSCRIPTIONS=(
  # "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  # "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy"
)

# -----------------------------------------------------------------------------
# PHASE 1: Discovery (always runs to gather information)
# -----------------------------------------------------------------------------

echo "Phase 1: Discovery"
echo "══════════════════════════════════════════════════════════════════════════"
echo ""

if [ "$DRY_RUN" = true ]; then
  echo "# Get all enabled subscriptions"
  echo "az account list --query \"[?state=='Enabled'].id\" -o tsv"
  echo ""
fi

if [ ${#SUBSCRIPTIONS[@]} -eq 0 ]; then
  SUBSCRIPTIONS=($(az account list --query "[?state=='Enabled'].id" -o tsv))
fi

echo "Found ${#SUBSCRIPTIONS[@]} subscription(s)"
echo ""

# Collect all information first
declare -A SUB_NAMES
declare -A SUB_VNETS
declare -A SUB_REGIONS

for SUB_ID in "${SUBSCRIPTIONS[@]}"; do
  if [ "$DRY_RUN" = true ]; then
    echo "# Set subscription context"
    echo "az account set --subscription \"$SUB_ID\""
    echo ""
    echo "# Get subscription name"
    echo "az account show --query \"name\" -o tsv"
    echo ""
  fi
  
  az account set --subscription "$SUB_ID"
  SUB_NAME=$(az account show --query "name" -o tsv)
  SUB_NAMES[$SUB_ID]="$SUB_NAME"
  
  if [ "$DRY_RUN" = true ]; then
    echo "# List all VNets in subscription"
    echo "az network vnet list --query \"[].{id:id, name:name, rg:resourceGroup, location:location}\" -o json"
    echo ""
  fi
  
  VNETS=$(az network vnet list --query "[].{id:id, name:name, rg:resourceGroup, location:location}" -o json)
  SUB_VNETS[$SUB_ID]="$VNETS"
  
  REGIONS=$(echo "$VNETS" | jq -r '.[].location' | sort -u | tr '\n' ' ')
  SUB_REGIONS[$SUB_ID]="$REGIONS"
  
  VNET_COUNT=$(echo "$VNETS" | jq length)
  echo "  Subscription: $SUB_NAME ($SUB_ID)"
  echo "  VNets: $VNET_COUNT"
  echo "  Regions: $REGIONS"
  echo ""
done

# -----------------------------------------------------------------------------
# PHASE 2: Execution Plan / Execution
# -----------------------------------------------------------------------------

echo ""
echo "Phase 2: $([ "$DRY_RUN" = true ] && echo "Execution Plan" || echo "Execution")"
echo "══════════════════════════════════════════════════════════════════════════"
echo ""

if [ "$DRY_RUN" = true ]; then
  echo "# ==========================================================================="
  echo "# COPY-PASTEABLE COMMANDS START HERE"
  echo "# ==========================================================================="
  echo ""
fi

TOTAL_VNETS=0
TOTAL_STORAGE_ACCOUNTS=0

for SUB_ID in "${SUBSCRIPTIONS[@]}"; do
  SUB_NAME="${SUB_NAMES[$SUB_ID]}"
  VNETS="${SUB_VNETS[$SUB_ID]}"
  REGIONS="${SUB_REGIONS[$SUB_ID]}"
  
  VNET_COUNT=$(echo "$VNETS" | jq length)
  
  if [ "$VNET_COUNT" -eq 0 ]; then
    if [ "$DRY_RUN" = true ]; then
      echo "# ──────────────────────────────────────────────────────────────────────────"
      echo "# SUBSCRIPTION: $SUB_NAME"
      echo "# ID: $SUB_ID"
      echo "# SKIPPED: No VNets found"
      echo "# ──────────────────────────────────────────────────────────────────────────"
      echo ""
    else
      echo "Skipping $SUB_NAME - no VNets"
    fi
    continue
  fi

  TOTAL_VNETS=$((TOTAL_VNETS + VNET_COUNT))
  TOTAL_STORAGE_ACCOUNTS=$((TOTAL_STORAGE_ACCOUNTS + 1))

  # Calculate resource names
  PRIMARY_REGION=$(echo "$REGIONS" | awk '{print $1}')
  SHORT_SUB=$(echo "$SUB_ID" | tr -d '-' | cut -c1-8)
  STORAGE_NAME="${STORAGE_NAME_PREFIX}${SHORT_SUB}"
  STORAGE_RG="rg-flowlogs-${PRIMARY_REGION}"
  STORAGE_ID="/subscriptions/${SUB_ID}/resourceGroups/${STORAGE_RG}/providers/Microsoft.Storage/storageAccounts/${STORAGE_NAME}"

  if [ "$DRY_RUN" = true ]; then
    echo "# ──────────────────────────────────────────────────────────────────────────"
    echo "# SUBSCRIPTION: $SUB_NAME"
    echo "# ID: $SUB_ID"
    echo "# VNets: $VNET_COUNT"
    echo "# ──────────────────────────────────────────────────────────────────────────"
    echo ""
    
    echo "# Set subscription context"
    echo "az account set --subscription \"$SUB_ID\""
    echo ""
    
    echo "# Create resource group for flow log storage"
    echo "az group create \\"
    echo "  --name \"$STORAGE_RG\" \\"
    echo "  --location \"$PRIMARY_REGION\""
    echo ""
    
    echo "# Create storage account for flow logs"
    echo "az storage account create \\"
    echo "  --name \"$STORAGE_NAME\" \\"
    echo "  --resource-group \"$STORAGE_RG\" \\"
    echo "  --location \"$PRIMARY_REGION\" \\"
    echo "  --sku \"$STORAGE_SKU\" \\"
    echo "  --kind StorageV2"
    echo ""
    
    echo "# Get storage account resource ID"
    echo "STORAGE_ID=\$(az storage account show --name \"$STORAGE_NAME\" --resource-group \"$STORAGE_RG\" --query \"id\" -o tsv)"
    echo ""
    
    # Network Watcher for each region
    for REGION in $REGIONS; do
      echo "# Enable Network Watcher in $REGION"
      echo "az network watcher configure \\"
      echo "  --resource-group \"NetworkWatcherRG\" \\"
      echo "  --locations \"$REGION\" \\"
      echo "  --enabled true"
      echo ""
    done
    
    # Flow logs for each VNet
    echo "$VNETS" | jq -c '.[]' | while read -r VNET; do
      VNET_NAME=$(echo "$VNET" | jq -r '.name')
      VNET_RG=$(echo "$VNET" | jq -r '.rg')
      VNET_ID=$(echo "$VNET" | jq -r '.id')
      VNET_LOCATION=$(echo "$VNET" | jq -r '.location')
      FLOW_LOG_NAME="fl-${VNET_NAME}"

      echo "# Enable flow log for VNet: $VNET_NAME (RG: $VNET_RG)"
      echo "az network watcher flow-log create \\"
      echo "  --name \"$FLOW_LOG_NAME\" \\"
      echo "  --location \"$VNET_LOCATION\" \\"
      echo "  --vnet \"$VNET_ID\" \\"
      echo "  --storage-account \"\$STORAGE_ID\" \\"
      echo "  --enabled true \\"
      echo "  --retention $FLOW_LOG_RETENTION_DAYS"
      echo ""
    done
    
  else
    # ACTUAL EXECUTION
    echo "──────────────────────────────────────────────────────────────────────────"
    echo "Processing: $SUB_NAME ($SUB_ID)"
    echo "──────────────────────────────────────────────────────────────────────────"
    
    az account set --subscription "$SUB_ID"
    
    echo "Creating resource group: $STORAGE_RG"
    az group create --name "$STORAGE_RG" --location "$PRIMARY_REGION" --output none
    
    echo "Creating storage account: $STORAGE_NAME"
    az storage account create \
      --name "$STORAGE_NAME" \
      --resource-group "$STORAGE_RG" \
      --location "$PRIMARY_REGION" \
      --sku "$STORAGE_SKU" \
      --kind StorageV2 \
      --output none
    
    STORAGE_ID=$(az storage account show --name "$STORAGE_NAME" --resource-group "$STORAGE_RG" --query "id" -o tsv)
    
    for REGION in $REGIONS; do
      echo "Enabling Network Watcher in $REGION"
      az network watcher configure --resource-group "NetworkWatcherRG" --locations "$REGION" --enabled true --output none 2>/dev/null || true
    done
    
    echo "$VNETS" | jq -c '.[]' | while read -r VNET; do
      VNET_NAME=$(echo "$VNET" | jq -r '.name')
      VNET_ID=$(echo "$VNET" | jq -r '.id')
      VNET_LOCATION=$(echo "$VNET" | jq -r '.location')
      FLOW_LOG_NAME="fl-${VNET_NAME}"

      echo "Enabling flow log: $FLOW_LOG_NAME"
      az network watcher flow-log create \
        --name "$FLOW_LOG_NAME" \
        --location "$VNET_LOCATION" \
        --vnet "$VNET_ID" \
        --storage-account "$STORAGE_ID" \
        --enabled true \
        --retention "$FLOW_LOG_RETENTION_DAYS" \
        --output none

      if [ $? -eq 0 ]; then
        echo "  ✓ $VNET_NAME"
      else
        echo "  ✗ $VNET_NAME (failed)"
      fi
    done
    
    echo ""
  fi
done

# -----------------------------------------------------------------------------
# SUMMARY
# -----------------------------------------------------------------------------

echo ""
echo "══════════════════════════════════════════════════════════════════════════"
echo "SUMMARY"
echo "══════════════════════════════════════════════════════════════════════════"
echo "  Subscriptions:        ${#SUBSCRIPTIONS[@]}"
echo "  VNets:                $TOTAL_VNETS"
echo "  Storage accounts:     $TOTAL_STORAGE_ACCOUNTS"
echo "  Retention (days):     $FLOW_LOG_RETENTION_DAYS"
echo ""

if [ "$DRY_RUN" = true ]; then
  echo "══════════════════════════════════════════════════════════════════════════"
  echo "DRY RUN COMPLETE"
  echo ""
  echo "To execute automatically:"
  echo "  ./enable-vnet-flowlogs.sh"
  echo ""
  echo "To execute manually:"
  echo "  Copy the commands above and run them in your terminal"
  echo "══════════════════════════════════════════════════════════════════════════"
else
  echo "══════════════════════════════════════════════════════════════════════════"
  echo "EXECUTION COMPLETE"
  echo "══════════════════════════════════════════════════════════════════════════"
fi