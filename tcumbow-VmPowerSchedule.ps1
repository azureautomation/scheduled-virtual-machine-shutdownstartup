# TFC

param(
    [parameter(Mandatory=$false)]
    [bool]$Simulate = $true,
    [parameter(Mandatory=$false)]
    [bool]$SkipAuth = $false
)

$VERSION = "0.0.3"

Install-Module Az.Resources -Scope CurrentUser
Install-Module Az.Compute -Scope CurrentUser

# Define function to check current time against specified range
function CheckScheduleEntry ([string]$TimeRange)
{
	# Initialize variables
	$rangeStart, $rangeEnd, $parsedDay = $null
	$currentTime = (Get-Date).ToUniversalTime()
    $midnight = $currentTime.AddDays(1).Date
    Write-Warning "Interpreting time range string: $TimeRange"

	try
	{
	    # Parse as range if contains '->'
	    if($TimeRange -like "*->*")
	    {
	        $timeRangeComponents = $TimeRange -split "->" | foreach {$_.Trim()}
	        if($timeRangeComponents.Count -eq 2)
	        {
	            $rangeStart = Get-Date $timeRangeComponents[0]
                Write-Warning "Interpreted start time as $rangeStart"
	            $rangeEnd = Get-Date $timeRangeComponents[1]
                Write-Warning "Interpreted end time as $rangeEnd"

	            # Check for crossing midnight
	            if($rangeStart -gt $rangeEnd)
	            {
                    # If current time is between the start of range and midnight tonight, interpret start time as earlier today and end time as tomorrow
                    if($currentTime -ge $rangeStart -and $currentTime -lt $midnight)
                    {
                        $rangeEnd = $rangeEnd.AddDays(1)
                    }
                    # Otherwise interpret start time as yesterday and end time as today
                    else
                    {
                        $rangeStart = $rangeStart.AddDays(-1)
                    }
	            }
	        }
	        else
	        {
	            Write-Warning "`tWARNING: Invalid time range format. Expects valid .Net DateTime-formatted start time and end time separated by '->'"
	        }
	    }
	    # Otherwise attempt to parse as a full day entry, e.g. 'Monday' or 'December 25'
	    else
	    {
	        # If specified as day of week, check if today
	        if([System.DayOfWeek].GetEnumValues() -contains $TimeRange)
	        {
	            if($TimeRange -eq (Get-Date).DayOfWeek)
	            {
	                $parsedDay = Get-Date "00:00"
	            }
	            else
	            {
	                # Skip detected day of week that isn't today
	            }
	        }
	        # Otherwise attempt to parse as a date, e.g. 'December 25'
	        else
	        {
	            $parsedDay = Get-Date $TimeRange
	        }

	        if($null -ne $parsedDay)
	        {
	            $rangeStart = $parsedDay # Defaults to midnight
	            $rangeEnd = $parsedDay.AddHours(23).AddMinutes(59).AddSeconds(59) # End of the same day
	        }
	    }
	}
	catch
	{
	    # Record any errors and return false by default
	    Write-Warning "`tWARNING: Exception encountered while parsing time range. Details: $($_.Exception.Message). Check the syntax of entry, e.g. '<StartTime> -> <EndTime>', or days/dates like 'Sunday' and 'December 25'"
	    return $false
	}

	# Check if current time falls within range
	if($currentTime -ge $rangeStart -and $currentTime -le $rangeEnd)
	{
	    return $true
	}
	else
	{
	    return $false
	}

} # End function CheckScheduleEntry

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
    Write-Warning "[$($vm.Name)]: Current power state is [$currentStatus]"

    # If should be started and isn't, start VM
	if($DesiredState -eq "Started" -and $currentStatus -notmatch "running")
	{
        if($Simulate)
        {
            Write-Warning "[$($vm.Name)]: SIMULATION -- Would have started VM. (No action taken)"
        }
        else
        {
            Write-Warning "[$($vm.Name)]: Starting VM"
            Start-AzVM -Id $vm.Id
        }
	}

	# If should be stopped and isn't, stop VM
	elseif($DesiredState -eq "StoppedDeallocated" -and $currentStatus -ne "deallocated")
	{
        if($Simulate)
        {
            Write-Warning "[$($vm.Name)]: SIMULATION -- Would have stopped VM. (No action taken)"
        }
        else
        {
            Write-Warning "[$($vm.Name)]: Stopping VM"
            Stop-AzVM -Id $vm.Id -Force
        }
	}

    # Otherwise, current power state is correct
    else
    {
        Write-Warning "[$($vm.Name)]: Current power state [$currentStatus] is correct."
    }
}

