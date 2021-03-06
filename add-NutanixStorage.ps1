<#
.SYNOPSIS
  This script can be used to initialize storage on a freshly installed Nutanix cluster.
.DESCRIPTION
  This script creates a storage pool and/or a container on a Nutanix cluster.
.PARAMETER help
  Displays a help message (seriously, what did you think this was?)
.PARAMETER history
  Displays a release history for this script (provided the editors were smart enough to document this...)
.PARAMETER log
  Specifies that you want the output messages to be written in a log file as well as on the screen.
.PARAMETER debugme
  Turns off SilentlyContinue on unexpected error messages.
.PARAMETER cluster
  Nutanix cluster fully qualified domain name or IP address.
.PARAMETER username
  Username used to connect to the Nutanix cluster.
.PARAMETER password
  Password used to connect to the Nutanix cluster.
.PARAMETER storagepool
  Name of the storage pool you want to create. If no name is specified, this will default to "<cluster name>-sp1". If a storage pool already exists, the script will not create a new one.
.PARAMETER container
  Name of the container you want to create. If no name is specified, this will default to "<cluster name>-ct1".  If a container already exists, the script will create a new one assuming the specified name is unique.
.PARAMETER rf
  Specifies the replication factor (2 or 3; default used if not specified is 2).
.PARAMETER compression
  Specifies that you want to enable compression on the container (default is not enabled).
.PARAMETER compressiondelay
  Specifies the compression delay in seconds. If no compression delay is specified, then inline compression will be enabled (default is 0).
.PARAMETER dedupe
  Specifies that you want to enable post process deduplication on the container (default is not enabled).
.PARAMETER fingerprint
  Specifies that you want to enable inline fingerprinting on the container (default is not enabled).
.PARAMETER connectnfs
  Specifies that you want to mount the new container as an NFS datastore on all ESXi hosts in the Nutanix cluster (default behavior will not mount the nfs datastore)
.PARAMETER vcenter
  Hostname of the vSphere vCenter to which the hosts you want to mount the NFS datastore belong to.  This is optional.  By Default, if no vCenter server and vSphere cluster name are specified, then the NFS datastore is mounted to all hypervisor hosts in the Nutanix cluster.  The script assumes the user running it has access to the vcenter server.
.PARAMETER vcluster
  Name of the vSphere cluster with the hosts where you want to mount the NFS datastore.  This is useful to specify if you have multiple compute clusters in your Nutanix cluster and you only want to mount your NFS datastore to the hosts of a specific compute cluster.
.EXAMPLE
  Create a default storage pool and container on the specified Nutanix cluster:
  PS> .\add-NutanixStorage.ps1 -cluster ntnxc1.local -username admin -password admin
.EXAMPLE
  Create a storage pool and container on the specified Nutanix cluster and enable inline compression on the container, then mount it on all ESXi hosts:
  PS> .\add-NutanixStorage.ps1 -cluster ntnxc1.local -username admin -password admin -storagepool spool1 -container compressed1 -compression -connectnfs
.EXAMPLE
  Create a storage pool and container on the specified Nutanix cluster and mount the NFS datastore to the hosts that make up the vSphere cluster named "cluster1" and are managed by the vCenter server called "vcenter1":
  PS> .\add-NutanixStorage.ps1 -cluster ntnxc1.local -username admin -password admin -storagepool spool1 -container compressed1 -connectnfs -vcenter vcenter1.mydomain.local -vcluster cluster1
.LINK
  http://www.nutanix.com/services
.NOTES
  Author: Stephane Bourdeaud (sbourdeaud@nutanix.com)
  Revision: July 22nd 2015
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
    [parameter(mandatory = $true)] [string]$cluster,
	[parameter(mandatory = $true)] [string]$username,
	[parameter(mandatory = $true)] [string]$password,
	[parameter(mandatory = $false)] [string]$storagepool,
	[parameter(mandatory = $false)] [string]$container,
	[parameter(mandatory = $false)] [int]$rf,
	[parameter(mandatory = $false)] [switch]$compression,
	[parameter(mandatory = $false)] [int]$compressiondelay,
	[parameter(mandatory = $false)] [switch]$dedupe,
	[parameter(mandatory = $false)] [switch]$fingerprint,
	[parameter(mandatory = $false)] [switch]$connectnfs,
	[parameter(mandatory = $false)] [string]$vcenter,
	[parameter(mandatory = $false)] [string]$vcluster
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
################################################################################
'@
$myvarScriptName = ".\template.ps1"
 
