#Powershell script to troubleshoot RightLink enabled Windows instances
#To execute this script you might have to run this Set-ExecutionPolicy powershell command first: 
#PS C:\> Set-ExecutionPolicy RemoteSigned -force

$timestamp = Get-Date -format yyyy-MM-dd_HH-mm-ss
$File ="C:\rs-win-troubleshooting_$timestamp.txt"
$original_path=invoke-expression 'get-location'

function cat_files_in_dir([string]$dir)
{
  Write-Output("`r`n*** Cat the following files:")
  ls $dir
  foreach($file in Get-ChildItem -force $dir | Where-Object { !($_.Attributes -match "Directory") } | Select-Object FullName)
  {
    Write-Output("`r`n*** Content of [{0}] is:" -f $file.FullName)
    cat $file.FullName
  }
}

write-output("*** Using troubleshoot script v1.2") | Out-File $File

write-output("`r`n*** Get RightLink service status:") | Out-File $File -append
get-service *RightLink 2>$null | Out-File $File -append

write-output("`r`n*** Get the server timezone setting:") | Out-File $File -append
get-itemproperty -path "HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" | Select-Object "TimeZoneKeyName" | Out-File $File -append

write-output("`r`n*** Resolve the RightScale brokers:") | Out-File $File -append
nslookup broker1-1.rightscale.com 2>$null | Out-File $File -append
nslookup broker1-2.rightscale.com 2>$null | Out-File $File -append

write-output("`r`n*** Date is: "+(invoke-expression 'date 2> $null')+"`r`n") | Out-File $File -append

#check to see if the package is already installed
if (Test-Path (${env:programfiles(x86)}+"\RightScale")) { 
  $rightscale_path = ${env:programfiles(x86)}+"\RightScale" 
} Elseif (Test-Path (${env:programfiles}+"\RightScale")) { 
  $rightscale_path = ${env:programfiles}+"\RightScale" 
}

write-output("`r`n*** RightLink version is:") | Out-File $File -append
(Get-Command "${env:programfiles}\RightScale\RightLinkService\RightLinkService.exe").FileVersionInfo.ProductVersion  | Out-File $File -append

write-output("`r`n*** Operationg System name and version:") | Out-File $File -append
gwmi win32_operatingsystem | format-table -autosize Version,OsArchitecture,Name | Out-File $File -append 

write-output("`r`n*** Ruby sandbox version:") | Out-File $File -append
invoke-expression "& '$rightscale_path\SandBox\Ruby\bin\ruby.exe' -v" 2> $null | Out-File $File -append

cd "$rightscale_path\SandBox\Ruby\bin"
write-output("`r`n*** Ruby sandbox gems:") | Out-File $File -append
invoke-expression "& '$rightscale_path\SandBox\Ruby\bin\gem.bat' list --local" 2> $null | Out-File $File -append

if (Test-Path "C:\ProgramData\RightScale\RightScaleService\log")
{
  write-output("`r`n*** Adding 2008 RightScaleService logs:") | Out-File $File -append	
  cat_files_in_dir('C:\ProgramData\RightScale\RightScaleService\log\') | Out-File $File -append
}
elseif (Test-Path "C:\Documents and Settings\All Users\Application Data\RightScale\RightScaleService\log")
{
  write-output("`r`n*** Adding 2003 RightScaleService logs:") | Out-File $File -append	
  cat_files_in_dir('C:\Documents and Settings\All Users\Application Data\RightScale\RightScaleService\log\') | Out-File $File -append
}
else
{
  write-output "`r`n*** Cannot find RightScaleService log directory!!!!!!!!!!!!!!!!!!!" | Out-File $File -append
}

if (Test-Path "C:\ProgramData\RightScale\log")
{
  write-output("`r`n*** Adding 2008 RightScale logs:") | Out-File $File -append
  cat_files_in_dir('C:\ProgramData\RightScale\log\') | Out-File $File -append
}
elseif (Test-Path "C:\Documents and Settings\All Users\Application Data\RightScale\log")
{
  write-output("`r`n*** Adding 2003 RightScale logs:") | Out-File $File -append
  cat_files_in_dir('C:\Documents and Settings\All Users\Application Data\RightScale\log\') | Out-File $File -append
}
else
{
  write-output "`r`n*** Cannot find RightScale log directory!!!!!!!!!!!!!!!!!!!" | Out-File $File -append
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
  write-output "`r`n*** Cannot find user-data/meta-data directory!!!!!!!!!!!!!!!!!!!" | Out-File $File -append
}

if ($cloud_dir)
{
  cd $cloud_dir
  write-output("`r`n*** Adding meta-data from $cloud_dir") | Out-File $File -append
  cat meta-data.dict | Out-File $File -append
  write-output("`r`n*** Adding user-data without(RS_API_URL, RS_TOKEN, RS_RN_AUTH)") | Out-File $File -append
  cat user-data.dict | findstr /V RS_API_URL | findstr /V RS_TOKEN | findstr /V RS_RN_AUTH | Out-File $File -append
}

$ec2configlog_path="C:\Program Files\Amazon\Ec2ConfigService\Logs\ec2configlog.txt"
if (Test-Path $ec2configlog_path)
{
  write-output("`r`n*** Adding the ec2configlog, skipping the 'Encrypted Password' line:") | Out-File $File -append
  cat $ec2configlog_path | findstr /V "Encrypted Password" | Out-File $File -append
}
else
{
  write-output "`r`n*** Ec2configlog($ec2configlog_path) missing!" | Out-File $File -append
}

write-output("`r`n*** Adding the processes...") | Out-File $File -append
gwmi win32_process | format-table -autosize name,processId,commandLine | Out-File $File -append -width 1000

write-output("`r`n*** Adding RightScale EventLogs...") | Out-File $File -append
Get-EventLog RightScale | select-object Index,Source,EntryType,TimeGenerated,Message | Sort-Object -property TimeGenerated | Out-File $File -append 


cd "$original_path"

#remove padding
(get-content -path $File) -replace "                        ","" | set-content $File

Write-Output "*** Troubleshooting log deployed to:`r`n`t$File"
