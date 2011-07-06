
#--- Initialize Global Variables
$global:webClient = new-object System.Net.WebClient
$global:ec2_placement_availability_zone = ""
$global:ec2_region = ""
$global:ec2_instance_id =""


# Set Error Action Preference
Set-PSdebug -strict
$ErrorActionPreference="Stop"

function Initialize-EC2Metadata()
{
	<#
    .SYNOPSIS 
    Initalizes EC2 metadata from http://169.265.169.254

    .DESCRIPTION
	Initializes the following powershell variables from Amazon's EC2 metadata
	
	$global:ec2_placement_availability_zone:
	http://169.254.169.254/latest/meta-data/placement/availability-zone
	
	$global:ec2_instance_id:
	http://169.254.169.254/latest/meta-data/instance-id
	
	$global:ec2_region derives this from $ec2_placement_availability_zone
	#>
	
	# Get Metadata
	$global:ec2_placement_availability_zone = $webClient.DownloadString("http://169.254.169.254/latest/meta-data/placement/availability-zone")
	$global:ec2_region = $ec2_placement_availability_zone.substring(0,$ec2_placement_availability_zone.length-1)
	$global:ec2_instance_id = $webClient.DownloadString("http://169.254.169.254/latest/meta-data/instance-id")

}

function Resolve-Error ($ErrorRecord=$Error[0])
{
	<#
    .SYNOPSIS 
    Iterates through the $Error object to display all the nested exceptions

    .DESCRIPTION
	Iterates through the $Error object to display all the nested exceptions
	#>
	
   $ErrorRecord | Format-List * -Force
   $ErrorRecord.InvocationInfo |Format-List *
   $Exception = $ErrorRecord.Exception
   for ($i = 0; $Exception; $i++, ($Exception = $Exception.InnerException))
   {   "$i" * 80
       $Exception |Format-List * -Force
   }
   
   return 1
}

function Import-AwsSdk()
{
	<#
    .SYNOPSIS 
    Loads the AWS .Net SDK assembly in to the current powershell session

    .DESCRIPTION
	Loads the AWS .Net SDK assembly in to the current powershell session. 
	#>
	
	# Load AWS SDK
	$osArchitecture = (Get-WmiObject Win32_OperatingSystem).OSArchitecture
	
	if ($osArchitecture -eq "32-bit")
	{
		Add-Type -Path "C:\Program Files\AWS SDK for .NET\bin\AWSSDK.dll"
	}
	else
	{
		Add-Type -Path "C:\Program Files (x86)\AWS SDK for .NET\bin\AWSSDK.dll"
	}
	
	if (!$?)
	{
		Write-Error "Could not load AWS SDK!"
		Exit 1
	}
}


function Get-S3File()
{
	<#
    .SYNOPSIS 
    Downloads a file from S3

    .DESCRIPTION
	Downloads a file from S3 using the provided AWS credentials
	
	.Example
	Get-S3file -ACCESSKEYID "myAccesKeyId" -SECRETACCESSKEY "mySecretAccessKey" -S3BUCKET "mybucket" -S3FILE "test.txt" -DOWNLOADDIR "c:\temp" 
        
	#>
	
	Param(
		[parameter(Mandatory=$true)] [string] $ACCESSKEYID,
		[parameter(Mandatory=$true)] [string] $SECRETACCESSKEY,
		[parameter(Mandatory=$true)] [string] $S3FILE,
		[parameter(Mandatory=$true)] [string] $S3BUCKET,
		[parameter(Mandatory=$true)] [string] $DOWNLOADDIR
	)
	
	# Load AWS SDK
	Import-AwsSdk
	
	$client=[Amazon.AWSClientFactory]::CreateAmazonS3Client($accessKeyID,$secretAccessKey)

	$targetpath = join-path ($downloadDir) $s3File

	if ($targetpath -match '^(.+)\\')
	{
		$fullpath=$matches[1]
		if (!(test-path $fullpath -PathType Container))
		{
			Write-output "***Directory [$fullpath] missing, creating it."
			New-Item $fullpath -type directory > $null
		}
	}

	Write-output "***Downloading key[$s3File] from bucket[$s3Bucket] to [$targetpath]"
	$get_request = New-Object -TypeName Amazon.S3.Model.GetObjectRequest
	$get_request.BucketName = $s3Bucket
	$get_request.key = $s3File


	$S3Response = $client.GetObject($get_request) #NOTE: download defaults to ... minute timeout. 
	#If download fails it will throw an exception and $S3Response will be $null 
	if($S3Response -eq $null){ 
		Write-Error "***ERROR: Amazon S3 get requrest failed. Script halted." 
		exit 1 
	} 

	$responsestream=$S3Response.ResponseStream

	# create the target file on the local system and the download buffer
	$targetfile = New-Object IO.FileStream ($targetpath,[IO.FileMode]::Create)
	[byte[]]$readbuffer = New-Object byte[] 1024

	# loop through the download stream and send the data to the target file
	do{
	    $readlength = $responsestream.Read($readbuffer,0,1024)
	    $targetfile.Write($readbuffer,0,$readlength)
	}
	while ($readlength -ne 0)

	$targetfile.close()

}


