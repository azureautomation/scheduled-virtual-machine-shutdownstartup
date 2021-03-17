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
	TimeRangeHT.Start = $timeRangeComponents[0]
	TimeRangeHT.End = $timeRangeComponents[1]
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
				$TimeText = $TimeText -replace("$($DOWstring.key) ")
				break # only remove one day-of-week prefix because we still want to error out if they put in two day-of-week strings in there
			}
		}
	}

	$ConvertedDateTime = $null
	$ConvertedDateTime = Get-Date -Date $TimeText
	return (-not($null -eq $ConvertedDateTime))
}

function TimeRangeTextIsValid ([string]$TimeRangeText)
{
	Write-Verbose "Checking validity of TimeRangeText: $TimeRangeText"

	if(-not($TimeRange -like "*->*" -or $TimeRange -like "*-*")) {
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

	try
	{
	    if(TimeRangeTextIsValid $TimeRangeText)
	    {
	        $timeRangeComponents = $TimeRange -split "->" | foreach {$_.Trim()}
	        if($timeRangeComponents.Count -eq 2)
	        {
	            $rangeStart = Get-Date $timeRangeComponents[0]
                Write-Verbose "Interpreted start time as $rangeStart"
	            $rangeEnd = Get-Date $timeRangeComponents[1]
                Write-Verbose "Interpreted end time as $rangeEnd"

	            # Check for crossing midnight
	            if($rangeStart -gt $rangeEnd)
	            {
                    # If current time is between the start of range and midnight tonight, interpret start time as earlier today and end time as tomorrow
                    if($CurrentDateTime -ge $rangeStart -and $CurrentDateTime -lt $midnight)
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
	    else
	    {
	        Write-Warning "`tWARNING: Did not receive a valid time range. Check the syntax of entry, e.g. '<StartTime> -> <EndTime>'"
			return $false
	    }
	}
	catch
	{
	    # Record any errors and return false by default
	    Write-Warning "`tWARNING: Exception encountered while parsing time range. Details: $($_.Exception.Message). Check the syntax of entry, e.g. '<StartTime> -> <EndTime>'"
	    return $false
	}

	# Check if current time falls within range
	if($CurrentDateTime -ge $rangeStart -and $CurrentDateTime -le $rangeEnd)
	{
	    return $true
	}
	else
	{
	    return $false
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