[CmdletBinding()]
param (
    [string]$ScriptScheduleText,
    [datetime]$ScriptCurrentDateTime
)

function Main
{
    return CheckSchedule $ScriptScheduleText $ScriptCurrentDateTime
}

# Define function to check current time against specified range
function CheckScheduleEntry ([string]$TimeRange,[datetime]$CurrentDateTime)
{
	# Initialize variables
	$rangeStart, $rangeEnd, $parsedDay = $null
	$midnight = $CurrentDateTime.AddDays(1).Date
    Write-Verbose "Interpreting time range string: $TimeRange"

	try Saturday 4AM -> Sunday 23:00, December 25, 17:00->07:00
	{
	    # Parse as range if contains '->'
	    if($TimeRange -like "*->*")
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
    Write-Verbose "Split SchedulText into $($TimeRangeList.Count) time ranges"

    # Check each range against the current time to see if any schedule is matched
    $ScheduleMatched = $false
    $WhichScheduleMatched = $null
    foreach($entry in $TimeRangeList)
    {
        if((CheckScheduleEntry -TimeRange $entry -CurrentDateTime $CurrentDateTime) -eq $true)
        {
            Write-Verbose "Checking against time range string: $entry"
            $ScheduleMatched = $true
            $WhichScheduleMatched = $entry
            break
        }
    }
}

return Main