function Write-S3file()
{
	<#
    .SYNOPSIS 
    Uploads a file to S3

    .DESCRIPTION
	Uploads a file to an  S3 bucket
	
	.Example
	 Write-S3file  -ACCESSKEYID "myAccesKeyId" -SECRETACCESSKEY "mySecretAccessKey" -S3BUCKET "mybucket" -FILEPATH "c:\temp\test.txt" -S3FILE "test.txt" 
        
	#>
	
	Param(
		[parameter(Mandatory=$true)] [string] $ACCESSKEYID,
		[parameter(Mandatory=$true)] [string] $SECRETACCESSKEY,
		[parameter(Mandatory=$true)] [string] $S3BUCKET,
		[parameter(Mandatory=$true)] [string] $FILEPATH,
		[parameter(Mandatory=$true)] [string] $S3FILE,
		[int] $TIMEOUTSECONDS=20
	)

	# Load AWS SDK
	Import-AwsSdk
	
	$client=[Amazon.AWSClientFactory]::CreateAmazonS3Client($accessKeyID,$secretAccessKey)

	$fileObject = [System.IO.FileInfo]$filePath

	#if fileObject is a directory, uploading the latest file from the directory
	if (test-path $fileObject.FullName -PathType Container)
	{
		Write-Output("***["+$fileObject.FullName+"] is a directory, trying to find the latest file inside.")
		$latest_file=Get-ChildItem -force $fileObject.FullName | Where-Object { !($_.Attributes -match "Directory") } | Sort-Object LastWriteTime -descending | Select-Object Name, FullName | Select-Object -first 1
		if ($latest_file -eq $null)
		{
		    Write-Error("***["+$fileObject.FullName+"] directory has no file, aborting...")
	    	exit 120
		}
		else
		{
			$fileObject=$latest_file
			Write-Output("***The latest file in ["+$fileObject.FullName+"] directory is ["+$fileObject.Name+"]")
		}
	}


	if (($s3File -eq $NULL) -or ($s3File -eq ""))
	{
		$s3File = $fileObject.Name
	}

	Write-Output("***Uploading file["+$fileObject.FullName+"] to bucket[$s3Bucket] as[$s3File]")

	$request = New-Object -TypeName Amazon.S3.Model.PutObjectRequest
	[void]$request.WithFilePath($fileObject.FullName)
	[void]$request.WithBucketName($s3Bucket)
	[void]$request.WithKey($s3File)

	#NOTE: upload defaults to 20 minute timeout.
	if ($timeoutSeconds -is [int])
	{  
		#timeout is in miliseconds
		$request.timeout=1000*$timeoutSeconds
	}

	#If download fails it will throw an exception and $S3Response will be $null 
	$S3Response = $client.PutObject($request)

	if($S3Response -eq $null)
	{ 
		Write-Error "ERROR: Amazon S3 put requrest failed. Aborting..." 
		return 121
	}
	else
	{
		return 0	
	}
}






function Unregister-ELB()
{
	<#
    .SYNOPSIS 
    Unregisters the current server with an Amazon Elastic Load Balancer

    .DESCRIPTION
	Unregisters the current server with an Amazon Elastic Load Balancer
	
	.Example
	Unregister-ELB -ACCESSKEYID "mykeyid" -SECRETACCESSKEY "mySecretAccessKey" -ELBNAME "myloadbalancername"
	#>
	
	Param(
		[parameter(Mandatory=$true)] [string] $ACCESSKEYID,
		[parameter(Mandatory=$true)] [string] $SECRETACCESSKEY,
		[parameter(Mandatory=$true)] [string] $ELBNAME
	)
	
	# Load AWS SDK
	Import-AwsSdk
	
	$elb_config = New-Object -TypeName Amazon.ElasticLoadBalancing.AmazonElasticLoadBalancingConfig

    # Get meta data	
	Initialize-EC2Metadata

	Write-Output "*** Instance is in region: [$global:ec2_region]"

	$elb_config.ServiceURL = "https://elasticloadbalancing."+  $global:ec2_region +".amazonaws.com"

	#create elb client base on the ServiceURL(region)
	$client_elb=[Amazon.AWSClientFactory]::CreateAmazonElasticLoadBalancingClient($accessKeyID,$secretAccessKey,$elb_config)

	# deregister instance
	try {
		$elb_deregister_request = New-Object -TypeName Amazon.ElasticLoadBalancing.Model.DeregisterInstancesFromLoadBalancerRequest

		$instance_object=New-Object -TypeName Amazon.ElasticLoadBalancing.Model.Instance
		$instance_object.InstanceId=$global:ec2_instance_id

		$elb_deregister_request.WithLoadBalancerName($elbName)  | Out-Null
		$elb_deregister_request.WithInstances($instance_object) | Out-Null

		$elb_deregister_response=$client_elb.DeregisterInstancesFromLoadBalancer($elb_deregister_request)

		$elb_deregister_response.DeregisterInstancesFromLoadBalancerResult
	
		return 0
	}
	catch [Exception]
	{
		Resolve-Error
	}
}


