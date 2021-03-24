function Log ([switch]$Warning,[switch]$Error,[string]$Text) {
	Write-Host $Text
}

# Past function CheckSchedule here

CheckSchedule "weekdays 1:00AM EST -> 5:00AM EST" (get-date)