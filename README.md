# Azure VNet Flow Logs Automation

A bash script to automatically enable VNet Flow Logs across multiple Azure subscriptions with a single command.

## Overview

This script streamlines the process of enabling Azure Network Watcher Flow Logs for all Virtual Networks across one or more subscriptions. It automatically creates the necessary infrastructure (storage accounts, resource groups, and network watchers) and configures flow logging for each VNet.

## Features

- **Multi-subscription support**: Process all enabled subscriptions, specify a subset, or target just the current subscription
- **Automatic infrastructure creation**: Creates storage accounts, resource groups, and enables Network Watcher
- **Regional awareness**: Handles VNets across multiple Azure regions
- **Dry-run mode**: Preview all commands before execution
- **Idempotent**: Safe to run multiple times
- **Summary reporting**: Clear output of what was discovered and configured

## Prerequisites

- Azure CLI installed and configured
- Authenticated Azure session (`az login`)
- Appropriate permissions:
  - Network Contributor or higher on subscriptions
  - Ability to create resource groups and storage accounts
  - Ability to enable Network Watcher
- `jq` command-line JSON processor

## Installation

1. Clone this repository:
```bash
git clone https://github.com/YOUR_USERNAME/illumio-enable-all-vnets.git
cd illumio-enable-all-vnets
```

2. Make the script executable:
```bash
chmod +x enable-all-vnet-flow-logs.sh
```

## Usage

### Basic Usage

Enable flow logs across all enabled subscriptions:
```bash
./enable-all-vnet-flow-logs.sh
```

### Current Subscription Only

Run only in the currently active subscription:
```bash
./enable-all-vnet-flow-logs.sh --current-subscription
```

This is useful when:
- You want to process a single subscription without affecting others
- You've already set your desired subscription with `az account set`
- You're testing the script on one subscription first

### Dry-Run Mode

Preview all commands without making changes:
```bash
./enable-all-vnet-flow-logs.sh --dry-run
```

Dry-run mode will:
- Display all discovery operations
- Show the exact commands that would be executed
- Provide copy-pasteable commands for manual execution
- Generate a summary without making changes

### Combined Options

You can combine flags in any order:
```bash
# Dry-run for current subscription only
./enable-all-vnet-flow-logs.sh --dry-run --current-subscription

# Same as above, different order
./enable-all-vnet-flow-logs.sh --current-subscription --dry-run
```

### Specify Subscriptions

Alternatively, edit the script to target specific subscriptions:
```bash
SUBSCRIPTIONS=(
  "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy"
)
```

If left empty and `--current-subscription` is not used, the script processes all enabled subscriptions.

## Configuration

Edit these variables at the top of the script to customize behavior:

```bash
STORAGE_SKU="Standard_LRS"              # Storage account SKU
FLOW_LOG_RETENTION_DAYS=30              # How long to retain flow logs
STORAGE_NAME_PREFIX="flowlogs"          # Prefix for storage account names
```

## What It Does

### Phase 1: Discovery
1. Determines which subscription(s) to process:
   - With `--current-subscription`: Uses the currently active subscription
   - With hardcoded list: Uses subscriptions defined in the script
   - Otherwise: Lists all enabled subscriptions
2. For each subscription:
   - Retrieves subscription name
   - Lists all VNets with their resource groups and locations
   - Identifies all regions in use

### Phase 2: Execution
For each subscription with VNets:
1. Creates a resource group for flow log storage (format: `rg-flowlogs-{region}`)
2. Creates a storage account (format: `flowlogs{subscription-id-prefix}`)
3. Enables Network Watcher in each region
4. Creates and enables a flow log for each VNet

## Resource Naming Convention

| Resource Type | Naming Pattern | Example |
|--------------|----------------|---------|
| Resource Group | `rg-flowlogs-{region}` | `rg-flowlogs-eastus` |
| Storage Account | `flowlogs{sub-id-8-chars}` | `flowlogs12345678` |
| Flow Log | `fl-{vnet-name}` | `fl-prod-vnet-001` |

## Output Example

```
Phase 1: Discovery
══════════════════════════════════════════════════════════════════════════
Found 2 subscription(s)

  Subscription: Production (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)
  VNets: 5
  Regions: eastus westus

  Subscription: Development (yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy)
  VNets: 2
  Regions: centralus

Phase 2: Execution
══════════════════════════════════════════════════════════════════════════
Processing: Production (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)
Creating resource group: rg-flowlogs-eastus
Creating storage account: flowlogs12345678
Enabling Network Watcher in eastus
Enabling Network Watcher in westus
Enabling flow log: fl-prod-vnet-001
  ✓ prod-vnet-001
...

══════════════════════════════════════════════════════════════════════════
SUMMARY
══════════════════════════════════════════════════════════════════════════
  Subscriptions:        2
  VNets:                7
  Storage accounts:     2
  Retention (days):     30
```

## Cost Considerations

Enabling VNet Flow Logs incurs Azure costs:
- **Storage**: Flow logs are stored in Azure Storage accounts
- **Network Watcher**: Per-GB charges for flow log data processing
- **Retention**: Longer retention periods increase storage costs

Estimate costs before running in production environments.

## Troubleshooting

### Permission Errors
Ensure you have sufficient permissions on the target subscriptions. Required roles:
- Network Contributor (minimum)
- Storage Account Contributor (for storage account creation)

### Storage Account Name Conflicts
Storage account names must be globally unique. If you encounter conflicts, modify the `STORAGE_NAME_PREFIX` variable.

### Network Watcher Not Available
Some regions may not support Network Watcher. Check [Azure region availability](https://azure.microsoft.com/en-us/explore/global-infrastructure/products-by-region/).

### jq Not Found
Install jq:
- macOS: `brew install jq`
- Ubuntu/Debian: `sudo apt-get install jq`
- Windows: Download from [jqlang.github.io/jq](https://jqlang.github.io/jq/)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see LICENSE file for details

## Author

Created for Illumio VNet flow log management automation.

## Acknowledgments

- Built using Azure CLI and jq
- Designed for Azure Network Watcher Flow Logs v2