function Register-Elb()
{
	<#
    .SYNOPSIS 
    Registers the current server with an Amazon Elastic Load Balancer

    .DESCRIPTION
	Registers the current server with an Amazon Elastic Load Balancer
	
	.Example
	Register-ELB -ACCESSKEYID "mykeyid" -SECRETACCESSKEY "mySecretAccessKey" -ELBNAME "myloadbalancername"
	#>
	
	Param(
			[parameter(Mandatory=$true)] [string] $ACCESSKEYID,
			[parameter(Mandatory=$true)] [string] $SECRETACCESSKEY,
			[parameter(Mandatory=$true)] [string] $ELBNAME
	)



	# Load AWS SDK
	Import-AwsSdk
	
	$elb_config = New-Object -TypeName Amazon.ElasticLoadBalancing.AmazonElasticLoadBalancingConfig
		
    # Get meta data	
	Initialize-EC2Metadata

	Write-Output "*** Instance is in region: [$global:ec2_region]"

	$elb_config.ServiceURL = "https://elasticloadbalancing."+ $global:ec2_region +".amazonaws.com"

	#create elb client base on the ServiceURL(region)
	$client_elb=[Amazon.AWSClientFactory]::CreateAmazonElasticLoadBalancingClient($accessKeyID,$secretAccessKey,$elb_config)


	#Enable the availability zone with the load balancer
	$elb_enable_az_request = New-Object -TypeName Amazon.ElasticLoadBalancing.Model.EnableAvailabilityZonesForLoadBalancerRequest
	$elb_enable_az_request.WithAvailabilityZones($global:ec2_placement_availability_zone)	| Out-Null
	$elb_enable_az_request.WithLoadBalancerName($elbName) | Out-Null

	$elb_enable_az_response=$client_elb.EnableAvailabilityZonesForLoadBalancer($elb_enable_az_request)
	Write-Output "`n----------------------------------------"	
	Write-Output "Current availability zones for this ELB:"
	Write-Output "----------------------------------------`n"	
	$elb_enable_az_response.EnableAvailabilityZonesForLoadBalancerResult.AvailabilityZones
	
	#register instance with the ELB
	try {
		$elb_register_request = New-Object -TypeName Amazon.ElasticLoadBalancing.Model.RegisterInstancesWithLoadBalancerRequest

		$instance_object=New-Object -TypeName Amazon.ElasticLoadBalancing.Model.Instance
		$instance_object.InstanceId=$global:ec2_instance_id

		$elb_register_request.WithLoadBalancerName($elbName)  | Out-Null
		$elb_register_request.WithInstances($instance_object) | Out-Null

		$elb_register_response=$client_elb.RegisterInstancesWithLoadBalancer($elb_register_request) 
		
		"`nRegistered instances:"
		$elb_register_response.RegisterInstancesWithLoadBalancerResult.Instances
		
		return 0
	}
	catch [Exception]
	{
		Resolve-Error
	}
}


function Remove-Instance()
{
	<#
    .SYNOPSIS 
    Terminates the EC2 instance this Powershell module is installed on

    .DESCRIPTION
	Terminates the EC2 instance this Powershell module is installed on
	
	.Example
	Remove-Instance -ACCESSKEYID "mykeyid" -SECRETACCESSKEY "mySecretAccessKey"
	#>
	
	Param (
		[parameter(Mandatory=$true)] [string] $accessKeyID,
		[parameter(Mandatory=$true)] [string] $secretAccessKey
	)

	#use the AWS SDK dll
	Import-AwsSdk

    # Get meta data	
	Initialize-EC2Metadata

	Write-Output "*** Instance is in region: [$global:ec2_region]"

	$ec2_config = New-Object -TypeName Amazon.EC2.AmazonEC2Config 
	[void]$ec2_config.WithServiceURL("https://$global:ec2_region.ec2.amazonaws.com")

	#create ec2 client base on the ServiceURL(region)
	$client_ec2=[Amazon.AWSClientFactory]::CreateAmazonEC2Client($accessKeyID,$secretAccessKey,$ec2_config)

	$request = New-Object -TypeName Amazon.EC2.Model.TerminateInstancesRequest

	[void]$request.WithInstanceId($global:ec2_instance_id)

	$ec2_describe_response=$client_ec2.TerminateInstances($request);

	$ec2_describe_response.TerminateInstancesResult
}

# Define Aliases

Set-Alias Load-AwsSdk Import-AwsSdk
Set-Alias Download-S3File Get-S3File
Set-Alias Get Get-S3File
Set-Alias Upload-S3File Write-S3File
Set-Alias Put Write-S3File
Set-Alias elb_deregister Unregister-ELB
Set-Alias Deregister-ELB Unregister-ELB
Set-Alias elb_register Register-ELB
Set-Alias terminate_instance Remove-Instance
Set-Alias Terminate-Instance Remove-Instance

# Export Module Members

Export-ModuleMember -function * -Alias *

