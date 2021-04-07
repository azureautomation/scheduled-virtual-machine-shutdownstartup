For use in an Azure Automation Account

Requires the following modules to be imported from the gallery:
Az.Accounts
Az.Resources
Az.Compute
Az.Automation

Automatically powers on/off VMs based on a schedule

Specify the schedule for each VM by creating a tag on that VM called "AutoPowerSchedule"
The contents of the tag determines the schedule.
Examples:
08:00 AM EST -> 05:00 PM EST 
08:00est->17:00est 
8am est - 5pm EST
Weekdays 08:00 EST -> 17:00 EST
weekdays 08:00 EST -> 17:00 EST, Sunday 10AM est -> Sunday 12PM est
Weekdays 7:00 AM CST -> 6:00 PM CST, Tuesday 7:00 AM CST ->  9:00 PM CST, Sat 03:00 UTC -> Sunday 05:00 UTC