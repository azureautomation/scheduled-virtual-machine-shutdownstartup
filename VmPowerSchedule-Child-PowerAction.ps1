# Tom Cumbow

param(
    $VM,$DesiredState
)

function Log ($Text)
{
	Write-Verbose -Message $Text -Verbose
}

function Get-VmPowerState ($vm)
{
    ((Get-AzVM -Name $vm.Name -ResourceGroup $vm.ResourceGroupName -Status).Statuses | where {$_.Code -like "PowerState*"} | Select -First 1 -ExpandProperty Code) -replace "PowerState/"
}

# Function to handle power state assertion VM
function AssertVirtualMachinePowerState
{
    param(
        [Object]$VirtualMachine,
        [string]$DesiredState
    )
    $vm = $VirtualMachine # shorter name for this variable

    # Get VM with current status
    $currentStatus = Get-VmPowerState $vm
    Log "[$($vm.Name)]: Current power state is [$currentStatus]"

    # If should be started and isn't, start VM
	if($DesiredState -eq "Started" -and $currentStatus -notmatch "running")
	{
        Write-Warning "[$($vm.Name)]: Starting VM"
        Start-AzVM -Id $vm.Id | Write-Verbose
        Start-Sleep 10
        $newStatus = Get-VmPowerState $vm
        Log "[$($vm.Name)]: New power state is [$currentStatus]"
        if ($newStatus -notmatch "running")
        {
            Write-Error "[$($vm.Name)]: VM was NOT successfully started"
        }
	}

	# If should be stopped and isn't, stop VM
	elseif($DesiredState -eq "StoppedDeallocated" -and $currentStatus -ne "deallocated")
	{
        Write-Warning "[$($vm.Name)]: Stopping VM"
        Stop-AzVM -Id $vm.Id -Force | Write-Verbose
        Start-Sleep 10
        $newStatus = Get-VmPowerState $vm
        Log "[$($vm.Name)]: New power state is [$currentStatus]"
        if ($newStatus -ne "deallocated")
        {
            Write-Error "[$($vm.Name)]: VM was NOT successfully deallocated"
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
	$vmName = $VM.Name
    Log "Called with DesiredState: $DesiredState"
	Log "Called with VM with name: $vmName"

    if ($DesiredState -ne "Started" -and $DesiredState -ne "StoppedDeallocated")
        {Write-Error "Runbook called without a valid DesiredState parameter";throw "Runbook called without a valid DesiredState parameter"}

    # Authentication and connection
    $connectionName = "AzureRunAsConnection"
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName
    $DummyVariable = $(Add-AzAccount -ServicePrincipal -TenantId $servicePrincipalConnection.TenantId -ApplicationId $servicePrincipalConnection.ApplicationId -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint)
    Log "Successfully logged into Azure subscription using Az cmdlets..."

    AssertVirtualMachinePowerState -VirtualMachine $VM -DesiredState $DesiredState

}
catch
{
    $errorMessage = $_.Exception.Message
	Write-Error "SEVERE Unexpected exception: $errorMessage"
    throw "Unexpected exception: $errorMessage"
}
finally
{
    Log "Runbook finished (Duration: $(("{0:hh\:mm\:ss}" -f ((Get-Date).ToUniversalTime() - $currentTime))))"
}