# Main runbook content
try
{
    $currentTime = (Get-Date).ToUniversalTime()
    Write-Warning "Runbook started. Version: $VERSION"
    if($Simulate)
    {
        Write-Warning "*** Running in SIMULATE mode. No power actions will be taken. ***"
    }
    else
    {
        Write-Warning "*** Running in LIVE mode. Schedules will be enforced. ***"
    }
    Write-Warning "Current UTC/GMT time [$($currentTime.ToString("dddd, yyyy MMM dd HH:mm:ss"))] will be checked against schedules"

    # Retrieve subscription name from variable asset if not specified
    if($AzureSubscriptionName -eq "Use *Default Azure Subscription* Variable Value")
    {
        $AzureSubscriptionName = Get-AutomationVariable -Name "Default Azure Subscription"
        if($AzureSubscriptionName.length -gt 0)
        {
            Write-Warning "Specified subscription name/ID: [$AzureSubscriptionName]"
        }
        else
        {
            throw "No subscription name was specified, and no variable asset with name 'Default Azure Subscription' was found. Either specify an Azure subscription name or define the default using a variable setting"
        }
    }

    # Authentication and connection
    if (-not $SkipAuth) {
        $connectionName = "AzureRunAsConnection"
        $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName
        $DummyVariable = $(Add-AzAccount -ServicePrincipal -TenantId $servicePrincipalConnection.TenantId -ApplicationId $servicePrincipalConnection.ApplicationId -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint)
        Write-Warning "Successfully logged into Azure subscription using Az cmdlets..."
    }

    # Get a list of all virtual machines in subscription
    Write-Warning "Getting all the VMs from the subscription..."
    $AllVMs = Get-AzResource -ResourceType "Microsoft.Compute/virtualMachines"

    # For each VM, determine
    #  - Is it directly tagged for shutdown
    #  - Is the current time within the tagged schedule
    # Then assert its correct power state based on the assigned schedule (if present)
    Write-Warning "Processing [$($AllVMs.Count)] virtual machines found in subscription"
    foreach($vm in $AllVMs)
    {
        $schedule = $null

        # Check for tag
        if($vm.ResourceType -eq "Microsoft.Compute/virtualMachines" -and $vm.Tags.AutoPowerSchedule)
        {
            # VM has direct tag
            $schedule = $vm.Tags.AutoPowerSchedule
            Write-Warning "[$($vm.Name)]: Found direct VM schedule tag with value: $schedule"
        }
        else
        {
            # No tag. Skip this VM.
            Write-Warning "[$($vm.Name)]: Not tagged for shutdown. Skipping this VM."
            continue
        }

        # Check that tag value was successfully obtained
        if($null -eq $schedule)
        {
            Write-Warning "[$($vm.Name)]: Failed to get tagged schedule for virtual machine. Skipping this VM."
            continue
        }

        # Parse the ranges in the Tag value. Expects a string of comma-separated time ranges, or a single time range
		$timeRangeList = @($schedule -split "," | foreach {$_.Trim()})

        # Check each range against the current time to see if any schedule is matched
		$scheduleMatched = $false
        $matchedSchedule = $null
		foreach($entry in $timeRangeList)
		{
		    if((CheckScheduleEntry -TimeRange $entry) -eq $true)
		    {
		        $scheduleMatched = $true
                $matchedSchedule = $entry
		        break
		    }
		}

        # Enforce desired state for group resources based on result.
		if($scheduleMatched)
		{
            # Schedule is matched. Shut down the VM if it is running.
		    Write-Warning "[$($vm.Name)]: Current time [$currentTime] falls within the scheduled shutdown range [$matchedSchedule]"
		    AssertVirtualMachinePowerState -VirtualMachine $vm -DesiredState "StoppedDeallocated" -Simulate $Simulate
		}
		else
		{
            # Schedule not matched. Start VM if stopped.
		    Write-Warning "[$($vm.Name)]: Current time falls outside of all scheduled shutdown ranges."
		    AssertVirtualMachinePowerState -VirtualMachine $vm -DesiredState "Started" -Simulate $Simulate
		}
    }

    Write-Warning "Finished processing virtual machine schedules"
}
catch
{
    $errorMessage = $_.Exception.Message
    throw "Unexpected exception: $errorMessage"
}
finally
{
    Write-Warning "Runbook finished (Duration: $(("{0:hh\:mm\:ss}" -f ((Get-Date).ToUniversalTime() - $currentTime))))"
}