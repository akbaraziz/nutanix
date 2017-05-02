<#
.SYNOPSIS
  This script configures the HA and DRS recommended settings for Nutanix CVMs in a given cluster.
.DESCRIPTION
  This script will disable DRS, change HA restart priority to disabled, disable HA VM monitoring and change HA host isolation response to "leave powered on" for all CVMs in a given cluster or vCenter server.
.PARAMETER help
  Displays a help message (seriously, what did you think this was?)
.PARAMETER history
  Displays a release history for this script (provided the editors were smart enough to document this...)
.PARAMETER log
  Specifies that you want the output messages to be written in a log file as well as on the screen.
.PARAMETER debugme
  Turns off SilentlyContinue on unexpected error messages.
.PARAMETER vcenter
  VMware vCenter server hostname. Default is localhost. You can specify several hostnames by separating entries with commas.
.PARAMETER cluster
  (optional) Name of compute cluster. By default, all clusters in the specified vCenter will be processed.
.EXAMPLE
  Configure all CVMs in the vCenter server of your choice:
  PS> .\set-cvms.ps1 -vcenter myvcenter.local
.LINK
  http://www.nutanix.com/services
.NOTES
  Author: Stephane Bourdeaud (sbourdeaud@nutanix.com)
  Revision: October 1st 2015
#>

#region parameters
######################################
##   parameters and initial setup   ##
######################################
#let's start with some command line parsing
Param
(
    #[parameter(valuefrompipeline = $true, mandatory = $true)] [PSObject]$myParam1,
    [parameter(mandatory = $false)] [switch]$help,
    [parameter(mandatory = $false)] [switch]$history,
    [parameter(mandatory = $false)] [switch]$log,
    [parameter(mandatory = $false)] [switch]$debugme,
    [parameter(mandatory = $false)] [string]$vcenter,
	[parameter(mandatory = $false)] [string]$cluster
)
#endregion

#region functions
########################
##   main functions   ##
########################

#this function is used to output log data
Function OutputLogData 
{
	#input: log category, log message
	#output: text to standard output
<#
.SYNOPSIS
  Outputs messages to the screen and/or log file.
.DESCRIPTION
  This function is used to produce screen and log output which is categorized, time stamped and color coded.
.NOTES
  Author: Stephane Bourdeaud
.PARAMETER myCategory
  This the category of message being outputed. If you want color coding, use either "INFO", "WARNING", "ERROR" or "SUM".
.PARAMETER myMessage
  This is the actual message you want to display.
.EXAMPLE
  PS> OutputLogData -mycategory "ERROR" -mymessage "You must specify a cluster name!"
#>
	param
	(
		[string] $category,
		[string] $message
	)

    begin
    {
	    $myvarDate = get-date
	    $myvarFgColor = "Gray"
	    switch ($category)
	    {
		    "INFO" {$myvarFgColor = "Green"}
		    "WARNING" {$myvarFgColor = "Yellow"}
		    "ERROR" {$myvarFgColor = "Red"}
		    "SUM" {$myvarFgColor = "Magenta"}
	    }
    }

    process
    {
	    Write-Host -ForegroundColor $myvarFgColor "$myvarDate [$category] $message"
	    if ($log) {Write-Output "$myvarDate [$category] $message" >>$myvarOutputLogFile}
    }

    end
    {
        Remove-variable category
        Remove-variable message
        Remove-variable myvarDate
        Remove-variable myvarFgColor
    }
}#end function OutputLogData
#endregion

#region prepwork
# get rid of annoying error messages
if (!$debugme) {$ErrorActionPreference = "SilentlyContinue"}

#check if we need to display help and/or history
$HistoryText = @'
 Maintenance Log
 Date       By   Updates (newest updates at the top)
 ---------- ---- ---------------------------------------------------------------
 06/19/2015 sb   Initial release.
 09/03/2015 sb   Added disabling of HA VM Monitoring on CVM objects
 10/01/2015 sb   Added setting advanced HA cluster option
                 (das.ignoreInsufficientHbDatastore)
                 Removed requirement for Nutanix cmdlets.
################################################################################
'@
$myvarScriptName = ".\set-cvms.ps1"
 
if ($help) {get-help $myvarScriptName; exit}
if ($History) {$HistoryText; exit}



#let's make sure the VIToolkit is being used
$myvarPowerCLI = Get-PSSnapin VMware.VimAutomation.Core -Registered
try {
    switch ($myvarPowerCLI.Version.Major) {
        {$_ -ge 6}
            {
            Import-Module VMware.VimAutomation.Vds -ErrorAction Stop
            OutputLogData -category "INFO" -message "PowerCLI 6+ module imported"
            }
        5   {
            Add-PSSnapin VMware.VimAutomation.Vds -ErrorAction Stop
            OutputLogData -category "WARNING" -message "PowerCLI 5 snapin added; recommend upgrading your PowerCLI version"
            }
        default {throw "This script requires PowerCLI version 5 or later"}
        }
    }
catch {throw "Could not load the required VMware.VimAutomation.Vds cmdlets"}
#endregion

#region variables
#initialize variables
	#misc variables
	$myvarElapsedTime = [System.Diagnostics.Stopwatch]::StartNew() #used to store script begin timestamp
	$myvarvCenterServers = @() #used to store the list of all the vCenter servers we must connect to
	$myvarOutputLogFile = (Get-Date -UFormat "%Y_%m_%d_%H_%M_")
	$myvarOutputLogFile += "OutputLog.log"
#endregion

