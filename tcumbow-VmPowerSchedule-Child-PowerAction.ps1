# Tom Cumbow

param(
    $JsonData
)

function Log
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory=$true,ValueFromPipeline)]
		[string]
		$Text,
		[Parameter(Mandatory=$false)]
		[switch]
		$Warning,
		[Parameter(Mandatory=$false)]
		[switch]
		$Error
	)


	if ($Error) {Write-Error $Text}
	elseif ($Warning) {Write-Warning $Text}
	else {Write-Verbose $Text}
}

# Define function to handle checking the ScheduleText against a given DateTime (which will probably be the current DateTime in most cases)
# This function contains nested functions so that you can collapse all the date/time logic more easily

function Get-VmPowerState ($vm)
{
    ((Get-AzVM -Name $vm.Name -ResourceGroup $vm.ResourceGroupName -Status).Statuses | where {$_.Code -like "PowerState*"} | Select -First 1 -ExpandProperty Code) -replace "PowerState/"
}
# Function to handle power state assertion VM
function AssertVirtualMachinePowerState
{
    param(
        [Object]$VirtualMachine,
        [string]$DesiredState,
        [bool]$Simulate
    )
    $vm = $VirtualMachine # shorter name for this variable

    # Get VM with current status
    $currentStatus = Get-VmPowerState $vm
    Log "[$($vm.Name)]: Current power state is [$currentStatus]"

    # If should be started and isn't, start VM
	if($DesiredState -eq "Started" -and $currentStatus -notmatch "running")
	{
        if($Simulate)
        {
            Log -Warning "[$($vm.Name)]: SIMULATION -- Would have started VM. (No action taken)"
        }
        else
        {
            Log -Warning "[$($vm.Name)]: Starting VM"
            Start-Job {Start-AzVM -Id $Using:vm.Id}
        }
	}

	# If should be stopped and isn't, stop VM
	elseif($DesiredState -eq "StoppedDeallocated" -and $currentStatus -ne "deallocated")
	{
        if($Simulate)
        {
            Log -Warning "[$($vm.Name)]: SIMULATION -- Would have stopped VM. (No action taken)"
        }
        else
        {
            Log -Warning "[$($vm.Name)]: Stopping VM"
            Start-Job {Stop-AzVM -Id $Using:vm.Id -Force}
        }
	}

    # Otherwise, current power state is correct
    else
    {
        Log "[$($vm.Name)]: Current power state [$currentStatus] is correct."
    }
}

# Main runbook content
try
{
    $currentTime = (Get-Date).ToUniversalTime()
    if($Simulate)
    {
        Log "*** Running in SIMULATE mode. No power actions will be taken. ***"
    }
    else
    {
        Log "*** Running in LIVE mode. ***"
    }
	Log "Converting from Json"
	$data = $JsonData.EventProperties.Data | ConvertFrom-Json
	$Action = $data.Action
	$VmObj = $data.VM
    Log "Called with action: $Action"
	Log "Called with VM ID: $(VmObj.Id)"

    # Authentication and connection
    $connectionName = "AzureRunAsConnection"
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName
    $DummyVariable = $(Add-AzAccount -ServicePrincipal -TenantId $servicePrincipalConnection.TenantId -ApplicationId $servicePrincipalConnection.ApplicationId -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint)
    Log "Successfully logged into Azure subscription using Az cmdlets..."

    
    
}
catch
{
    $errorMessage = $_.Exception.Message
	Log -Error "SEVERE Unexpected exception: $errorMessage"
    throw "Unexpected exception: $errorMessage"
}
finally
{
    Log "Runbook finished (Duration: $(("{0:hh\:mm\:ss}" -f ((Get-Date).ToUniversalTime() - $currentTime))))"
}