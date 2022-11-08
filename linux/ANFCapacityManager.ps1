$spid = '' #Service Principal Id
$passwd = ConvertTo-SecureString '' -AsPlainText -Force #Service Principal Password
$pscredential = New-Object System.Management.Automation.PSCredential($spid, $passwd)
Connect-AzAccount -ServicePrincipal -Credential $pscredential -Tenant '' -ErrorAction SilentlyContinue -WarningAction SilentlyContinue #Your Tenant Id
$percentFullThreshold = 2
$date = Get-Date -Format "MM/dd/yyyyHH:mm"
$logfile = '/tmp/anfcapacitymanager/check.log'
$dfout = Invoke-Command -ScriptBlock { df --output=source,pcent --type=nfs }
$ANFCapacityManagerURI = ''
$allANFVolumes = Get-AzResource | ? {$_.ResourceType -like 'Microsoft.NetApp/netAppAccounts/capacityPools/volumes'}
foreach($volume in $dfout | where-object {$_ -notlike "File*"}) {
    $volumeDetails = $volume -split '\s+'
    $volumePath = $volumeDetails[0]
    $volumePercent = $volumeDetails[1].split('%')[0]
    $volumePathDetails = $volumePath -split ':/'
    $volumePathIP = $volumePathDetails[0]
    $logentry = $date + ',' + $volumePath + ',' + $volumePercent
    Add-Content $logfile $logentry
    if($volumePercent -ge $percentFullThreshold) {
    $volumeName = $volumePathDetails[1]
    foreach ($ANFVolume in $allANFVolumes | where-object {$_.ResourceId -like "*$volumeName"}) {
        $ANFVolumeDetails = Get-AzNetAppFilesVolume -ResourceId $ANFVolume.ResourceId
            if($ANFVolumeDetails.MountTargets[0].IpAddress -eq $volumePathIP) {
                if($ANFVolumeDetails.Tags.anfcapacitymanager_autogrow_maxgib) {
                    $maxVolumeThreshold = $ANFVolumeDetails.Tags.anfcapacitymanager_autogrow_maxgib
                } else {
                    $maxVolumeThreshold = 0
                }
                if($maxVolumeThreshold -gt 0 -and $ANFVolumeDetails.UsageThreshold/1024/1024/1024 -lt $maxVolumeThreshold) {
                    $payload = '{"data":{"essentials":{"signalType":"Metric","monitorCondition":"Fired","alertTargetIDs":["' + $ANFVolume.ResourceId + '"]}}}'
                    Invoke-WebRequest -URI $ANFCapacityManagerURI -Method POST -ContentType 'application/json' -Body $payload
                    $logentry = $date + ',' + $ANFVolume.ResourceId + ',CallANFCapacityManagerLogicApp'
                    Add-Content $logfile $logentry
                } else {
                    $logentry = $date + ',' + $ANFVolume.ResoureId + ',MaxAutogrowGiBReached,' + $maxVolumeThreshold
                    Add-Content $logfile $logentry
                }
            }
        }
    }
}