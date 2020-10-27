Scheduled Virtual Machine Shutdown/Startup
==========================================

            

This runbook automates scheduled startup and shutdown of [Azure virtual machines](http://azure.microsoft.com/en-us/services/virtual-machines/). You can implement multiple granular power schedules for your virtual machines
 using simple tag metadata in the Azure portal or through PowerShell. For example, you could tag an individual VM or group of VMs to be shut down between the hours of 10:00 PM and 6:00 AM, all day on Saturdays and Sundays, and during specific days of the year,
 like December 25.


The runbook is intended to run on a schedule in an [Azure Automation](http://azure.microsoft.com/en-us/services/automation/) account, with a configured subscription and associated access credentials. For example, it can
 run once every hour, checking all the schedule [tags](http://azure.microsoft.com/en-us/documentation/articles/resource-group-using-tags/) it finds on your virtual machine or [resource groups](http://azure.microsoft.com/en-us/documentation/articles/resource-group-portal/). If the current time falls within a shutdown period you’ve defined, the runbook will stop the VM if it is running, preventing any compute charges. If the current time falls outside of any tagged shutdown period, this means the VM should be
 running, so the runbook starts any such VM that is stopped.


Once the runbook is in place and scheduled, the only configuration required can be done through simple tagging of resources, and the runbook will implement whatever power schedules it finds during its next scheduled run. Think of this as a quick and
 basic power management scheduling solution for your Azure virtual machines.

Requirements

This runbook leverages the modules available in Azure Automation accounts by default, including 'Azure' and 'AzureRM.Resources'. Ensure these have not been modified or removed. If you don't know about modules, no need to worry about this.

More Information / Documentation

More information on how to configure the runbook and shutdown schedules is available with the prerequisite downloads at this link:


**[Scheduled Virtual Machine Shutdown/Startup - Microsoft Azure](https://automys.com/library/asset/scheduled-virtual-machine-shutdown-startup-microsoft-azure)**


 

Updates

2-29-2016: Version 2.0.2. Minor bug fixed related to error messages.


2-16-2016: Version 2.0.1. Minor changes to logging output for better troubleshooting.


2-8-2016: Version 2.0 release. Complete rewrite. Added simulation mode for safe testing.


1-19-2016: Added support for both newer and classic virtual machine types


8-17-2015: Improved authentication checks and error messages


6-24-2015: Fixed issue with subscription selection


 

Contributing

If you're interested in contributing enhancements to the solution, please join at the GitHub repository below or send an email to hello@automys.com.


https://github.com/automys/Azure-Automation-Scheduled-VM-Shutdown


 


![Image](https://github.com/azureautomation/scheduled-virtual-machine-shutdownstartup/raw/master/scheduled-virtual-machine-shutdown-startup-microsoft-azure-150521024650991.png)


 


![Image](https://github.com/azureautomation/scheduled-virtual-machine-shutdownstartup/raw/master/azure-runbook-output.jpg)


 


 

 

        
    
TechNet gallery is retiring! This script was migrated from TechNet script center to GitHub by Microsoft Azure Automation product group. All the Script Center fields like Rating, RatingCount and DownloadCount have been carried over to Github as-is for the migrated scripts only. Note : The Script Center fields will not be applicable for the new repositories created in Github & hence those fields will not show up for new Github repositories.
