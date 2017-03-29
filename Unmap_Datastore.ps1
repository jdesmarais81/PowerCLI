# Start Load VMware  Snapin (if not already loaded)
if (!(Get-PSSnapin -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue)) {
	if (!(Add-PSSnapin -PassThru VMware.VimAutomation.Core)) {
		# Error out if loading fails
		Write-Error "ERROR: Cannot load the VMware Snapin. Is the PowerCLI installed?"
		Exit
	}
}
# End Load VMware  Snapin (if not already loaded)

# Start Set Session Timout
$initialTimeout = (Get-PowerCLIConfiguration -Scope Session).WebOperationTimeoutSeconds
Set-PowerCLIConfiguration -Scope Session -WebOperationTimeoutSeconds -1 -Confirm:$False
# End Set Session Timout

# Start Global Definitions
$VIServer = "yourvCenter.lan.local"
$UNMAPs = @(	("esx0019.*", "DS01*"),
                ("esx0017.*", "DS02*"),
                ("esx0003.*", "DS03*"))
# End Global Definitions

# Start vCenter Connection
Write-Output "Starting to Process vCenter Connection to " $VIServer " ..."
$OpenConnection = $global:DefaultVIServers | where { $_.Name -eq $VIServer }
if($OpenConnection.IsConnected) {
	Write-Output "vCenter is Already Connected..."
	$VIConnection = $OpenConnection
} else {
	Write-Output "Connecting vCenter..."
	$VIConnection = Connect-VIServer -Server $VIServer
}

if (-not $VIConnection.IsConnected) {
	Write-Error "Error: vCenter Connection Failed"
    Exit
}
# End vCenter Connection

# Start Loop Datastores and run UNMAP
foreach ($UNMAP in $UNMAPs){
    $yourHost = $UNMAP[0]
    $esxcli2 = Get-VMHost $yourHost | Get-ESXCLI -V2
	foreach ($DS in Get-VMHost -Name $yourHost | Get-Datastore | where {$_.Name -like $UNMAP[1] -and $_.State -eq "Available" -and $_.Accessible -eq "True"})
        { 
        Write-Output "$(Get-Date -Format T) ...Starting processing $DS on $yourhost"
        $startDTM = (Get-Date)
		$arguments = $esxcli2.storage.vmfs.unmap.CreateArgs()
		$arguments.volumelabel = $DS
		try {
			$esxcli2.storage.vmfs.unmap.Invoke($arguments)
			}
		catch {
			Write-Output "A Error occured: " "" $error[0] ""
			}
        Write-Output "$(Get-Date -Format T) Finished processing $DS on $yourhost" 
        $endDTM = (Get-Date)
        Write-Output "Elapsed Time: $(($endDTM-$startDTM).totalMinutes) minutes"
        }
}
# End Loop Datastores and run UNMAP

# Start Revert Timeout
Set-PowerCLIConfiguration -Scope Session -WebOperationTimeoutSeconds $initialTimeout -Confirm:$False
# End Revert Timeout