#region parameters validation
	############################################################################
	# command line arguments initialization
	############################################################################	
	#let's initialize parameters if they haven't been specified
	if (!$vcenter) {$vcenter = read-host "Enter vCenter server name or IP address"}#prompt for vcenter server name
	$myvarvCenterServers = $vcenter.Split(",") #make sure we parse the argument in case it contains several entries
    if (!$cluster) {$cluster = read-host "Enter the vSphere cluster name"}
#endregion	

#region processing
	################################
	##  foreach vCenter loop      ##
	################################
	foreach ($myvarvCenter in $myvarvCenterServers)	
	{
		OutputLogData -category "INFO" -message "Connecting to vCenter server $myvarvCenter..."
		if (!($myvarvCenterObject = Connect-VIServer $myvarvCenter))#make sure we connect to the vcenter server OK...
		{#make sure we can connect to the vCenter server
			$myvarerror = $error[0].Exception.Message
			OutputLogData -category "ERROR" -message "$myvarerror"
			return
		}
		else #...otherwise show the error message
		{
			OutputLogData -category "INFO" -message "Connected to vCenter server $myvarvCenter."
		}#endelse
		
		if ($myvarvCenterObject)
		{
		
			######################
			#main processing here#
			######################
			OutputLogData -category "INFO" -message "Retrieving CVM objects..."
			if ($cluster)
			{
				$myvarCVMs = Get-Cluster -Name $cluster | Get-VM -Name ntnx-*-cvm
                #configuring advanced HA cluster option
                OutputLogData -category "INFO" -message "Setting advanced HA cluster option das.ignoreInsufficientHbDatastore to true on $cluster..."
                New-AdvancedSetting -Type ClusterHA -entity (get-cluster -Name $cluster) -name 'das.ignoreInsufficientHbDatastore' -value true -Confirm:$false | out-null
			}
			else
			{
				$myvarCVMs = Get-VM -Name ntnx-*-cvm
			}
			
			foreach ($myvarCVM in $myvarCVMs)
			{

				OutputLogData -category "INFO" -message "Disabling DRS on $myvarCVM..."
				$myvarCVM | Set-VM -DrsAutomationLevel Disabled -Confirm:$false | Out-Null

				OutputLogData -category "INFO" -message "Changing HA restart priority on $myvarCVM..."
				$myvarCVM | Set-VM -HARestartPriority Disabled -Confirm:$false | Out-Null

				OutputLogData -category "INFO" -message "Changing HA host isolation response to 'do nothing' on $myvarCVM..."
				$myvarCVM | Set-VM -HAIsolationResponse DoNothing -Confirm:$false | Out-Null

				OutputLogData -category "INFO" -message "Disabling HA VM monitoring on $myvarCVM..."
				## get the .NET View object of the cluster, with a couple of choice properties
				$myvarViewMyCluster = Get-View -ViewType ClusterComputeResource -Property Name, Configuration.DasVmConfig -Filter @{"Name" = "^${cluster}$"}
				## make a standard VmSettings object
				$myvarDasVmSettings = New-Object VMware.Vim.ClusterDasVmSettings -Property @{
				    vmToolsMonitoringSettings = New-Object VMware.Vim.ClusterVmToolsMonitoringSettings -Property @{
				        enabled = $false
				        vmMonitoring = "vmMonitoringDisabled"
				        clusterSettings = $false
				    } ## end new-object
				} ## end new-object
				## create a new ClusterConfigSpec object with which to reconfig the cluster
				$myvaroClusterConfigSpec = New-Object VMware.Vim.ClusterConfigSpec
				## for each VM View, add a DasVmConfigSpec to the ClusterConfigSpec object
				$myvarVMView = $myvarCVM | Get-View
				## the operation for this particular DasVmConfigSpec; if a spec already exists for the cluster for this VM, "edit" it, else, "add" it
			    $myvarStrOperationForThisVM = if ($myvarViewMyCluster.Configuration.DasVmConfig | ?{($_.Key -eq $myvarVMView.MoRef)}) {"edit"} else {"add"}
			    $myvaroClusterConfigSpec.DasVmConfigSpec += New-Object VMware.Vim.ClusterDasVmConfigSpec -Property @{
			        operation = $myvarStrOperationForThisVM     ## set the operation to "edit" or "add"
			        info = New-Object VMware.Vim.ClusterDasVmConfigInfo -Property @{
			            key = [VMware.Vim.ManagedObjectReference]$myvarVMView.MoRef
			            dasSettings = $myvarDasVmSettings
			        } ## end new-object
			    } ## end new-object
				## reconfigure the cluster with the given ClusterConfigSpec for all of the VMs
				$myvarViewMyCluster.ReconfigureCluster_Task($myvaroClusterConfigSpec, $true) | Out-Null
			}
		}#endif
        OutputLogData -category "INFO" -message "Disconnecting from vCenter server $vcenter..."
		Disconnect-viserver -Confirm:$False #cleanup after ourselves and disconnect from vcenter
	}#end foreach vCenter
#endregion

#region cleanup
#########################
##       cleanup       ##
#########################

	#let's figure out how much time this all took
	OutputLogData -category "SUM" -message "total processing time: $($myvarElapsedTime.Elapsed.ToString())"
	
	#cleanup after ourselves and delete all custom variables
	Remove-Variable myvar* -ErrorAction SilentlyContinue
	Remove-Variable ErrorActionPreference -ErrorAction SilentlyContinue
	Remove-Variable help -ErrorAction SilentlyContinue
    Remove-Variable history -ErrorAction SilentlyContinue
	Remove-Variable log -ErrorAction SilentlyContinue
	Remove-Variable vcenter -ErrorAction SilentlyContinue
    Remove-Variable debugme -ErrorAction SilentlyContinue
	Remove-Variable cluster -ErrorAction SilentlyContinue
#endregion