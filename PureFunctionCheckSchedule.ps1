[CmdletBinding()]
param (
    [string]$ScriptScheduleText,
    [datetime]$ScriptCurrentDateTime
)

function Main
{
    return CheckSchedule $ScriptScheduleText $ScriptCurrentDateTime
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
	foreach ($DOWstring in $script:DayOfWeekStrings.GetEnumerator()) {
		if ($TimeText -like "$($DOWstring.key) *") {return $true}
	}
	return $false
}
function ValidateTimeText ($TimeText)
{
	if (TimeTextStartsWithDayOfWeek $TimeText) {
		foreach ($DOWstring in $script:DayOfWeekStrings.GetEnumerator()) {
			if ($TimeText -like "$($DOWstring.key) *") {
				$TimeText = ($TimeText -replace("$($DOWstring.key) ")).Trim()
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
	Write-Verbose "function InterpretTimeText called with TimeText: $TimeText"
	$DayOffset = 0
	if (TimeTextStartsWithDayOfWeek $TimeText) {
		foreach ($DOWstring in $script:DayOfWeekStrings.GetEnumerator()) {
			if ($TimeText -like "$($DOWstring.key) *") {
				$DayOffset = $DOWstring.Value - ($CurrentDateTime.DayOfWeek.value__)
				[string]$CleanedTimeText = ($TimeText -replace("$($DOWstring.key) ")).Trim()
				break # we can assume there is only one day-of-week prefix string
			}
		}
	}
	else {
		[string]$CleanedTimeText = $TimeText
	}

	return (($CurrentDateTime).Date + (New-TimeSpan -Start ((Get-Date $CleanedTimeText).Date) -End (Get-Date $CleanedTimeText)) + (New-TimeSpan -Days $DayOffset))
}
function TimeRangeTextIsValid ([string]$TimeRangeText)
{
	Write-Verbose "Checking validity of TimeRangeText: $TimeRangeText"

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
		((TimeTextStartsWithDayOfWeek $TimeRangeText.Start) -and -not(TimeTextStartsWithDayOfWeek $TimeRangeText.End)) `
		-or `
		(-not(TimeTextStartsWithDayOfWeek $TimeRangeText.Start) -and (TimeTextStartsWithDayOfWeek $TimeRangeText.End)) ) {
		Write-Warning "`tWARNING: Invalid time range format. If you specify the day of week on one side, it should be specified on the other"
		return $false
	}

	# Make sure each end of the time range can be interpreted as a date/time
	elseif ((-not(ValidateTimeText $TimeRangeTextHT.Start)) -or (-not(ValidateTimeText $TimeRangeTextHT.End))) {
		Write-Warning "`tWARNING: Invalid time range format. Expects valid .Net DateTime-formatted start time and end time separated by '->'"
		return $false
	}

	else {
		Write-Verbose "TimeRangeText was determined to be valid"
		return $true
	}
}

# Define function to check current time against specified range
function CheckScheduleEntry ([string]$TimeRangeText,[datetime]$CurrentDateTime)
{
	# Initialize variables
	$rangeStart, $rangeEnd, $parsedDay = $null
	$midnight = $CurrentDateTime.AddDays(1).Date
    Write-Verbose "Interpreting time range string: $TimeRangeText"

	if(-not(TimeRangeTextIsValid $TimeRangeText)) {return $false}

	$TimeRangeHT = SplitTimeRangeText($TimeRangeText)

	$Start = InterpretTimeText($TimeRangeHT.Start,$CurrentDateTime)
	Write-Verbose "Interpreted start time as $Start"
	$End = InterpretTimeText($TimeRangeHT.End,$CurrentDateTime)
	Write-Verbose "Interpreted end time as $End"

	# Check for crossing midnight/Sunday
	if($rangeStart -gt $rangeEnd)
	{
		# If the start is later than the end, flip the two and take the logical oposite of the result
		return (-not( $Start -ge $CurrentDateTime -and $End -le $CurrentDateTime ))
	}
	else
	{
		# Otherwise, just do a normal comparison
		return ($Start -le $CurrentDateTime -and $End -ge $CurrentDateTime)
	}
} # End function CheckScheduleEntry

function CheckSchedule ([string]$ScheduleText, [datetime]$CurrentDateTime)
{
    Write-Verbose "Checking ScheduleText against this DateTime UTC = $($CurrentDateTime.ToUniversalTime().ToString())"
    Write-Verbose "ScheduleText = $ScheduleText"
    # Parse the ranges in the Tag value. Expects a string of comma-separated time ranges, or a single time range
    $TimeRangeList = @($ScheduleText -split "," | foreach {$_.Trim()})
    Write-Verbose "Split ScheduleText into $($TimeRangeList.Count) time ranges"

    # Check each range against the current time to see if any schedule is matched
    $ScheduleMatched = $false
    $WhichScheduleMatched = $null
    foreach($entry in $TimeRangeList)
    {
        if((CheckScheduleEntry -TimeRangeText $entry -CurrentDateTime $CurrentDateTime) -eq $true)
        {
            Write-Verbose "Checking against time range string: $entry"
            $ScheduleMatched = $true
            $WhichScheduleMatched = $entry
            break
        }
    }
	if ($ScheduleMatched) {Write-Verbose "Schedule matched"} else {Write-Verbose "Schedule did not match"}
	return $ScheduleMatched
}

return Main