$ErrorActionPreference='Stop'
$v2Root=Split-Path -Parent $PSScriptRoot
$v2Raw=Join-Path $v2Root 'hardware\fpai_demo_vivado.runs\impl_1\ai7030_edif_top.bit'
if(-not(Test-Path -LiteralPath $v2Raw)){throw 'Missing completed V2 raw bitstream'}
$v2Status=Join-Path $v2Root 'output\disable_icap_status.txt'
if(Test-Path -LiteralPath $v2Status){Remove-Item -LiteralPath $v2Status}
$v2Converted=Join-Path $v2Root 'hardware\fpai_demo_vivado.runs\impl_1\ai7030_edif_top_disable_icap.bit'
if(Test-Path -LiteralPath $v2Converted){Remove-Item -LiteralPath $v2Converted}
$env:PROCISE_DIR='F:/Procise';$env:TCL_LIBRARY='F:/Procise/tcl8.4';$env:ICTIME_HOME='F:/Procise';$env:APP_DIR='F:/Procise';$env:FMSH_DB='F:/Procise/db'
$env:PATH='F:\Procise\dll;F:\Procise\bin;'+$env:PATH
$v2Proc=Start-Process -FilePath 'F:\Procise\bin\procise.exe' -ArgumentList (Join-Path $PSScriptRoot 'disable_icap.tcl') -WorkingDirectory (Join-Path $v2Root 'output') -WindowStyle Hidden -PassThru
$v2Deadline=[DateTime]::UtcNow.AddMinutes(2)
while(-not(Test-Path -LiteralPath $v2Status)){
 if([DateTime]::UtcNow -gt $v2Deadline){throw 'Disable-ICAP conversion timed out'}
 Start-Sleep -Milliseconds 500
}
if((Get-Content -LiteralPath $v2Status -TotalCount 1) -ne 'PASS'){throw 'Disable-ICAP conversion failed'}
if(-not(Test-Path -LiteralPath $v2Converted) -or (Get-Item -LiteralPath $v2Converted).Length -lt 1000000){throw 'Converted V2 bitstream missing/incomplete'}
'V2_DISABLE_ICAP_PASS'
