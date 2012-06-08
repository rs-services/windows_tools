# Add the DEBUG BLOCK at the beginning of a Powershell RightScript. 
# Run the RightScript, RDP into the server and start debugging with script.ps1
# PS C:\> Set-ExecutionPolicy RemoteSigned -force
# PS C:\> . "c:\ap-debug\script.ps1"

##### DEGUB BLOCK ### REMOVE #####
$debug_dir="c:\ap-debug"
if (!(test-path $debug_dir -PathType Container)) {
  write-output("*** Creating debug directory($debug_dir) and files")
  mkdir $debug_dir
  write-output("*** Exporting env variables to: $debug_dir\envs.ps1")
  Get-ChildItem Env: | % {write-output("`${env:"+$_.Name+"}='"+$_.Value+"'") } | Out-File -Encoding ASCII "$debug_dir\envs.ps1"
  $script_path=$MyInvocation.MyCommand.Path
  write-output("*** Copying script("+$script_path+") to: $debug_dir\script.ps1")
  cp "$script_path" "$debug_dir\script.ps1"
} elseif (!(${env:RS_SERVER})) {
  write-output("*** Debug directory($debug_dir) exits, sourcing $debug_dir\envs.ps1")
  . "$debug_dir\envs.ps1"
}
##### DEGUB BLOCK ### REMOVE #####
