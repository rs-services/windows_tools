#Powershell script to troubleshoot RightLink enabled Windows instances
#To execute this script you might have to run this Set-ExecutionPolicy powershell command first: 
#PS C:\> Set-ExecutionPolicy RemoteSigned -force

$timestamp = Get-Date -format yyyy-MM-dd_HH-mm-ss

$File ="C:\rs-win-troubleshooting_$timestamp.txt"

$original_path=invoke-expression 'get-location'

write-output("*** Get RightLink service status:") | Out-File $File
get-service *RightLink 2>$null | Out-File $File -append

write-output("`n*** Get the server timezone setting:") | Out-File $File -append
get-itemproperty -path "HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" | Select-Object "TimeZoneKeyName" | Out-File $File -append

write-output("`n*** Resolve the RightScale brokers:") | Out-File $File -append
nslookup broker1-1.rightscale.com 2>$null | Out-File $File -append
nslookup broker1-2.rightscale.com 2>$null | Out-File $File -append

write-output("`n*** Date is: "+(invoke-expression 'date 2> $null')+"`n") | Out-File $File -append

#check to see if the package is already installed
if (Test-Path (${env:programfiles(x86)}+"\RightScale")) { 
  $rightscale_path = ${env:programfiles(x86)}+"\RightScale" 
} Elseif (Test-Path (${env:programfiles}+"\RightScale")) { 
  $rightscale_path = ${env:programfiles}+"\RightScale" 
}

write-output("`n*** RightLink version is:") | Out-File $File -append
(Get-Command "${env:programfiles}\RightScale\RightLinkService\RightLinkService.exe").FileVersionInfo.ProductVersion  | Out-File $File -append

write-output("`n*** Operationg System name and version:") | Out-File $File -append
gwmi win32_operatingsystem | select Name,Version | Out-File $File -append 

write-output("`n*** Ruby sandbox version:") | Out-File $File -append
invoke-expression "& '$rightscale_path\SandBox\Ruby\bin\ruby.exe' -v" 2> $null | Out-File $File -append

cd "$rightscale_path\SandBox\Ruby\bin"
write-output("`n*** Ruby sandbox gems:") | Out-File $File -append
invoke-expression "& '$rightscale_path\SandBox\Ruby\bin\gem.bat' list --local" 2> $null | Out-File $File -append

if (Test-Path "C:\ProgramData\RightScale\RightScaleService\log")
{
	write-output("`n*** Adding 2008 RightScaleService logs:") | Out-File $File -append	
	cat "C:\ProgramData\RightScale\RightScaleService\log\*" | Out-File $File -append
}
elseif (Test-Path "C:\Documents and Settings\All Users\Application Data\RightScale\RightScaleService\log")
{
	write-output("`n*** Adding 2003 RightScaleService logs:") | Out-File $File -append	
	cat "C:\Documents and Settings\All Users\Application Data\RightScale\RightScaleService\log\*" | Out-File $File -append
}
else
{
	write-output "*** Cannot find RightScaleService logs!!!!!!!!!!!!!!!!!!!" | Out-File $File -append
}

if (Test-Path "C:\ProgramData\RightScale\log")
{
	write-output("`n*** Adding 2008 RightScale logs:") | Out-File $File -append
	cat "C:\ProgramData\RightScale\log\*" | Out-File $File -append
}
elseif (Test-Path "C:\Documents and Settings\All Users\Application Data\RightScale\log")
{
	write-output("`n*** Adding 2003 RightScale logs:") | Out-File $File -append
	cat "C:\Documents and Settings\All Users\Application Data\RightScale\log\*" | Out-File $File -append
}
else
{
	write-output "*** Cannot find RightScaleService logs!!!!!!!!!!!!!!!!!!!" | Out-File $File -append
}

cd "$original_path"

Write-Output "*** Troubleshooting log deployed to:`n`t$File"
