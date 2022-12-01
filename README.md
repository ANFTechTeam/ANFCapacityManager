
# ANFCapacityManager

<img src="./img/anficon.png" align="left" alt="" height="50" style="margin: 0 0 0 0; " />
<img src="./img/10201-icon-service-Logic-Apps.svg" alt="" height="50" style="margin: 0 0 0 0; " /> 

**An Azure Logic App that manages capacity based alert rules and automatically increases volume sizes to prevent your Azure NetApp Files volumes from running out of space.**

## **Disclaimer**

**This logic app (ANFCapacityManager) is provided as is and is not supported by NetApp or Microsoft. You are encouraged to modify to fit your specific environment and/or requirements. It is strongly recommended to test the functionality before deploying to any business critical or production environments.**

## Change Log

* Nov 30, 2022 - Added support for ['Agent mode'](./linux/README.md). Agent mode measures volume utilization from the host and significantly reduces auto grow response time.
* Nov 30, 2022 - Added support for volume specific thresholds via volume tags. See [Volume Tags](#volume-tags) below for more information.
* Sep 20, 2021 - Fixed bug that required SMBFQDN field that doesn't always exist
* Sep 20, 2021 - Fixed bug that incorrectly calculated the new volume size when using percent based autogrow 
* Jul 27, 2021 - Increased v3.1 -> v4.0
* Jul 27, 2021 - Added separate alert for Volume full warning only. Use this value to notify your team without automatically growing the volume.
* Jul 26, 2021 - Auto Grow amount now accepts percent-based values (20%) or static values with 't' for 'g'. i.e. '500g' to grow by 500 GiB or '2t' to grow by 2 TiB.
* Apr 16, 2021 - Added NetApp Account name to metric rule names to guarantee resource name uniqueness.
* Apr 12, 2021 - Added logic to check if pool resize is complete before attempting to resize volume. Changed 'put' methods to 'patch' to avoid wiping out tags and snapshot policies.
* Mar 14, 2021 - CRR Source Volumes; added logic to autogrow function to increase CRR target capacity pool if required. Logic App will need contributor access to target volume's resource group.
* Mar 03, 2021 - Change volume metric from "Volume Consumed Size" to "Percentage Volume Consumed Size"

## Alert Rule Management

* When an Azure NetApp Files Capacity Pool or Volume is created, ANFCapacityManager creates 2 metric alert rules based on the specified percent consumed threshold separately for warning and autogrow. If you do not wish to have a warning email, you can set the threshold to '0'.
* When an Azure NetApp Files Capacity Pool or Volume is resized, ANFCapacityManager modifies the metric alert rule based on the specified percent capacity consumed threshold. If the alert rule does not exist, it will be created.
* When an Azure NetApp Files Capacity Pool or Volume is deleted, the corresponding metric alert rule will be deleted.

## Capacity Management

* Optionally, when an Azure NetApp Files Volume reaches the specified percent consumed threshold, the volume quota (size) will be increased by the percent specified between 10-100%.
* If increasing the volume size exceeds the capacity of the containing capacity pool, the capacity pool size will also be increased to accomodate the new volume size.
* Because CRR target volumes will be increased to match the source, ANFCapacityManager will now verify there is sufficient space in the target volume's capacity pool and increase capacity as needed.
* For an exmaple of how this works, click [here](./ResizeWorkflow.md).

## Prerequisites and Permissions

* The logic app's managed identity will need 'contributor' access to your ANF resrouce group (or subscription) and 'contributor' access to the resource group where it will be creating the alerts as well as the resource group it is deployed to.
* You will need to have an alert action group already created prior to installing the logic app. This action group will be associated with all capacity based alerts that get created by the logic app. This action group is triggered when a capacity pool or volume has reached the specified full threshold. This alert action group should likely notify the appropriate people via email or SMS.

## Volume Tags

There are 4 volume tags that can be used to control the behavior of ANFCapacityManager:

* **anfcapacitymanager_threshold_grow**
    - integer value representing a percentage (no '%' symbol)
    - if set, will override the default value for that volume only, at what percent full should this volume trigger auto grow
* **anfcapacitymanager_threshold_warn**
    - integer value representing a percentage (no '%' symbol)
    - if set, will override the default value for that volume only, at what percent full should this volume send a warning to the action group
* **anfcapacitymanager_autogrow_value**
    - this can be in any of the following formats: '20%', '100g', '1t'
    - if set, will override the default auto grow ammount for that volume only, by how much should the volume auto grow
    - if set to 0, volume auto grow is disabled for that volume only
* **anfcapacitymanager_autogrow_maxgib**
    - integer value represented GiBs, i.e. '500'
    - if set, will limit the max volume size a volume can auto grow to
    - if unset, the volume will grow up to the volume maximum size as allowed by the Azure NetApp Files service
    - if set to 0, volume auto grow is disabled for that volume only

## Installation

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FANFTechTeam%2FANFCapacityManager%2Fmaster%2Fanfcapacitymanager.json)

