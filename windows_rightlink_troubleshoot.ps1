#Powershell script to troubleshoot RightLink enabled Windows instances
#To execute this script you might have to run this Set-ExecutionPolicy powershell command first: 
#PS C:\> Set-ExecutionPolicy RemoteSigned -force

function cat_files_in_dir([string]$dir)
{
  Write-Output("`r`n### Including the content of the following files: #########################################################")
  ls $dir | format-table | out-string
  foreach($file in Get-ChildItem -force $dir | Where-Object { !($_.Attributes -match "Directory") } | Select-Object FullName)
  {
    Write-Output("`r`n### Content of [{0}] is:" -f $file.FullName)
    get-content $file.FullName
  }
}


function rs_troubleshoot()
{
$original_path=invoke-expression 'get-location'
$errorActionPreference = "Continue"

write-output("### Using troubleshoot script v1.3 #########################################################")

write-output("`r`n### Get RightLink service status: #########################################################")
get-service *RightLink 2>$null

write-output("`r`n### Get the server timezone setting: #########################################################")
get-itemproperty -path "HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" | Select-Object "TimeZoneKeyName"

write-output("`r`n### Resolve the RightScale brokers: #########################################################")
nslookup broker1-1.rightscale.com 2>$null
nslookup broker1-2.rightscale.com 2>$null

write-output("`r`n### Date is: "+(invoke-expression 'date 2> $null')+" #########################################################`r`n")

#check to see if the package is already installed
if (Test-Path (${env:programfiles(x86)}+"\RightScale")) { 
  $rightscale_path = ${env:programfiles(x86)}+"\RightScale" 
} Elseif (Test-Path (${env:programfiles}+"\RightScale")) { 
  $rightscale_path = ${env:programfiles}+"\RightScale" 
}

write-output("`r`n### RightLink version is: #########################################################")
(Get-Command "${env:programfiles}\RightScale\RightLinkService\RightLinkService.exe").FileVersionInfo.ProductVersion 

write-output("`r`n### Operationg System name and version: #########################################################")
gwmi win32_operatingsystem | format-table -autosize Version,OsArchitecture,Name | out-string

write-output("`r`n### Ruby sandbox version: #########################################################")
invoke-expression "& '$rightscale_path\SandBox\Ruby\bin\ruby.exe' -v" 2> $null

cd "$rightscale_path\SandBox\Ruby\bin"
write-output("`r`n### Ruby sandbox gems: #########################################################")
invoke-expression "& '$rightscale_path\SandBox\Ruby\bin\gem.bat' list --local" 2> $null

if (Test-Path "C:\ProgramData\RightScale\RightScaleService\log")
{
  write-output("`r`n### Adding 2008 RightScaleService logs: #########################################################")	
  cat_files_in_dir('C:\ProgramData\RightScale\RightScaleService\log\')
}
elseif (Test-Path "C:\Documents and Settings\All Users\Application Data\RightScale\RightScaleService\log")
{
  write-output("`r`n### Adding 2003 RightScaleService logs: #########################################################")	
  cat_files_in_dir('C:\Documents and Settings\All Users\Application Data\RightScale\RightScaleService\log\')
}
else
{
  write-output("`r`n### Cannot find RightScaleService log directory!!! #########################################################")
}

if (Test-Path "C:\ProgramData\RightScale\log")
{
  write-output("`r`n### Adding 2008 RightScale logs: #########################################################")
  cat_files_in_dir('C:\ProgramData\RightScale\log\')
}
elseif (Test-Path "C:\Documents and Settings\All Users\Application Data\RightScale\log")
{
  write-output("`r`n### Adding 2003 RightScale logs: #########################################################")
  cat_files_in_dir('C:\Documents and Settings\All Users\Application Data\RightScale\log\')
}
else
{
  write-output("`r`n### Cannot find RightScale log directory!!! #########################################################")
}

if (Test-Path "C:\ProgramData\RightScale\spool\cloud")
{
  $cloud_dir="C:\ProgramData\RightScale\spool\cloud"
}
elseif (Test-Path "C:\Documents and Settings\All Users\Application Data\RightScale\spool\cloud")
{
  $cloud_dir="C:\Documents and Settings\All Users\Application Data\RightScale\spool\cloud"
}
else
{
  write-output("`r`n### Cannot find user-data/meta-data directory!!! #########################################################")
}

if ($cloud_dir)
{
  cd $cloud_dir
  write-output("`r`n### Adding meta-data from $cloud_dir #########################################################")
  get-content meta-data.dict
  write-output("`r`n### Adding user-data masking some values #########################################################")
  (get-content user-data.dict) -replace "RS_TOKEN=\w+","RS_TOKEN=***MASKED***" -replace "ec2_instances/\w+","ec2_instances/***MASKED***" -replace "RS_RN_AUTH=\w+","RS_RN_AUTH=***MASKED***"  -replace "//\w+:\w+@","//***MASKED***@"
}

$ec2configlog_path="C:\Program Files\Amazon\Ec2ConfigService\Logs\ec2configlog.txt"
if (Test-Path $ec2configlog_path)
{
  write-output("`r`n### Adding the ec2configlog, skipping the 'Encrypted Password' line: #########################################################")
  get-content $ec2configlog_path | findstr /V "Encrypted Password"
}
else
{
  write-output("`r`n### Ec2configlog($ec2configlog_path) missing! #########################################################")
}

write-output("`r`n### Adding the processes... #########################################################")
gwmi win32_process | format-table -autosize name,processId,commandLine | Out-String -width 1000 | Foreach-Object {$_ -replace "                        ",""}

write-output("`r`n### Adding RightScale EventLogs... #########################################################")
Get-EventLog RightScale | select-object Index,Source,EntryType,TimeGenerated,Message | Sort-Object -property TimeGenerated | Out-String -width 1000 | Foreach-Object {$_ -replace "                        ",""}

cd "$original_path"
}

#generate a log file with timestamp
$log_file ="C:\rs-win-troubleshooting_$(Get-Date -format yyyy-MM-dd_HH-mm-ss).txt"
rs_troubleshoot | out-file $log_file

#mask instances token/credentials
(get-content -path $log_file) -replace "-(t|u|p) \w+","-`${1} ***MASKED***" | set-content $log_file

Write-Output("### Troubleshooting log deployed to: $log_file`r`n")
