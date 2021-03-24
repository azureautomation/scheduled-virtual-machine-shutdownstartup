function Log ([switch]$Warning,[switch]$Error,[string]$Text) {
	Write-Host $Text
}
function CheckSchedule ([string]$ScheduleText, [datetime]$CurrentDateTime)
{
	function ConvertTimeStringWithTimeZoneToUtc ([string]$DateTimeString)
	{
		if ($DateTimeString -like "*est") {$TimeZoneID = "Eastern Standard Time";$DateTimeStringCleaned = $DateTimeString.Substring(0,$DateTimeString.Length-3)}
		elseif ($DateTimeString -like "*cst") {$TimeZoneID = "Central Standard Time";$DateTimeStringCleaned = $DateTimeString.Substring(0,$DateTimeString.Length-3)}
		elseif ($DateTimeString -like "*utc") {$TimeZoneID = "UTC";$DateTimeStringCleaned = $DateTimeString.Substring(0,$DateTimeString.Length-3)}
		else {
			Log -Warning "No timezone specified, interpreting as UTC by default"
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
			Log -Warning "No timezone specified, interpreting as UTC by default"
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
	$NextDayOfWeek = @{
		"Monday" = "Tuesday";
		"Tuesday" = "Wednesday";
		"Wednesday" = "Thursday";
		"Thursday" = "Friday";
		"Friday" = "Saturday";
		"Saturday" = "Sunday";
		"Sunday" = "Monday"
	}
	function InsertPrefixOnBothSidesOfTimeRange ([string]$Prefix,[string]$SourceText)
	{
		$TimeRangeHT = SplitTimeRangeText $SourceText
		if ((Get-Date ($TimeRangeHT.Start)) -gt (Get-Date ($TimeRangeHT.End))) {
			Write-Host "--------------"
			$PrefixPlusOneDay = $NextDayOfWeek[$Prefix]
			Write-Host $PrefixPlusOneDay
			$NewText = "$Prefix $($TimeRangeHT.Start) -> $PrefixPlusOneDay $($TimeRangeHT.End)"
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
		Write-Host "asdf $entry"
		if ($entry -like "weekdays *") {
			Write-Host "blarg"
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

CheckSchedule "weekdays 11:00PM EST -> 2:00AM EST" (get-date)