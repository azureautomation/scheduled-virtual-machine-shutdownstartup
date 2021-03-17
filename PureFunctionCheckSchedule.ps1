[CmdletBinding()]
param (
    [string]$ScriptScheduleText,
    [datetime]$ScriptCurrentDateTime
)

function Main
{
    return CheckSchedule $ScriptScheduleText $ScriptCurrentDateTime
}

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
				Write-Verbose "The text '$TimeText' does start with a day of the week"
				return $true
			}
		}
		Write-Verbose "The text '$TimeText' does NOT start with a day of the week"
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
		Write-Verbose "function InterpretTimeText called with TimeText: $TimeText"
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
			Write-Verbose "TimeRangeText was determined to be valid"
			return $true
		}
	}
	function CheckScheduleEntry ([string]$TimeRangeText,[datetime]$CurrentDateTime)
	{
		# Initialize variables
		Write-Verbose "Interpreting time range string: $TimeRangeText"

		if(-not(TimeRangeTextIsValid $TimeRangeText)) {return $false}

		$TimeRangeHT = SplitTimeRangeText($TimeRangeText)

		[datetime]$Start = InterpretTimeText $TimeRangeHT.Start $CurrentDateTime
		Write-Verbose "Interpreted start time as $Start"
		[datetime]$End = InterpretTimeText $TimeRangeHT.End $CurrentDateTime
		Write-Verbose "Interpreted end time as $End"

		# Check for crossing midnight/Sunday
		if($Start -gt $End)
		{
			# If the start is later than the end, flip the two and take the logical opposite of the result
			Write-Verbose "Start is later than End, so we are flipping and reversing"
			$MatchSuccess = (-not( $Start -ge $CurrentDateTime -and $End -le $CurrentDateTime ))
		}
		else
		{
			# Otherwise, just do a normal comparison
			$MatchSuccess = ($Start -le $CurrentDateTime -and $End -ge $CurrentDateTime)
		}
		if ($MatchSuccess) {Write-Verbose "Matched against ScheduleEntry $TimeRangeText"}
		else {Write-Verbose "Did NOT match against ScheduleEntry $TimeRangeText"}
		return $MatchSuccess
	} # End function CheckScheduleEntry

	$CurrentDateTime = $CurrentDateTime.ToUniversalTime()
    Write-Verbose "Checking ScheduleText against this DateTime UTC = $($CurrentDateTime.ToString())"
    Write-Verbose "ScheduleText = $ScheduleText"
    # Parse the ranges in the Tag value. Expects a string of comma-separated time ranges, or a single time range
    $TimeRangeList = @($ScheduleText -split "," | foreach {$_.Trim()})
    Write-Verbose "Split ScheduleText into $($TimeRangeList.Count) time ranges"

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
	if ($ScheduleMatched) {Write-Verbose "Schedule matched"} else {Write-Verbose "Schedule did not match"}
	return $ScheduleMatched
}

return Main