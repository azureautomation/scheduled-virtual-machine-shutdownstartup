# Tom Cumbow

param(
    [parameter(Mandatory=$false)]
    [bool]$Simulate = $true,
    [parameter(Mandatory=$false)]
    [switch]$DevMode
)

$VERSION = "0.0.4"

if ($DevMode) {
    $GLOBAL:VerbosePreference = "Continue"
    if (-not $GLOBAL:CheckedDependenciesForVmPowerScheduleRunbook)
    {
        Install-Module Az.Resources -Scope CurrentUser
        Install-Module Az.Compute -Scope CurrentUser
        $GLOBAL:CheckedDependenciesForVmPowerScheduleRunbook = $true
    }
}

# This is a custom function for logging - this is a workaround for the failed logging in Azure Runbooks
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
	function UpsertTableEntity($TableName, $RowKey, $Entity) {
		$StorageAccount = "tcumbowdartsandbox"
		$SasToken = "?st=2021-03-21T14%3A52%3A00Z&se=2042-03-23T14%3A52%3A00Z&sp=rau&sv=2018-03-28&tn=runbooklogs&sig=jG6lhLojZ%2F74SJllghtxHuvasLiruIK0hCP%2FSJn8igY%3D"
		$version = "2017-04-17"
		$PartitionKey = ((get-date -format "yyyyMM").ToString())
		$resource = "$tableName(PartitionKey='$PartitionKey',RowKey='$RowKey')$SasToken"
		$table_url = "https://$StorageAccount.table.core.windows.net/$resource"
		$GMTTime = (Get-Date).ToUniversalTime().toString('R')
		$headers = @{
			'x-ms-date'    = $GMTTime
			"x-ms-version" = $version
			Accept         = "application/json;odata=fullmetadata"
		}
		$body = $Entity | ConvertTo-Json
		$item = Invoke-RestMethod -Method MERGE -Uri $table_url -Headers $headers -Body $body -ContentType application/json
	}

	if ($Error) {Write-Error $Text}
	elseif ($Warning) {Write-Warning $Text}
	else {Write-Verbose $Text}

	$HashTable = @{}
    $HashTable.Add("Text",$Text)
    $HashTable.Add("Level",$(if($Error){"Error"}elseif($Warning){"Warning"}else{"Verbose"}))
	$HashTable.Add("ScriptName",(Split-Path $PSCommandPath -Leaf))
	UpsertTableEntity -TableName "RunbookLogs" -RowKey ([guid]::NewGuid().ToString()) -Entity $HashTable
}

