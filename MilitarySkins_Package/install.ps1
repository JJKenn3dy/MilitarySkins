param([switch]$Rollback,[string]$GameRoot='')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
if($GameRoot){$root=[IO.Path]::GetFullPath($GameRoot).TrimEnd('\')}
if(-not (Test-Path -LiteralPath (Join-Path $root 'gta_sa.exe'))){throw 'Extract this archive into the GTA San Andreas game root first.'}
if(Get-Process -Name gta_sa -ErrorAction SilentlyContinue){throw 'Close GTA San Andreas before installation or rollback.'}
if(-not $Rollback){
 $retiredHelper=Join-Path $root 'MoonLoader\MilitarySkins\update.ps1'
 if(Test-Path -LiteralPath $retiredHelper){
  Get-CimInstance Win32_Process -Filter "name = 'powershell.exe'" | Where-Object { $_.CommandLine -like ('*-File "'+$retiredHelper+'"*') } | ForEach-Object {Stop-Process -Id $_.ProcessId}
 }
}
function Hash([string]$path){(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Target([string]$name){
 $p=[IO.Path]::GetFullPath((Join-Path $root $name))
 if(-not $p.StartsWith($root+'\MoonLoader\',[StringComparison]::OrdinalIgnoreCase)){throw 'Invalid package target'}
 return $p
}
$history=Join-Path $root 'MilitarySkins_Backups'
$latest=Join-Path $history 'latest.json'
if($Rollback){
 $saved=Get-Content -LiteralPath $latest -Raw | ConvertFrom-Json
 foreach($r in $saved.files){$target=Target $r.name
  if($r.existed){$source=Join-Path $saved.backup $r.name;if((Hash $source) -ne $r.oldHash){throw 'Backup damaged'};Copy-Item -LiteralPath $source -Destination $target -Force}
  elseif(Test-Path -LiteralPath $target){Remove-Item -LiteralPath $target -Force}
 }
 foreach($legacy in $saved.legacy){$original=Target $legacy.name;$disabled=Target $legacy.disabled;if(Test-Path -LiteralPath $disabled){Move-Item -LiteralPath $disabled -Destination $original}}
 Write-Output 'MilitarySkins rolled back. Cloud assignments and personal credentials retained.';exit
}
$package=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'manifest.json') -Raw | ConvertFrom-Json
$backup=Join-Path $history (Get-Date -Format 'yyyyMMdd_HHmmss_fff')
New-Item -ItemType Directory -Path $backup -Force | Out-Null
$records=@();$legacy=@()
foreach($item in $package.files){
 $target=Target $item.name;$source=Join-Path (Join-Path $PSScriptRoot 'payload') $item.name
 if((Hash $source) -ne $item.sha256){throw ('Package checksum mismatch: '+$item.name)}
 if($item.name -eq 'MoonLoader\MilitarySkins\cloud_config.json' -and (Test-Path -LiteralPath $target)){continue}
 $existed=Test-Path -LiteralPath $target;$oldHash=$null
 if($existed){$oldHash=Hash $target;if($oldHash -eq $item.sha256){continue};$copy=Join-Path $backup $item.name;New-Item -ItemType Directory -Path (Split-Path -Parent $copy) -Force | Out-Null;Copy-Item -LiteralPath $target -Destination $copy;if((Hash $copy) -ne $oldHash){throw 'Backup checksum mismatch'}}
 $records+=@{name=$item.name;source=$source;target=$target;existed=$existed;oldHash=$oldHash;sha256=$item.sha256}
}
$token=[guid]::NewGuid().ToString('N');$staged=@();$done=@()
try{
 foreach($r in $records){New-Item -ItemType Directory -Path (Split-Path -Parent $r.target) -Force | Out-Null;$temp=$r.target+'.'+$token+'.new';$staged+=$temp;Copy-Item -LiteralPath $r.source -Destination $temp;if((Hash $temp) -ne $r.sha256){throw 'Staging checksum mismatch'}}
 foreach($r in ($records | Sort-Object {$_.name -eq 'MoonLoader\MilitarySkins.lua'})){
  if($r.existed){if((Hash $r.target) -ne $r.oldHash){throw 'Installed file changed during staging'};[IO.File]::Replace($r.target+'.'+$token+'.new',$r.target,(Join-Path $backup ('replaced_'+(Split-Path -Leaf $r.name))))}
  else{[IO.File]::Move($r.target+'.'+$token+'.new',$r.target)}
  $done+=$r
 }
 foreach($name in @('Soldier179.lua','ShunSkin61.lua','MilitarySkins\updater.lua','MilitarySkins\update.ps1','MilitarySkins\update_config.json','MilitarySkins\update_status.json','MilitarySkins\update_installed.json')){
  $relative='MoonLoader\'+$name;$target=Target $relative
  if(Test-Path -LiteralPath $target){$disabled=$relative+'.disabled_mskin4_'+$token;$destination=Target $disabled;Move-Item -LiteralPath $target -Destination $destination;$legacy+=@{name=$relative;disabled=$disabled}}
 }
 foreach($r in $records){if((Hash $r.target) -ne $r.sha256){throw 'Installed checksum mismatch'}}
 @{backup=$backup;files=$records;legacy=$legacy;version=$package.version}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $latest -Encoding UTF8
 Write-Output ('MilitarySkins '+$package.version+' installed. Start GTA and use /mskin. Automatic updates removed.')
}catch{
 foreach($r in $done){if($r.existed){Copy-Item -LiteralPath (Join-Path $backup $r.name) -Destination $r.target -Force}elseif(Test-Path -LiteralPath $r.target){Remove-Item -LiteralPath $r.target -Force}}
 foreach($entry in $legacy){$disabled=Target $entry.disabled;$original=Target $entry.name;if(Test-Path -LiteralPath $disabled){Move-Item -LiteralPath $disabled -Destination $original}}
 throw
}finally{foreach($temp in $staged){if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force}}}