if ($help) {get-help $myvarScriptName; exit}
if ($History) {$HistoryText; exit}


#let's load the Nutanix cmdlets
if ((Get-PSSnapin -Name NutanixCmdletsPSSnapin -ErrorAction SilentlyContinue) -eq $null)#is it already there?
{
    try {
	    Add-PSSnapin NutanixCmdletsPSSnapin -ErrorAction Stop #no? let's add it
	}
    catch {
        Write-Warning $($_.Exception.Message)
		OutputLogData -category "ERROR" -message "Unable to load the Nutanix snapin.  Please make sure the Nutanix Cmdlets are installed on this server."
		return
	}
}

#let's make sure the VIToolkit is being used
if ($vcenter)
{
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
}
#endregion

#region variables
#initialize variables
	#misc variables
	$myvarElapsedTime = [System.Diagnostics.Stopwatch]::StartNew() #used to store script begin timestamp
	$myvarvCenterServers = @() #used to store the list of all the vCenter servers we must connect to
	$myvarOutputLogFile = (Get-Date -UFormat "%Y_%m_%d_%H_%M_")
	$myvarOutputLogFile += "OutputLog.log"
	$myvarNutanixHosts = @()
#endregion

#region parameters validation
	############################################################################
	# command line arguments initialization
	############################################################################	
	#let's initialize parameters if they haven't been specified
	if (!$rf) {$rf = 2} #configure default rf (replication factor) if it has not been specified
	if (($rf -gt 3) -or ($rf -lt 2))
	{
		OutputLogData -category "ERROR" -message "An invalid value ($rf) has been specified for the replication factor. It must be 2 or 3."
		break
	}
	if (!$fingerprint -and $dedupe)
	{
		OutputLogData -category "ERROR" -message "Deduplication can only be enabled when fingerprinting is also enabled."
		break
	}
	if ($compressiondelay -and !$compression)
	{
		OutputLogData -category "ERROR" -message "Compressiondelay can only be specified when compression is also used."
		break
	}
	if ($vcenter -and !$vcluster)
	{
		OutputLogData -category "ERROR" -message "You must specifiy a compute cluster name when you use the -vcenter parameter."
		break
	}
	if ($password) {
		$spassword = $password | ConvertTo-SecureString -AsPlainText -Force
		Remove-Variable password #clear the password variable so we don't leak it
	}
	else 
	{
		$password = read-host "Enter the Nutanix cluster password" -AsSecureString #prompt for the Nutanix cluster password
		$spassword = $password #we already have a secrue string
		Remove-Variable password #clear the password variable so we don't leak it
	}
#endregion