# Define function to handle checking the ScheduleText against a given DateTime (which will probably be the current DateTime in most cases)
# This function contains nested functions so that you can collapse all the date/time logic more easily
function CheckSchedule ([string]$ScheduleText, [datetime]$CurrentDateTime)
{
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
		$ConvertedDateTime = Get-Date -Date $TimeText
		return (-not($null -eq $ConvertedDateTime))
	}
	function InterpretTimeText ([string]$TimeText,[datetime]$CurrentDateTime)
	{
		Log "function InterpretTimeText called with TimeText: $TimeText"
		$DayOffset = 0
		if (TimeTextStartsWithDayOfWeek $TimeText) {
			foreach ($DowString in $script:DayOfWeekStrings.GetEnumerator()) {
				if ($TimeText -like "$($DowString.key) *") {
					$DayOffset = $DowString.Value - ($CurrentDateTime.DayOfWeek.value__)
					[string]$CleanedTimeText = ($TimeText -replace("$($DowString.key) ")).Trim()
					break # we can assume there is only one day-of-week prefix string
				}
			}
		}
		else {
			[string]$CleanedTimeText = $TimeText
		}

		$TimeText = "$TimeText -0" # So that the Get-Date statements below interpret the string as UTC
		return (($CurrentDateTime).Date + (New-TimeSpan -Start ((Get-Date $CleanedTimeText).Date) -End (Get-Date $CleanedTimeText)) + (New-TimeSpan -Days $DayOffset))
	}
	function TimeRangeTextIsValid ([string]$TimeRangeText)
	{
		Log "Checking validity of TimeRangeText: $TimeRangeText"

		if(-not($TimeRangeText -like "*->*" -or $TimeRangeText -like "*-*")) {
			Log -Warning "`tWARNING: Did not receive a valid time range. Check the syntax of entry, e.g. '<StartTime> -> <EndTime>'"
			return $false
		}

		$TimeRangeTextHT = SplitTimeRangeText $TimeRangeText
		if ($null -eq $TimeRangeTextHT) {
			Log -Warning "`tWARNING: Invalid time range format. Expects valid .Net DateTime-formatted start time and end time separated by '->'"
			return $false
		}

		# If a day of week is specified for one end of the time range, it should be specified for the other
		elseif ( `
			((TimeTextStartsWithDayOfWeek $TimeRangeTextHT.Start) -and -not(TimeTextStartsWithDayOfWeek $TimeRangeTextHT.End)) `
			-or `
			(-not(TimeTextStartsWithDayOfWeek $TimeRangeTextHT.Start) -and (TimeTextStartsWithDayOfWeek $TimeRangeTextHT.End)) ) {
			Log -Warning "`tWARNING: Invalid time range format. If you specify the day of week on one side, it should be specified on the other"
			return $false
		}

		# Make sure each end of the time range can be interpreted as a date/time
		elseif ((-not(ValidateTimeText $TimeRangeTextHT.Start)) -or (-not(ValidateTimeText $TimeRangeTextHT.End))) {
			Log -Warning "`tWARNING: Invalid time range format. Expects valid .Net DateTime-formatted start time and end time separated by '->'"
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

	$CurrentDateTime = $CurrentDateTime.ToUniversalTime()
    Log "Checking ScheduleText against this DateTime UTC = $($CurrentDateTime.ToString())"
    Log "ScheduleText = $ScheduleText"
    # Parse the ranges in the Tag value. Expects a string of comma-separated time ranges, or a single time range
    $TimeRangeList = @($ScheduleText -split "," | foreach {$_.Trim()})
    Log "Split ScheduleText into $($TimeRangeList.Count) time ranges"

    # Check each range against the current time to see if any schedule is matched
    $ScheduleMatched = $false
    foreach($entry in $TimeRangeList)
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
            Start-AzVM -Id $vm.Id | Log
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
            Stop-AzVM -Id $vm.Id -Force | Log
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
    Log "Runbook started. Version: $VERSION"
    if($Simulate)
    {
        Log "*** Running in SIMULATE mode. No power actions will be taken. ***"
    }
    else
    {
        Log "*** Running in LIVE mode. Schedules will be enforced. ***"
    }
    Log "Current UTC/GMT time [$($currentTime.ToString("dddd, yyyy MMM dd HH:mm:ss"))] will be checked against schedules"

    # Retrieve subscription name from variable asset if not specified
    if($AzureSubscriptionName -eq "Use *Default Azure Subscription* Variable Value")
    {
        $AzureSubscriptionName = Get-AutomationVariable -Name "Default Azure Subscription"
        if($AzureSubscriptionName.length -gt 0)
        {
            Log "Specified subscription name/ID: [$AzureSubscriptionName]"
        }
        else
        {
            throw "No subscription name was specified, and no variable asset with name 'Default Azure Subscription' was found. Either specify an Azure subscription name or define the default using a variable setting"
        }
    }

    # Authentication and connection
    if (-not $DevMode) {
        $connectionName = "AzureRunAsConnection"
        $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName
        $DummyVariable = $(Add-AzAccount -ServicePrincipal -TenantId $servicePrincipalConnection.TenantId -ApplicationId $servicePrincipalConnection.ApplicationId -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint)
        Log "Successfully logged into Azure subscription using Az cmdlets..."
    }

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

        # Check for tag
        if($vm.ResourceType -eq "Microsoft.Compute/virtualMachines" -and $vm.Tags.AutoShutdownSchedule)
        {
            # VM has direct tag
            $schedule = $vm.Tags.AutoShutdownSchedule
            Log "[$($vm.Name)]: Found direct VM schedule tag with value: $schedule"
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
            Log -Warning "[$($vm.Name)]: Failed to get tagged schedule for virtual machine. Skipping this VM."
            continue
        }

        # Call function that handles the whole interpretation of the text which contains 1 or more time ranges
		$scheduleMatched = CheckSchedule $schedule (Get-Date)

        # Enforce desired state for group resources based on result.
		if($scheduleMatched)
		{
            # Schedule is matched. Shut down the VM if it is running.
		    AssertVirtualMachinePowerState -VirtualMachine $vm -DesiredState "StoppedDeallocated" -Simulate $Simulate
		}
		else
		{
            # Schedule not matched. Start VM if stopped.
		    AssertVirtualMachinePowerState -VirtualMachine $vm -DesiredState "Started" -Simulate $Simulate
		}
    }

    Log "Finished processing virtual machine schedules"
}
catch
{
    $errorMessage = $_.Exception.Message
    throw "Unexpected exception: $errorMessage"
}
finally
{
    Log "Runbook finished (Duration: $(("{0:hh\:mm\:ss}" -f ((Get-Date).ToUniversalTime() - $currentTime))))"
}