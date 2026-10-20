param([string]$AndroidSdk=$env:ANDROID_SDK_ROOT,[string]$JavaRoot=$env:JAVA_HOME,[string]$Python='python',[string]$Payload=(Join-Path $PSScriptRoot 'payload\system'))
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$projectRoot=$PSScriptRoot
if (!$AndroidSdk) { $AndroidSdk=Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
if (!$JavaRoot -or !(Test-Path (Join-Path $JavaRoot 'bin\javac.exe'))) {
  $JavaRoot=(Get-ChildItem 'C:\Program Files\Java' -Directory -Filter 'jdk*' | Sort-Object Name -Descending | Select-Object -First 1).FullName
}
$env:JAVA_HOME=$JavaRoot
$sdkTools=Join-Path $AndroidSdk 'build-tools\36.0.0'
$platformJar=Join-Path $AndroidSdk 'platforms\android-35\android.jar'
function Invoke-Checked([string]$Executable,[string[]]$Arguments) {
  & $Executable @Arguments
  if ($LASTEXITCODE -ne 0) { throw "Build step failed: $Executable ($LASTEXITCODE)" }
}
$build=Join-Path $projectRoot 'build'
$out=Join-Path $projectRoot 'out'
foreach ($folder in @($build,$out,"$build\helper-classes","$build\helper-dex","$build\classes","$build\dex")) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
Invoke-Checked $Python @("$projectRoot\pack-assets.py",'--payload',$Payload)
Invoke-Checked "$JavaRoot\bin\javac.exe" @('-encoding','UTF-8','-source','8','-target','8','-classpath',$platformJar,'-d',"$build\helper-classes","$projectRoot\helper\RestorePolicy.java")
Invoke-Checked "$sdkTools\d8.bat" @('--min-api','26','--lib',$platformJar,'--output',"$build\helper-dex","$build\helper-classes\RestorePolicy.class")
Invoke-Checked "$JavaRoot\bin\jar.exe" @('cf',"$projectRoot\assets\control.jar",'-C',"$build\helper-dex",'classes.dex')
$generated="package com.smr.googlerestore;`nfinal class AssetHashes {`n"
foreach ($pair in @(@('SCRIPT','restore.sh'),@('CONTROL','control.jar'),@('PAYLOAD','payload.zip'),@('SUMS','payload.sha256'))) {
  $hash=(Get-FileHash -LiteralPath "$projectRoot\assets\$($pair[1])" -Algorithm SHA256).Hash.ToLowerInvariant()
  $generated+="static final String $($pair[0]) = `"$hash`";`n"
}
$generated+="}`n"
[IO.File]::WriteAllText("$build\AssetHashes.java",$generated,[Text.UTF8Encoding]::new($false))
Invoke-Checked "$JavaRoot\bin\javac.exe" @('-encoding','UTF-8','-source','8','-target','8','-classpath',$platformJar,'-d',"$build\classes","$build\AssetHashes.java","$projectRoot\src\com\smr\googlerestore\MainActivity.java")
$classFiles=@(Get-ChildItem "$build\classes" -Recurse -Filter '*.class' | ForEach-Object FullName)
Invoke-Checked "$sdkTools\d8.bat" (@('--min-api','26','--lib',$platformJar,'--output',"$build\dex")+$classFiles)
$unsigned="$build\unsigned.apk"
Invoke-Checked "$sdkTools\aapt.exe" @('package','-f','-M',"$projectRoot\AndroidManifest.xml",'-S',"$projectRoot\res",'-A',"$projectRoot\assets",'-I',$platformJar,'-0','zip','-F',$unsigned)
Push-Location "$build\dex"
try { Invoke-Checked "$sdkTools\aapt.exe" @('add',$unsigned,'classes.dex') } finally { Pop-Location }
Invoke-Checked "$sdkTools\zipalign.exe" @('-f','4',$unsigned,"$build\aligned.apk")
$signing=Join-Path $projectRoot '.signing'
New-Item -ItemType Directory -Path $signing -Force | Out-Null
$key="$signing\restore.jks"
$passFile="$signing\password.txt"
if (!(Test-Path $key)) {
  if (Test-Path $passFile) { throw 'Signing password exists without key; inspect manually' }
  [IO.File]::WriteAllText($passFile,([Guid]::NewGuid().ToString('N')),[Text.UTF8Encoding]::new($false))
  Invoke-Checked "$JavaRoot\bin\keytool.exe" @('-genkeypair','-keystore',$key,'-storepass:file',$passFile,'-keypass:file',$passFile,'-alias','restore','-keyalg','RSA','-keysize','2048','-validity','10000','-dname','CN=Local Google Restore')
}
$apk="$out\GoogleRestore.apk"
Invoke-Checked "$sdkTools\apksigner.bat" @('sign','--ks',$key,'--ks-key-alias','restore','--ks-pass',"file:$passFile",'--out',$apk,"$build\aligned.apk")
Invoke-Checked "$sdkTools\apksigner.bat" @('verify','--verbose',$apk)
Get-Item $apk | Select-Object FullName,Length