#region processing
	################################
	##  Main execution here       ##
	################################
	OutputLogData -category "INFO" -message "Connecting to the Nutanix cluster $myvarNutanixCluster..."
		try
		{
			$myvarNutanixCluster = Connect-NutanixCluster -Server $cluster -UserName $username -Password $spassword –acceptinvalidsslcerts -ForcedConnection -ErrorAction Stop
		}
		catch
		{#error handling
			Write-Warning $($_.Exception.Message)
			OutputLogData -category "ERROR" -message "Could not connect to $cluster"
			Exit
		}
	OutputLogData -category "INFO" -message "Connected to Nutanix cluster $cluster."
	
	if ($myvarNutanixCluster)
	{
	
		######################
		#main processing here#
		######################
		
		OutputLogData -category "INFO" -message "Creating the storage pool..."
		if (!$storagepool) 
		{
			$storagepool = (Get-NTNXClusterInfo).Name + "-sp1" #figure out the cluster name and init default sp name
		}
	 
		#add error control here to see if storage pool already exists
		if (!$storagepool -eq (Get-NTNXStoragePool | select -expand name))
		{
			#create the container
			New-NTNXStoragePool -Name $storagepool -Disks (Get-NTNXDisk | select -ExpandProperty id)
			#figure out the storage pool id
		}
		else
		{
			OutputLogData -category "WARN" -message "The storage pool $storagepool already exists..."
		}
		$myvarStoragePoolId = get-ntnxstoragepool | where{$_.name -eq $storagepool} | select -expand id #need to add select id property only here
		
		OutputLogData -category "INFO" -message "Creating the container..."
		if (!$container) 
		{
			$container = (Get-NTNXClusterInfo).Name + "-ct1" #figure out the cluster name and init default ct name
		} 
		#add error control here to see if the container already exists
		if (!(get-ntnxcontainer | where{$_.name -eq $container}))
		{			
			if ($compression -and $compressiondelay -and $dedupe -and $fingerprint) 
			{
				if (New-NTNXContainer -Name $container -StoragePoolId $myvarStoragePoolId -ReplicationFactor $rf -CompressionEnabled:$true -CompressionDelayInSecs $compressiondelay -FingerPrintOnWrite ON -OnDiskDedup POST_PROCESS)
				{
					OutputLogData -category "INFO" -message "Container $container was successfully created!"
				}
			}
			elseif ($compression -and $compressiondelay -and $dedupe) 
			{
				if (New-NTNXContainer -Name $container -StoragePoolId $myvarStoragePoolId -ReplicationFactor $rf -CompressionEnabled:$true -CompressionDelayInSecs $compressiondelay -OnDiskDedup POST_PROCESS )
				{
					OutputLogData -category "INFO" -message "Container $container was successfully created!"
				}
			}
			elseif ($compression -and $compressiondelay -and $fingerprint) 
			{
				if (New-NTNXContainer -Name $container -StoragePoolId $myvarStoragePoolId -ReplicationFactor $rf -CompressionEnabled:$true -CompressionDelayInSecs $compressiondelay -FingerPrintOnWrite ON)
				{
					OutputLogData -category "INFO" -message "Container $container was successfully created!"
				}
			}
			elseif ($compression -and $compressiondelay) 
			{
				if (New-NTNXContainer -Name $container -StoragePoolId $myvarStoragePoolId -ReplicationFactor $rf -CompressionEnabled:$true -CompressionDelayInSecs $compressiondelay)
				{
					OutputLogData -category "INFO" -message "Container $container was successfully created!"
				}
			}
			elseif ($compression -and $dedupe -and $fingerprint) 
			{
				if (New-NTNXContainer -Name $container -StoragePoolId $myvarStoragePoolId -ReplicationFactor $rf -CompressionEnabled:$true -FingerPrintOnWrite ON -OnDiskDedup POST_PROCESS)
				{
					OutputLogData -category "INFO" -message "Container $container was successfully created!"
				}
			}
			elseif ($compression -and $fingerprint) 
			{
				if (New-NTNXContainer -Name $container -StoragePoolId $myvarStoragePoolId -ReplicationFactor $rf -CompressionEnabled:$true -FingerPrintOnWrite ON)
				{
					OutputLogData -category "INFO" -message "Container $container was successfully created!"
				}
			}
			elseif ($compression) 
			{
				if (New-NTNXContainer -Name $container -StoragePoolId $myvarStoragePoolId -ReplicationFactor $rf -CompressionEnabled:$true)
				{
					OutputLogData -category "INFO" -message "Container $container was successfully created!"
				}
			}
			elseif ($dedupe -and $fingeprint) 
			{
				if (New-NTNXContainer -Name $container -StoragePoolId $myvarStoragePoolId -ReplicationFactor $rf -FingerPrintOnWrite ON -OnDiskDedup POST_PROCESS)
				{
					OutputLogData -category "INFO" -message "Container $container was successfully created!"
				}
			}
			elseif ($dedupe) 
			{
				if (New-NTNXContainer -Name $container -StoragePoolId $myvarStoragePoolId -ReplicationFactor $rf -OnDiskDedup POST_PROCESS)
				{
					OutputLogData -category "INFO" -message "Container $container was successfully created!"
				}
			}
			elseif ($fingeprint) 
			{
				if (New-NTNXContainer -Name $container -StoragePoolId $myvarStoragePoolId -ReplicationFactor $rf -FingerPrintOnWrite ON)
				{
					OutputLogData -category "INFO" -message "Container $container was successfully created!"
				}
			}
			else 
			{
				if (New-NTNXContainer -Name $container -StoragePoolId $myvarStoragePoolId -ReplicationFactor $rf)
				{
					OutputLogData -category "INFO" -message "Container $container was successfully created!"
				}
			}
		}
		else
		{
			OutputLogData -category "ERROR" -message "The container $container already exists..."
			break
		}
		
		if ($connectnfs)
		{
			if ($vcenter)
			{
				#connect to the vcenter server
				OutputLogData -category "INFO" -message "Connecting to vCenter server $vcenter..."
				if (!($myvarvCenterObject = Connect-VIServer $vcenter))#make sure we connect to the vcenter server OK...
				{#make sure we can connect to the vCenter server
					$myvarerror = $error[0].Exception.Message
					OutputLogData -category "ERROR" -message "$myvarerror"
					return
				}
				else #...otherwise show the error message
				{
					OutputLogData -category "INFO" -message "Connected to vCenter server $vcenter."
				}#endelse
				
				if ($myvarvCenterObject)
				{
					#get the hosts in the specified cluster
					$myvarESXiHosts = get-cluster $vcluster | get-vmhost | Get-VMHostNetworkAdapter -Name vmk0 | Select -ExpandProperty IP
					foreach ($myvarHost in $myvarESXiHosts)
					{
						#make sure all hosts in the compute cluster are also in the Nutanix cluster and get their unique IDs
						$myvarNutanixHosts += Get-NTNXHost | where {$_.hypervisorAddress -eq $myvarHost} | select -ExpandProperty serviceVMId
						OutputLogData -category "INFO" -message "Found ESXi host with IP address $myvarHost in the Nutanix cluster $cluster..."
					}
					
				}
				#mount the NFS datastore to the specified hosts
				if ($myvarNutanixHosts)
				{
					Add-NTNXNfsDatastore -DatastoreName $container -ContainerName $container -NodeIds $myvarNutanixHosts | Out-Null
					OutputLogData -category "INFO" -message "Mounted datastore $container to the ESXi hosts in $vcluster"
				}
				else
				{
					OutputLogData -category "ERROR" -message "Could not find any host to mount the NFS datastore to in $vcluster..."
				}
				OutputLogData -category "INFO" -message "Disconnecting from vCenter server $vcenter..."
				Disconnect-viserver -Confirm:$False #cleanup after ourselves and disconnect from vcenter
			}
			else
			{
				OutputLogData -category "INFO" -message "Mounting the NFS datastore $container on all hypervisor hosts in the Nutanix cluster..."
				Add-NTNXNfsDatastore -DatastoreName $container -ContainerName $container | Out-Null
			}
		}
		
	}#endif
    OutputLogData -category "INFO" -message "Disconnecting from Nutanix cluster $cluster..."
	Disconnect-NutanixCluster -Servers $cluster #cleanup after ourselves and disconnect from the Nutanix cluster
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
	Remove-Variable cluster -ErrorAction SilentlyContinue
	Remove-Variable username -ErrorAction SilentlyContinue
	Remove-Variable password -ErrorAction SilentlyContinue
	Remove-Variable storagepool -ErrorAction SilentlyContinue
	Remove-Variable container -ErrorAction SilentlyContinue
	Remove-Variable compression -ErrorAction SilentlyContinue
	Remove-Variable compressiondelay -ErrorAction SilentlyContinue
	Remove-Variable dedupe -ErrorAction SilentlyContinue
	Remove-Variable fingerprint -ErrorAction SilentlyContinue
	Remove-Variable connectnfs -ErrorAction SilentlyContinue
	Remove-Variable rf -ErrorAction SilentlyContinue
	Remove-Variable vcenter -ErrorAction SilentlyContinue
	Remove-Variable vcluster -ErrorAction SilentlyContinue
    Remove-Variable debugme -ErrorAction SilentlyContinue
#endregion