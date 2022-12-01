# ANFCapacityManager Agent

**ANFCapacityManager Agent** is a PowerShell script that measures volume utilization from a linux host and triggers the ANFCapacityManager logic app to perform volume auto grow events. Measuring volume utilization from the linux host greatly reduces the response time of ANFCapacityManager auto grow events.

Without **ANFCapacityManager Agent**, ANFCapacityManager relies on Azure monitor metrics to trigger auto grow events. Azure monitor metrics are commonly 10-15 minutes behind the actual value measured from the hosts. Because of this delay, the speed at which data is being written to the Azure NetApp Files volume combined with limited free space may result in the volume becoming full before ANFCapacityManager is able to be triggered.

**ANFCapacityManager Agent** eliminates the dependency on Azure monitor metrics.

## How does it work?

The ANFCapacityManager Agent script collects volume utilization via the 'df' command for all network file systems (NFS) connected to the host. When it detects a volume's utilization is above the specified threshold it uses 'Get-AzResource' and 'Get-AzNetAppFilesVolume' to determine which Azure NetApp Files volume is mounted and then calls the ANFCapacityManager logic app to automatically grow the volume by the specified amount. 

## Why PowerShell?

PowerShell on Linux works great and it makes interacting with Azure very simple. Using PowerShell allows me to use the same language for agents on both Linux and Windows.

If PowerShell is not a good fit for your environment or use case, please feel free to write an agent in your language of choice and submit a PR to get it added to the repo.

## Installation

### 1. Deploy the ANFCapacityManager logic app

#### Permissions

The ANFCapacityManager logic app's managed identity will need write permissions on your Azure NetApp Files volumes. This is required for volume auto grow to function. You can give the logic app's managed identity the 'contributor' role or create a custom role.

#### Steps to deploy the ANFCapacityManager logic app

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FANFTechTeam%2FANFCapacityManager%2Fmaster%2Fanfcapacitymanager.json)

1. Click the button above to deploy the ANFCapacityManager logic app, the following fields will be presented to you:
    * **Subscription** - this is the subscription where the logic will be deployed
    * **Resource group** - this is the resource group where the logic app will be deployed
    * **Region** - this is the region of the resource group selected
    * **Logic App Name** - any name you would like, it is recommended to add the suffix '_AgentMode'.
    * **Location** - this is the region where the logic app will be deployed, leave as default to use same region as the resource group selected
    * **Target Resource Group for Alerts** - leave this field blank
    * **Target Resource Group to Monitor** - leave this field blank
    * **Capacity Pool Percent Full Threshold** - leave this field blank
    * **Volume Percent Grow Threshold** - leave this field blank
    * **Volume Percent Warn Threshold** - leave this field blank
    * **Existing Action Group Resource Group** - leave this field blank
    * **Existing Action Group for Capacity Notifications** - leave this field blank
    * **Auto Grow Amount** - Percent (%) of the existing volume size or GiB (g) or TiB (t) to automatically grow a volume if it reaches the % Full Threshold specified above. A value of 0 (zero) will disable the auto grow functionality.
    * **Agent Mode** - Set to '@true'

2. Retrieve the logic app's webhook URI by navigating to the logic app and clicking 'Logic app designer', click on the first box to expand it, and finally click on the copy to clipboard icon.

<img src="./img/webhookuri.png" alt="" height="300" style="margin: 0 0 0 0; " />

### 2. Deploy the ANFCapacityManager Agent script

#### Permissions

The ANFCapacityManager Agent script requires read access to your Azure subscription. By default, the script will attempt to use the host's managed identity to authenticate. For this to work, enable the virtual machine's managed identiy and give it read access to your Azure subscription. Alternatively, you can use service principal credentials to authenticate. Using the virtual machines's managed identity is the preferred method.

#### Steps to deploy the ANFCapacityManager Agent script

**From a Linux host where Azure NetApp Files volumes are mounted**
1. [Install PowerShell v7.2.x](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux?view=powershell-7.2)
    1. PowerShell v7.3 has not been tested and may not work correctly
1. Start PowerShell `sudo pwsh`
1. [Install the Azure Az PowerShell module](https://learn.microsoft.com/powershell/azure/install-az-ps)
1. [Install the Az.NetAppFiles PowerShell module](https://www.powershellgallery.com/packages/Az.NetAppFiles)
1. Return to regular shell `exit`
1. Change directory to /usr/bin `cd /usr/bin`
1. Git clone this repo `git clone https://github.com/ANFTechTeam/ANFCapacityManager.git`
1. Change directory to /usr/bin/ANFCapacityManager/linux `cd /usr/bin/ANFCapacityManager/linux`
1. Copy the sample config file to config.ps1 `cp config.ps1.sample config.ps1`
1. Modify the config file using vi or your favorite text editor `vi config.ps1`
1. Make sure to paste in your logic app's webhook URI
1. Scheduled the script to run via [cron](https://help.ubuntu.com/community/CronHowto)
    1. `crontab -e` to edit the crontab file
    2. `* * * * * pwsh /usr/bin/ANFCapacityManager/linux/ANFCapacityManager.ps1` 
    1. These settings trigger the script to run every minute, adjust the schedule as needed.
    1. `crontab -l` to view/confirm the crontab file

If things are working correctly, you should see new lines in the /var/logs/ANFCapacityManager.log file.

You can run the agent manually to verify it is working correctly: `sudo pwsh /usr/bin/ANFCapacityManager/linux/ANFCapacityManager.ps1`

## Email Notifications

Email notifications depend on an SMTP relay. Configure the SMTP settings in the config (config.ps1) file. 

The ANFCapacityManager Agent will send Email notifications for the following events:
- Volume Autogrow Trigger, sent when a volume has reached the specified full threshold and the ANFCapacityManager logic app has been called
- Volume Max Size Reached, sent when a volume has reached the specified full threshold and has already reached the maximum size specified

## Logs

Logs are written to '/var/logs/ANFCapacityManager.log' by default. The ANFCapacityManager Agent script logs volume utilization, when the ANFCapacityManager logic app is triggered, and when a volume has reached the maximum auto grow threshold.

### Log Retention

By default, each log file can grow up to 10MB. When the log file reaches 10MB, it is renamed to 'ANFCapacityManager.log.1'. If 'ANFCapacityManager.log.1' exists, it is first renamed to 'ANFCapacityManager.log.2', and so on. By default, 5 log files are retained:

- ANFCapacityManager.log
- ANFCapacityManager.log.1
- ANFCapacityManager.log.2
- ANFCapacityManager.log.3
- ANFCapacityManager.log.4

The log file size and number of log files retained can be modified via the config (config.ps1) file. 