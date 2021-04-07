# Tom Cumbow

param(
    [parameter(Mandatory=$false)]
    [bool]$SimulationOnly = $false
)

function Log ($Text)
{
	Write-Verbose -Message $Text -Verbose
}

# Define function to handle checking the ScheduleText against a given DateTime (which will probably be the current DateTime in most cases)
# This function contains nested functions so that you can collapse all the date/time logic more easily
function CheckSchedule ([string]$ScheduleText, [datetime]$CurrentDateTime)
{
	function ConvertTimeStringWithTimeZoneToUtc ([string]$DateTimeString)
	{
		if ($DateTimeString -like "*est") {$TimeZoneID = "Eastern Standard Time";$DateTimeStringCleaned = $DateTimeString.Substring(0,$DateTimeString.Length-3)}
		elseif ($DateTimeString -like "*cst") {$TimeZoneID = "Central Standard Time";$DateTimeStringCleaned = $DateTimeString.Substring(0,$DateTimeString.Length-3)}
		elseif ($DateTimeString -like "*utc") {$TimeZoneID = "UTC";$DateTimeStringCleaned = $DateTimeString.Substring(0,$DateTimeString.Length-3)}
		else {
			Write-Warning "No timezone specified, interpreting as UTC by default"
			$TimeZoneID = "UTC";$DateTimeStringCleaned = $DateTimeString
		}
		Log "Interpreted $DateTimeString as $DateTimeStringCleaned in $TimeZoneID"
		$ReturnVal = ([System.TimeZoneInfo]::ConvertTimeToUtc((Get-Date $DateTimeStringCleaned),[System.TimeZoneInfo]::FindSystemTimeZoneById($TimeZoneID)))
        Log "Which is $ReturnVal in UTC (disregard the date)"
        return $ReturnVal
	}
	function ConvertDowNumberAndTimeStringToUtcDowNumber ($DowNumber,[string]$DateTimeString,[datetime]$CurrentDateTime)
	{
        Log "ConvertDowNumber called with $DowNumber $DateTimeString $CurrentDateTime"
		if ($DateTimeString -like "*est") {$TimeZoneID = "Eastern Standard Time";$DateTimeStringCleaned = $DateTimeString.Substring(0,$DateTimeString.Length-3)}
		elseif ($DateTimeString -like "*cst") {$TimeZoneID = "Central Standard Time";$DateTimeStringCleaned = $DateTimeString.Substring(0,$DateTimeString.Length-3)}
		elseif ($DateTimeString -like "*utc") {$TimeZoneID = "UTC";$DateTimeStringCleaned = $DateTimeString.Substring(0,$DateTimeString.Length-3)}
		else {
			Write-Warning "No timezone specified, interpreting as UTC by default"
			$TimeZoneID = "UTC";$DateTimeStringCleaned = $DateTimeString
		}
		Log "Interpreted $DateTimeString as $DateTimeStringCleaned in $TimeZoneID"
        $DowOffset = $DowNumber - ((Get-Date).DayOfWeek.value__)
        $ConvertedDateTime = ([System.TimeZoneInfo]::ConvertTimeToUtc(((Get-Date $DateTimeStringCleaned)+(New-TimeSpan -days $DowOffset)),[System.TimeZoneInfo]::FindSystemTimeZoneById($TimeZoneID)))
        $ReturnVal = ($ConvertedDateTime.DayOfWeek.value__)
        return $ReturnVal
	}
	function SplitTimeRangeText ([string]$TimeRangeText)
	{
		$timeRangeComponents = $TimeRangeText -split "->" | foreach {$_.Trim()}
		if($timeRangeComponents.Count -ne 2){
			$timeRangeComponents = $TimeRangeText -split "-" | foreach {$_.Trim()}
		}
		if($timeRangeComponents.Count -ne 2) {return $null}
		$TimeRangeHT = @{ }
		$TimeRangeHT.Start = $timeRangeComponents[0]
		$TimeRangeHT.End = $timeRangeComponents[1]
		return $TimeRangeHT
	}
	$script:DayOfWeekStrings = @{ # using progressively shorter strings so when used for search/replace, it replaces as much as possible. Also, assuming we will ToLower before matching against this hashtable
		"sunday" = 0;
		"monday" = 1;
		"tuesday" = 2;
		"wednesday" = 3;
		"thursday" = 4;
		"friday" = 5;
		"saturday" = 6;
		"sun" = 0;
		"mon" = 1;
		"tues" = 2;
		"wed" = 3;
		"thurs" = 4;
		"fri" = 5;
		"sat" = 6;
		"tue" = 2;
		"thur" = 4;
		"thu" = 4;
	}
	function TimeTextStartsWithDayOfWeek ($TimeText)
	{
		foreach ($DowString in $script:DayOfWeekStrings.GetEnumerator()) {
			if ($TimeText -like "$($DowString.key) *") {
				Log "The text '$TimeText' does start with a day of the week"
				return $true
			}
		}
		Log "The text '$TimeText' does NOT start with a day of the week"
		return $false
	}
	function ValidateTimeText ($TimeText)
	{
		if (TimeTextStartsWithDayOfWeek $TimeText) {
			foreach ($DowString in $script:DayOfWeekStrings.GetEnumerator()) {
				if ($TimeText -like "$($DowString.key) *") {
					$TimeText = ($TimeText -replace("$($DowString.key) ")).Trim()
					break # only remove one day-of-week prefix because we still want to error out if they put in two day-of-week strings in there
				}
			}
		}

		$ConvertedDateTime = $null
		$ConvertedDateTime = ConvertTimeStringWithTimeZoneToUtc $TimeText
		return (-not($null -eq $ConvertedDateTime))
	}
	function InterpretTimeText ([string]$TimeText,[datetime]$CurrentDateTime)
	{
		Log "function InterpretTimeText called with TimeText: $TimeText"
		$DayOffset = 0
		if (TimeTextStartsWithDayOfWeek $TimeText) {
			foreach ($DowString in $script:DayOfWeekStrings.GetEnumerator()) {
				if ($TimeText -like "$($DowString.key) *") {
					[string]$CleanedTimeText = ($TimeText -replace("$($DowString.key) ")).Trim()
					$ConvertedDowNumber = ConvertDowNumberAndTimeStringToUtcDowNumber ($DowString.Value) $CleanedTimeText $CurrentDateTime
					$DayOffset = $ConvertedDowNumber - ($CurrentDateTime.DayOfWeek.value__)
					break # we can assume there is only one day-of-week prefix string
				}
			}
		}
		else {
			[string]$CleanedTimeText = $TimeText
		}

		return (($CurrentDateTime).Date + (New-TimeSpan -Start ((ConvertTimeStringWithTimeZoneToUtc $CleanedTimeText).Date) -End (ConvertTimeStringWithTimeZoneToUtc $CleanedTimeText)) + (New-TimeSpan -Days $DayOffset))
	}
	function TimeRangeTextIsValid ([string]$TimeRangeText)
	{
		Log "Checking validity of TimeRangeText: $TimeRangeText"

		if(-not($TimeRangeText -like "*->*" -or $TimeRangeText -like "*-*")) {
			Write-Warning "`tWARNING: Did not receive a valid time range. Check the syntax of entry, e.g. '<StartTime> -> <EndTime>'"
			return $false
		}

		$TimeRangeTextHT = SplitTimeRangeText $TimeRangeText
		if ($null -eq $TimeRangeTextHT) {
			Write-Warning "`tWARNING: Invalid time range format. Expects valid .Net DateTime-formatted start time and end time separated by '->'"
			return $false
		}

		# If a day of week is specified for one end of the time range, it should be specified for the other
		elseif ( `
			((TimeTextStartsWithDayOfWeek $TimeRangeTextHT.Start) -and -not(TimeTextStartsWithDayOfWeek $TimeRangeTextHT.End)) `
			-or `
			(-not(TimeTextStartsWithDayOfWeek $TimeRangeTextHT.Start) -and (TimeTextStartsWithDayOfWeek $TimeRangeTextHT.End)) ) {
			Write-Warning "`tWARNING: Invalid time range format. If you specify the day of week on one side, it should be specified on the other"
			return $false
		}

		# Make sure each end of the time range can be interpreted as a date/time
		elseif ((-not(ValidateTimeText $TimeRangeTextHT.Start)) -or (-not(ValidateTimeText $TimeRangeTextHT.End))) {
			Write-Warning "`tWARNING: Invalid time range format. Expects valid .Net DateTime-formatted start time and end time separated by '->'"
			return $false
		}

		else {
			Log "TimeRangeText was determined to be valid"
			return $true
		}
	}
	function CheckScheduleEntry ([string]$TimeRangeText,[datetime]$CurrentDateTime)
	{
		# Initialize variables
		Log "Interpreting time range string: $TimeRangeText"

		if(-not(TimeRangeTextIsValid $TimeRangeText)) {return $false}

		$TimeRangeHT = SplitTimeRangeText($TimeRangeText)

		[datetime]$Start = InterpretTimeText $TimeRangeHT.Start $CurrentDateTime
		Log "Interpreted start time as $Start"
		[datetime]$End = InterpretTimeText $TimeRangeHT.End $CurrentDateTime
		Log "Interpreted end time as $End"

		# Check for crossing midnight/Sunday
		if($Start -gt $End)
		{
			# If the start is later than the end, flip the two and take the logical opposite of the result
			Log "Start is later than End, so we are flipping and reversing"
			$MatchSuccess = (-not( $Start -ge $CurrentDateTime -and $End -le $CurrentDateTime ))
		}
		else
		{
			# Otherwise, just do a normal comparison
			$MatchSuccess = ($Start -le $CurrentDateTime -and $End -ge $CurrentDateTime)
		}
		if ($MatchSuccess) {Log "Matched against ScheduleEntry $TimeRangeText"}
		else {Log "Did NOT match against ScheduleEntry $TimeRangeText"}
		return $MatchSuccess
	} # End function CheckScheduleEntry
	function InsertPrefixOnBothSidesOfTimeRange ([string]$Prefix,[string]$SourceText)
	{
		$TimeRangeHT = SplitTimeRangeText $SourceText
		if ((ConvertTimeStringWithTimeZoneToUtc ($TimeRangeHT.Start) ) -gt (ConvertTimeStringWithTimeZoneToUtc ($TimeRangeHT.End))) {
			Write-Error "Cannot tolerate Start times that are greater than End times when using 'weekdays'"
			$NewText = $null
		}
		else {
			$NewText = "$Prefix $($TimeRangeHT.Start) -> $Prefix $($TimeRangeHT.End)"
		}
		return $NewText
	}

	$CurrentDateTime = $CurrentDateTime.ToUniversalTime()
    Log "Checking ScheduleText against this DateTime UTC = $($CurrentDateTime.ToString())"
    Log "ScheduleText = $ScheduleText"
    # Parse the ranges in the Tag value. Expects a string of comma-separated time ranges.
    $TimeRangeList = @($ScheduleText -split "," | foreach {$_.Trim()})
    Log "Split ScheduleText into $($TimeRangeList.Count) time ranges"

	# Check for "weekdays" prefix and, if found, explode into time ranges for M-F
	$ExplodedTimeRangeList = @()
	foreach ($entry in $TimeRangeList) {
		if ($entry -like "weekdays *") {
			Log "Exploding weekdays into ranges for M-F"
			$entryCleaned = $entry -replace("weekdays ")
			$ExplodedTimeRangeList += InsertPrefixOnBothSidesOfTimeRange "Monday" $entryCleaned
			$ExplodedTimeRangeList += InsertPrefixOnBothSidesOfTimeRange "Tuesday" $entryCleaned
			$ExplodedTimeRangeList += InsertPrefixOnBothSidesOfTimeRange "Wednesday" $entryCleaned
			$ExplodedTimeRangeList += InsertPrefixOnBothSidesOfTimeRange "Thursday" $entryCleaned
			$ExplodedTimeRangeList += InsertPrefixOnBothSidesOfTimeRange "Friday" $entryCleaned

		}
		else {
			$ExplodedTimeRangeList += $entry
		}
	}

    # Check each range against the current time to see if any schedule is matched
    $ScheduleMatched = $false
    foreach ($entry in $ExplodedTimeRangeList)
    {
        if((CheckScheduleEntry -TimeRangeText $entry -CurrentDateTime $CurrentDateTime) -eq $true)
        {
            $ScheduleMatched = $true
            break
        }
    }
	if ($ScheduleMatched) {Log "Schedule matched"} else {Log "Schedule did not match"}
	return $ScheduleMatched
}

