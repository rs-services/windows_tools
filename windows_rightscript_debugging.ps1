# Add the DEBUG BLOCK at the beginning of a Powershell RightScript. Run the RightScript and then RDP into the server and start debugging with script.ps1
#> Set-ExecutionPolicy RemoteSigned -force
#> . "c:\ap-debug\script.ps1"

##### DEGUB BLOCK ### REMOVE #####
$debug_dir="c:\ap-debug"
if (!(test-path $debug_dir -PathType Container)) {
  write-output("*** Creating debug directory($debug_dir) and files")
  mkdir $debug_dir
  Get-ChildItem Env: | % {write-output("`${env:"+$_.Name+"}='"+$_.Value+"'") } | Out-File -Encoding ASCII "$debug_dir\envs.ps1"
  write-output("*** All env variables exported to: $debug_dir\envs.ps1")
  $script_path=$MyInvocation.MyCommand.Path
  cp "$script_path" "$debug_dir\script.ps1"
  write-output("*** Script("+$script_path+") copied to: $debug_dir\script.ps1")
} else {
  write-output("*** Debug directory($debug_dir) exits, sourcing envs.ps1")
  . "$debug_dir\envs.ps1"
}
##### DEGUB BLOCK ### REMOVE #####
