param (
    [int]$thresholdInput # accept integer passed from command line for threshold
)

# Source variables.ps1 to get service principal and SMTP details for connecting to Azure RM
try {
    . "/usr/bin/ANFCapacityManager/linux/config.ps1"
}
catch {
    Write-Error "No credentials file was found in the path specified."
}

# Set percent full when auto grow should be triggered based on parameter input
if($thresholdInput) {
    $percentFullThreshold = $thresholdInput
}

function Send-Email ([string] $Subject, [string] $Body) {
    $Username = $smtpUsername # Your SMTP server user name
    $Password = ConvertTo-SecureString $smtpPassword -AsPlainText -Force # SendGrid password
    $credential = New-Object System.Management.Automation.PSCredential $Username, $Password
    Send-MailMessage -smtpServer $smtpServer -Credential $credential -Usessl -Port 587 -from $emailFrom -to $emailTo -subject $Subject -Body $Body -BodyAsHtml -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
}

try {
    # Connect to Azure RM using VM managed identity
    Connect-AzAccount -Identity
}
catch {
    # Connect to Azure RM using service principal credentials
    $passwd = ConvertTo-SecureString $sppasswd -AsPlainText -Force # service principal Password
    $psCredential = New-Object System.Management.Automation.PSCredential($spid, $passwd)
    Connect-AzAccount -ServicePrincipal -Credential $psCredential -Tenant $tenantId -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
}

$date = Get-Date -Format yyyyMMddTHHmmss
$logfile = $logFilePath
$dfout = Invoke-Command -ScriptBlock { df --output=source,pcent --type=nfs }
$hostname = Invoke-Command -ScriptBlock { hostname }
$allANFVolumes = Get-AzResource | Where-Object {$_.ResourceType -like 'Microsoft.NetApp/netAppAccounts/capacityPools/volumes'}
$processedVolumes = @()
foreach($volume in $dfout | where-object {$_ -notlike "File*"}) { # -notlike omits the column header row
    $volumeDetails = $volume -split '\s+' # splits the row at one or more spaces
    $volumePath = $volumeDetails[0] # grabs the first element which is IP and volume path
    $volumePercent = $volumeDetails[1].split('%')[0] # define volume current percent full as integer
    $volumePathDetails = $volumePath -split ':/' # splits the volume path in two, IP and volume path
    try {
        [ipaddress]$volumePathDetails[0]
        $volumePathIP = $volumePathDetails[0]
    }
    catch {
        $hostToIP = Invoke-Command -ScriptBlock { host -t a $volumePathDetails[0] }
        write-host $hostToIP
        $volumePathIP = $hostToIP.split(' ')[3]
    }
    $logentry = $date + ',' + $volumePath + ',' + $volumePercent # defines the log entry
    Add-Content $logfile $logentry # adds the log entry
    $volumeName = ($volumePathDetails[1] -split '/')[0]
    $volumeIPandName = $volumePathIP + ':/' + $volumeName # removes any nested folders

    # check if the percent consumed is greater or equal to the threshold and check if the volume has already been processed, this catches volumes that may be mounted twice because of nested subdirectories
    if($volumePercent -ge $percentFullThreshold -and $volumeIPandName -notin $processedVolumes) { 
        $processedVolumes += $volumeIPandName # add this volume to the processed volumes array

        # loop through all of the volumes in Azure to find a match based on the volume name from df
        foreach ($ANFVolume in $allANFVolumes | where-object {$_.ResourceId -like "*$volumeName"}) {
            $ANFVolumeDetails = Get-AzNetAppFilesVolume -ResourceId $ANFVolume.ResourceId # get the ANF volume details
            if($ANFVolumeDetails.MountTargets[0].IpAddress -eq $volumePathIP) {
                if($ANFVolumeDetails.Tags.anfcapacitymanager_autogrow_maxgib) {
                    $maxVolumeThreshold = $ANFVolumeDetails.Tags.anfcapacitymanager_autogrow_maxgib
                } else {
                    $maxVolumeThreshold = $defaultVolumeMaxGib
                }
                if($maxVolumeThreshold -gt 0 -and $ANFVolumeDetails.UsageThreshold/1024/1024/1024 -lt $maxVolumeThreshold) {
                    $payload = '{"data":{"essentials":{"signalType":"Metric","monitorCondition":"Fired","alertTargetIDs":["' + $ANFVolume.ResourceId + '"]}}}'
                    Invoke-WebRequest -URI $ANFCapacityManagerURI -Method POST -ContentType 'application/json' -Body $payload
                    $logentry = $date + ',' + $ANFVolume.ResourceId + ',CallANFCapacityManagerLogicApp'
                    Add-Content $logfile $logentry
                    $AlertSubject = 'ANFCapacityManager: Volume Autogrow Trigger: ' + $volumeName + ' on ' + $hostname
                    $AlertBody = '<h3>ANFCapacityManager Alert Notification</h3><h4>Volume Autogrow Trigger</h4><ul><li>Hostname: ' + $hostname + '</lu>' + '<li>Mount path: ' + $volumePath + '</li><li>Percent full: ' + $volumePercent + '</li><li>Current volume size: ' + $ANFVolumeDetails.UsageThreshold/1024/1024/1024 + ' GiB</li><li>Volume resource Id: <a href="https://portal.azure.com/#@/resource/' + $ANFVolume.ResourceId + '">' + $ANFVolume.ResourceId + '</a></li></ul><p><small><a href="https://github.com/ANFTechTeam/ANFCapacityManager">ANFCapacityManager</a> created by <a href="https://github.com/seanluce">Sean Luce, NetApp</a></small></p>'
                    Send-Email $AlertSubject $AlertBody
                } else {
                    $logentry = $date + ',' + $ANFVolume.ResourceId + ',MaxAutogrowGiBReached,' + $maxVolumeThreshold
                    Add-Content $logfile $logentry
                    $AlertSubject = "ANFCapacityManager: Volume Max Size Reached: " + $volumeName + " on " + $hostname
                    $AlertBody = '<h3>ANFCapacityManager Alert Notification</h3><h4>Volume Max Size Reached</h4><ul><li>Hostname: ' + $hostname + '</lu>' + '<li>Mount path: ' + $volumePath + '</li><li>Percent full: ' + $volumePercent + '</li><li>Current volume size: ' + $ANFVolumeDetails.UsageThreshold/1024/1024/1024 + ' GiB</li><li>Volume resource Id: <a href="https://portal.azure.com/#@/resource/' + $ANFVolume.ResourceId + '">' + $ANFVolume.ResourceId + '</a></li></ul><p><small><a href="https://github.com/ANFTechTeam/ANFCapacityManager">ANFCapacityManager</a> created by <a href="https://github.com/seanluce">Sean Luce, NetApp</a></small></p>'
                    Send-Email $AlertSubject $AlertBody
                }
            }
        }
    }
}