function Get-VmPowerState ($vm)
{
    ((Get-AzVM -Name $vm.Name -ResourceGroup $vm.ResourceGroupName -Status).Statuses | where {$_.Code -like "PowerState*"} | Select -First 1 -ExpandProperty Code) -replace "PowerState/"
}
function CallChildRunbookPowerAction ($vm,$action)
{
	$parametersToPassToChildNotebook = @{}
	$parametersToPassToChildNotebook.VM = $vm
	$parametersToPassToChildNotebook.Action = $action

	Start-AzAutomationRunbook `
		-AutomationAccountName (Get-AutomationVariable -Name "Internal_AutomationAccountName") `
		-Name 'VmPowerSchedule-Child-PowerAction' `
		-ResourceGroupName (Get-AutomationVariable -Name "Internal_ResourceGroupName") `
		-Parameters $parametersToPassToChildNotebook
}
# Function to handle VM power state assertion
function AssertVirtualMachinePowerState
{
    param(
        [Object]$VirtualMachine,
        [string]$DesiredState,
        [bool]$SimulationOnly
    )
    $vm = $VirtualMachine # shorter name for this variable

    # Get VM with current status
    $currentStatus = Get-VmPowerState $vm
    Log "[$($vm.Name)]: Current power state is [$currentStatus]"

    # If should be started and isn't, start VM
	if($DesiredState -eq "Started" -and $currentStatus -notmatch "running")
	{
        if($SimulationOnly)
        {
            Write-Warning "[$($vm.Name)]: SIMULATION -- Would have started VM. (No action taken)"
        }
        else
        {
            Write-Warning "[$($vm.Name)]: Starting VM"
			CallChildRunbookPowerAction $vm "Start"
            # Start-Job {Start-AzVM -Id $Using:vm.Id}
        }
	}

	# If should be stopped and isn't, stop VM
	elseif($DesiredState -eq "StoppedDeallocated" -and $currentStatus -ne "deallocated")
	{
        if($SimulationOnly)
        {
            Write-Warning "[$($vm.Name)]: SIMULATION -- Would have stopped VM. (No action taken)"
        }
        else
        {
            Write-Warning "[$($vm.Name)]: Stopping VM"
			CallChildRunbookPowerAction $vm "Stop"
            # Start-Job {Stop-AzVM -Id $Using:vm.Id -Force}
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
    Log "Runbook started. Version: $ScriptVersion"
    if($SimulationOnly)
    {
        Log "*** Running in SIMULATE mode. No power actions will be taken. ***"
    }
    else
    {
        Log "*** Running in LIVE mode. Schedules will be enforced. ***"
    }
    Log "Current UTC/GMT time [$($currentTime.ToString("dddd, yyyy MMM dd HH:mm:ss"))] will be checked against schedules"

    # Authentication and connection
	$connectionName = "AzureRunAsConnection"
	$servicePrincipalConnection=Get-AutomationConnection -Name $connectionName
	$DummyVariable = $(Add-AzAccount -ServicePrincipal -TenantId $servicePrincipalConnection.TenantId -ApplicationId $servicePrincipalConnection.ApplicationId -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint)
	Log "Successfully logged into Azure subscription using Az cmdlets..."

    # Get a list of all virtual machines in subscription
    Log "Getting all the VMs from the subscription..."
    $AllVMs = Get-AzResource -ResourceType "Microsoft.Compute/virtualMachines"

    # For each VM, determine
    #  - Is it directly tagged for shutdown
    #  - Is the current time within the tagged schedule
    # Then assert its correct power state based on the assigned schedule (if present)
    Log "Processing [$($AllVMs.Count)] virtual machines found in subscription"
    foreach($vm in $AllVMs)
    {
        $schedule = $null
		$scheduleTypeIsShutdown = $null

        # Check for tag
		if($vm.ResourceType -eq "Microsoft.Compute/virtualMachines" -and $vm.Tags.AutoPowerSchedule)
		{
			# VM has Power tag
			$schedule = $vm.Tags.AutoPowerSchedule
			Log "[$($vm.Name)]: Found VM power schedule tag with value: $schedule"
			$scheduleTypeIsShutdown = $false
		}
        elseif($vm.ResourceType -eq "Microsoft.Compute/virtualMachines" -and $vm.Tags.AutoShutdownSchedule)
        {
            # VM has Shutdown tag
            $schedule = $vm.Tags.AutoShutdownSchedule
            Log "[$($vm.Name)]: Found VM shutdown schedule tag with value: $schedule"
			$scheduleTypeIsShutdown = $true
        }
        else
        {
            # No tag. Skip this VM.
            Log "[$($vm.Name)]: Not tagged for shutdown. Skipping this VM."
            continue
        }

        # Check that tag value was successfully obtained
        if($null -eq $schedule)
        {
            Write-Warning "[$($vm.Name)]: Failed to get tagged schedule for virtual machine. Skipping this VM."
            continue
        }

        # Call function that handles the whole interpretation of the schedule text (which contains 1 or more time ranges)
		$scheduleMatched = CheckSchedule $schedule $currentTime

		# Flip result if this is a shutdown tag
		if ($scheduleTypeIsShutdown) {$scheduleMatched = (-not $scheduleMatched)}

        # Enforce desired state for group resources based on result.
		if($scheduleMatched)
		{
			# Schedule not matched. Start VM if stopped.
			AssertVirtualMachinePowerState -VirtualMachine $vm -DesiredState "Started" -Simulate $SimulationOnly
		}
		else
		{
			# Schedule is matched. Shut down the VM if it is running.
			AssertVirtualMachinePowerState -VirtualMachine $vm -DesiredState "StoppedDeallocated" -Simulate $SimulationOnly
		}
    }

    Log "Finished processing virtual machine schedules"
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