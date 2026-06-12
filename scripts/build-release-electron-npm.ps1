param(
  [string]$Target = $env:ELECTRON_WORKSPACE_TARGET,
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$PackageArgs
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Target) { $Target = '41' }
$srcDir = if ($env:ELECTRON_WORKSPACE_SRC_DIR) {
  $env:ELECTRON_WORKSPACE_SRC_DIR
} else {
  Join-Path (Resolve-Path (Join-Path $ScriptDir '..')).Path "$Target\src"
}

function Invoke-NativeCommand {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [string[]]$Arguments = @(),
    [string]$Name = $FilePath
  )

  $previousErrorActionPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    & $FilePath @Arguments
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }

  if ($exitCode -ne 0) {
    throw "$Name failed with exit code $exitCode"
  }
}

function Test-Truthy {
  param([object]$Value)
  if ($Value -eq $true) { return $true }
  if (-not $Value) { return $false }
  return [regex]::IsMatch([string]$Value, '^(1|true|yes|on)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

function Get-PackageArgValue {
  param(
    [string[]]$ArgList,
    [string]$Name
  )

  $flag = "--$Name"
  for ($i = 0; $i -lt $ArgList.Count; $i++) {
    $arg = $ArgList[$i]
    if ($arg -eq $flag) {
      if (($i + 1) -lt $ArgList.Count -and -not $ArgList[$i + 1].StartsWith('--')) {
        return $ArgList[$i + 1]
      }
      return 'true'
    }
    if ($arg.StartsWith("$flag=")) {
      return $arg.Substring($flag.Length + 1)
    }
  }

  return $null
}

function Resolve-WidevineCdmForPackage {
  $includeWidevine = (Test-Truthy $env:ELECTRON_PACKAGE_INCLUDE_WIDEVINE_CDM) -or
    (Test-Truthy (Get-PackageArgValue -ArgList $PackageArgs -Name 'include-widevine-cdm'))
  if (-not $includeWidevine) { return }

  $explicitCdmDir = $env:ELECTRON_PACKAGE_WIDEVINE_CDM_DIR
  if (-not $explicitCdmDir) {
    $explicitCdmDir = Get-PackageArgValue -ArgList $PackageArgs -Name 'widevine-cdm-dir'
  }
  if ($explicitCdmDir) { return }

  $licenseAccepted = (Test-Truthy $env:ELECTRON_PACKAGE_WIDEVINE_LICENSE_ACK) -or
    (Test-Truthy (Get-PackageArgValue -ArgList $PackageArgs -Name 'widevine-license-ack'))
  if (-not $licenseAccepted) {
    throw 'Widevine packaging was requested, but license acknowledgement is missing. Pass --widevine-license-ack or set ELECTRON_PACKAGE_WIDEVINE_LICENSE_ACK=1.'
  }

  $resolver = Join-Path $ScriptDir 'resolve-widevine-cdm.ps1'
  $resolved = & $resolver -Target $Target -SrcDir $srcDir -LicenseAck -DownloadIfMissing -PreferDownload -RequireChromeMajorMatch -Force | Select-Object -Last 1
  if (-not $resolved -or -not (Test-Path -LiteralPath $resolved)) {
    throw "Widevine resolver did not produce a valid CDM directory: $resolved"
  }
  $env:ELECTRON_PACKAGE_WIDEVINE_CDM_DIR = [string]$resolved
  $env:ELECTRON_PACKAGE_WIDEVINE_LICENSE_ACK = '1'
  Write-Host "Resolved target Chromium Widevine CDM: $resolved"
}

Resolve-WidevineCdmForPackage

Push-Location $srcDir
try {
  $electronBuildTools = if ($IsWindows -or $env:OS -eq 'Windows_NT') { 'e.cmd' } else { 'e' }
  $buildArgs = @('--target', 'electron:electron_dist_zip')
  if ($env:ELECTRON_BUILD_NO_REMOTE -eq '1') { $buildArgs += '--no-remote' }
  if ($env:ELECTRON_BUILD_LOCAL_JOBS) {
    $buildArgs += @('-local_jobs', $env:ELECTRON_BUILD_LOCAL_JOBS)
  } elseif ($env:ELECTRON_BUILD_JOBS) {
    $buildArgs += @('-j', $env:ELECTRON_BUILD_JOBS)
  }
  if ($env:ELECTRON_BUILD_NO_REMOTE -ne '1' -and $env:ELECTRON_BUILD_REMOTE_JOBS -match '^[1-9][0-9]*$') {
    $buildArgs += @('-remote_jobs', $env:ELECTRON_BUILD_REMOTE_JOBS)
  }

  Invoke-NativeCommand -FilePath $electronBuildTools -Arguments (@('build') + $buildArgs) -Name 'e build'

  Invoke-NativeCommand -FilePath 'npm.cmd' -Arguments @('--prefix', 'electron', 'run', 'create-typescript-definitions') -Name 'npm create-typescript-definitions'

  $packageCommandArgs = @(
    (Join-Path $ScriptDir 'package-electron-npm.js'),
    '--mode', 'release',
    '--src-dir', $srcDir
  ) + $PackageArgs
  Invoke-NativeCommand -FilePath 'node' -Arguments $packageCommandArgs -Name 'package-electron-npm.js'
} finally {
  Pop-Location
}
