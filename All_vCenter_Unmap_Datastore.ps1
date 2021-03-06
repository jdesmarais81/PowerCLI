Clear-Host
$ErrorActionPreference = "Continue"
$DebugPreference = "Continue"
$VerbosePreference = "Continue"

@"
## vmware_unmap_datastore.ps1 #################################################
Usage:        powershell -ExecutionPolicy Bypass -File ./vmware_unmap_datastore.ps1

Purpose:      Dumps Datastore (in GB): Capacity, Free, and Uncommitted space to
              to CSV and runs ESXCli command 'unmap' to retrieve unused space
              on Thin Provisioned LUNs.
JD Comment:   This Script allows you to scan all datastores in a vCenter using any
              host.  Which is fine for most but it will scan remote hosts as well
              that are attached to the vCenter.
              Note:  this has also been found to have errors on some version that 
              I do not know which. 

Requirements: Windows Powershell and VI Toolkit

Assumptions:  All ESXi hosts have access to all datastores

TO DO:        Import Dell Equal Logic Module, get Used space before/after unmap

Created By:   lars.bjerke@augustschell.com
History:      06/20/2014  -  Created
              03/29/2017  -  Forked by JD
###############################################################################
"@

## Prompt Administrator for vCenter Server ####################################
###############################################################################
[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.VisualBasic') | Out-Null
$VCServer = [Microsoft.VisualBasic.Interaction]::InputBox(
                "vCenter Server FQDN or IP",
                "PowerCLI Prompt: vCenter Server Query",
                "VCEN-001.TEST.DEV.DOMAIN.COM")


## Filename and path to save the CSV ##########################################
###############################################################################
$timestamp = $(((get-date).ToUniversalTime()).ToString("yyyyMMdd"))
$output_path = [Environment]::GetFolderPath("mydocuments")
$output_file = $output_path + "\datastore_info-" + $timestamp + ".csv"

## Ensure VMware Automation Core Snap In is loaded ############################
###############################################################################
if ((Get-PSSnapin -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue) -eq $null) {
     Add-PSSnapin VMware.VimAutomation.Core      }

## Unmap can take hour+ per data store on first run, remove timeout ###########
###############################################################################
Set-PowerCLIConfiguration -WebOperationTimeoutSeconds -1 -Scope Session -Confirm:$false

## Ignore Certificates Warning ################################################
###############################################################################
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Scope Session -Confirm:$false

## Connect to vCenter Server ##################################################
# Prompt user for vCenter creds every time unless creds are stored using:
# New-VICredentialStoreItem -Host $VIServer -User "AD\user" -Password 'pass'
###############################################################################
$VC = Connect-VIServer $VCServer
Write-verbose "Connected to '$($VC.Name):$($VC.port)' as '$($VC.User)'"

## Connect to first ESXi host in list to run unmap ESXCLI #####################
###############################################################################
$ESXiHost = Get-VMHost |Select-Object -first 1
$ESXCLI = Get-EsxCli -VMHost $ESXiHost
Write-Verbose "Using ESXi host '($ESXiHost)' for CLI"


## Establish structure to store CSV data ######################################
# Try to open a CSV file, if it doesn't exist a new one will be created.
###############################################################################
try {
    $report = Import-Csv $output_file
    }
catch {
    $report = @()
    }

## CSV Collect Data ###########################################################
# Function to collect datastore usage information to be stored in CSV
###############################################################################
function get_datastore_usage {
    Write-Verbose "[ $($dsv.Name) ] - Gathering statistics..."
    $row = "" |select TIMESTAMP, DATASTORE, CAPACITY_GB, FREE_GB, UNCOMMITED_GB
    $row.TIMESTAMP = $(((get-date).ToUniversalTime()).ToString("yyyyMMddThhmmssZ"))
    $row.DATASTORE = $ds.Name
    $row.CAPACITY_GB = [int]($ds.CapacityGB)
    $row.FREE_GB = [int]($ds.FreeSpaceGB)
    $row.UNCOMMITED_GB = [int]($dsv.Summary.Uncommitted / (1024 * 1024 * 1024))
    return $row
    }

## Unmap ######################################################################
# unmap creates a maximum of 200 (changable) 1MB files at a time to 100%.
###############################################################################
function reclaim_datastore_used_space {
    Write-Verbose "[ $($dsv.Name) ] - Running unmap, can take 30+ minutes"
    try {
        $RETVAL = $ESXCLI.storage.vmfs.unmap(800, $ds.Name, $null)
        }
    catch [VMware.VimAutomation.Sdk.Types.V1.ErrorHandling.VimException.ViError]{
        Write-Verbose $_.Exception.Message
        }
    }

## Loop through datastores ####################################################
# Loops through all datastores seen by vCenter.  If the datastore is accessible
# and capable of thinprovisioning: Gathers datastore usage data, runs unmap
###############################################################################
foreach ($ds in Get-Datastore) {
    $dsv = $ds |Get-View
    if ($dsv.Summary.accessible -and $dsv.Capability.PerFileThinProvisioningSupported) {
        Write-Verbose "[ $($dsv.Name) ] - Refreshing Datastore Data..."
        $dsv.RefreshDatastore()
        $dsv.RefreshDatastoreStorageInfo()
        $report += get_datastore_usage
        reclaim_datastore_used_space
        }
    }


## Write CSV data to file #####################################################
###############################################################################
$report |Export-Csv $output_file -NoTypeInformation

## Open CSV file using Notepad ################################################
###############################################################################
Start-Process notepad -ArgumentList $output_file

## Properly disconnect from vCenter Server ####################################
###############################################################################
Disconnect-VIServer $VC -Confirm:$false