[![Deploy to Azure Gov](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazuregov.svg)](https://portal.azure.us/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FANFTechTeam%2FANFCapacityManager%2Fmaster%2Fanfcapacitymanager_usgov.json)

## **IMPORTANT: Follow all installation steps completely!**  

1. Create an [action group](https://learn.microsoft.com/azure/azure-monitor/alerts/action-groups?ocid=AID754288&wt.mc_id=CFID0448) that will be used to alert you or your team when a volume or capacity pool has reached the target threshold. You may skip this step if you arelady have action group that you would like to use.

2. **Click the button above to deploy the ANFCapacityManager logic app** Complete the following fields:
   * **Subscription** - this is the subscription where the logic will be deployed
   * **Resource group** - this is where the Logic App will be deployed.
   * **Region** - this is the region where the logic app will be deployed, leave as default to use same region as the resource group selected
   * **Logic App Name** - any name you would like, the default is recommended.
   * **Location** - this is the region where the logic app will be deployed, leave as default to use same region as the resource group selected
   * **Target Resource Group for Alerts** - new alerts will be created in this resource group.
   * **Target Resource Group to Monitor** - leave this field blank to monitor your entire subscription.
   * **Capacity Pool Percent Full Threshold** - This determines the consumed threshold that triggers an alert for capacity pools. A value of 90 would cause an alert to be triggered when the capacity pool reaches 90% consumed.
   * **Volume Percent Grow Threshold** - This determines the consumed threshold that triggers an alert for volumes and triggers auto grow. A value of 80 would cause an alert to be triggered and the auto grow function to be triggered when the volume reaches 80% consumed.
   * **Volume Percent Warn Threshold** - This determines the consumed threshold that triggers an alert for volumes. A value of 70 would cause an alert to be triggered when the volume reaches 70% consumed.
   * **Existing Action Group Resource Group** - this is the resource group that contains your **_existing_** Action Group.
   * **Existing Action Group for Capacity Notifications** - this is the action group that will be triggered for capacity based alerting. This should be pre-created by you. This action group could send email/sms, or anything else you would like.
   * **Auto Grow Amount** - Percent of the existing volume size or GiB (g) or TiB (t) to automatically grow a volume if it reaches the % Full Threshold specified above. A value of 0 (zero) will disable the AutoGrow feature.
   * **Agent Mode** - leave set to '@false' unless using [ANFCapacityManager Agent](/linux/README.md)

3. **Give the logic app's managed identity permissions to read, create, and modify resources within your environment:** Navigate to Resource groups, choose the resource group that you specified for 'Target Resource Group for Alerts'. Choose 'Access control (IAM)' from the menu. Click the '+ Add' button and choose 'Add role assignment'. For the 'Role', choose Contributor. For 'Assign access to', choose Logic App, now select 'ANFCapacityManager' (or the name you specified in step 1). Finally, click the 'Save' button. **Repeat as needed to give the logic app the required access:**
   * **Resource Group containing ANFCapacityManager**: 'Contributor'
   * **Resource Group where Alert Rules will be created**: 'Contributor'
   * **Subscription (or Resource Group) being monitored**: 'Contributor'

   ![Add Role to RG](./img/addrole.png)
   <img src="./img/chooselogicapp.png" alt="" height="350" style="margin: 0 0 0 0; " />

4. **IMPORTANT: Run the logic app manually to build the supporting resources:** Navigate to your Logic App and choose Run Trigger, Manual. Running the Logic App manually kicks off a special workflow that does the following:
   * Creates an Action Group called '**ANF_LogicAppTrigger**\[_*monitor_rg]*', this action group is called when any of the four below alerts are triggered. The action group calls the logic app when a new volume or capacity pool is created, modified, or deleted.
   * Creates an Activity Log Alert rule called '**ANF_VolumeModified**\[_*monitor_rg]*' to trigger the Logic App whenever a volume is created or modified.
   * Creates an Activity Log Alert called '**ANF_PoolModified**\[_*monitor_rg]*' to trigger the Logic App whenever a capacity pool is created or modified.
   * Creates an Activity Log Alert called '**ANF_VolumeDeleted**\[_*monitor_rg]*' to trigger the Logic App whenever a volume is deleted.
   * Creates an Activity Log Alert called '**ANF_PoolDeleted**\[_*monitor_rg]*' to trigger the Logic App whenever a pool is deleted.
   * Creates capacity based metric alert rules for existing volumes and capacity pools.
  
Once ANFCapacityManager is installed successfully you should experience the following behavior: When an Azure NetApp Files Capacity Pool or Volume is created, modified, or deleted, the logic app will automatically create (or modify, or delete) a capacity based Metric Alert rule with the name '**ANF\_Pool\_*accountname*\_*poolname***' or '**ANF\_Vol\_*accountname*\_*poolname*\_*volname***'. In addition, if you provided a value greater than 0 (zero) for the '**Auto Grow Amount**' field, the logic app will automatically increase the volume capacity by the percent specified if a volume reaches the consumed threshold.'

## Modifying Alert Thresholds and AutoGrow Amount

You can modify the ANFCapacityManager capacity thresholds and auto grow values as needed after deployment: Navigate back to the logic app, and select 'Logic app designer' from the left hand menu.

Modify the 4 variables as required:

* **Set Capacity Pool Alert Percentage (consumed)** - this determines when capacity pool alerts are sent
* **Set Volume Alert Percentage (consumed)** - this determines when volume auto grow events are triggered
* **Set Volume Alert Warning Percentage (consumed)** - this determines when volume alerts are sent
* **Set Volume AutoGrow Value** - this determines by how much volumes are grown; 20%, 2g, 1t as examples

**Trigger a manual run of the Logic App.** This will modify all of the existing metric alert rules based on the new values specified.

<img src="./img/modifythresholds.png" alt="" height="600" style="margin: 0 0 0 0; " />

Please reach out if you have any questions or feature requests.

I'd love to hear what you think of this logic app. Say hello on [Twitter](https://twitter.com/seanluce).
