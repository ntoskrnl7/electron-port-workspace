param(
  [string]$BaseDir,
  [string]$ConfigsDir = (Join-Path $HOME '.electron_build_tools\configs'),
  [string]$Branch = 'main',
  [switch]$Sync,
  [switch]$SetCurrent,
  [switch]$ForceConfig,
  [switch]$UseSsh
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $BaseDir) { $BaseDir = (Resolve-Path (Join-Path $ScriptDir '..')).Path }

function Invoke-Logged {
  param(
    [Parameter(Position = 0, Mandatory = $true)]
    [string]$Exe,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
  )
  Write-Host "+ $Exe $($Arguments -join ' ')"
  $exe = $Exe
  if ($exe -eq 'e' -and $env:OS -eq 'Windows_NT') {
    $eCmd = Get-Command e.cmd -ErrorAction SilentlyContinue
    if ($eCmd) {
      $exe = $eCmd.Source
    }
  }
  & $exe @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "command failed with exit code $LASTEXITCODE`: $Exe $($Arguments -join ' ')"
  }
}

function Write-IfChanged {
  param([string]$Path, [string]$Content, [switch]$Force)
  $parent = Split-Path -Parent $Path
  if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  if (Test-Path -LiteralPath $Path) {
    $existing = Get-Content -LiteralPath $Path -Raw
    if ($existing -eq $Content) {
      Write-Host "+ already up to date: $Path"
      return
    }
    if (-not $Force) {
      throw "file exists with different content: $Path. Re-run with -ForceConfig to replace it."
    }
  }
  [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
  Write-Host "+ wrote $Path"
}

$workspaceName = 'main'
$root = Join-Path $BaseDir $workspaceName
$releaseConfig = "$workspaceName-release"
$testingConfig = "$workspaceName-testing"
$releaseConfigFile = Join-Path $ConfigsDir "evm.$releaseConfig.json"
$testingConfigFile = Join-Path $ConfigsDir "evm.$testingConfig.json"
$currentFile = Join-Path $ConfigsDir 'evm-current.txt'
$electronOrigin = if ($UseSsh) { 'git@github.com:electron/electron.git' } else { 'https://github.com/electron/electron.git' }

New-Item -ItemType Directory -Force -Path $root, $ConfigsDir | Out-Null

$gclient = @"
solutions = [
  { "name"        : 'src/electron',
    "url"         : '$electronOrigin',
    "deps_file"   : 'DEPS',
    "managed"     : False,
    "custom_deps" : {
    },
    "custom_vars": {},
  },
]
"@
Write-IfChanged -Path (Join-Path $root '.gclient') -Content $gclient -Force:$ForceConfig

function New-ConfigJson {
  param([string]$ImportName, [string]$OutName)
  $schemaPath = (Join-Path $HOME '.electron_build_tools\evm-config.schema.json') -replace '\\', '/'
  [ordered]@{
    '$schema' = "file:///$schemaPath"
    root = $root
    remotes = @{ electron = @{ origin = $electronOrigin } }
    gen = @{
      args = @(
        "import(`"//electron/build/args/$ImportName.gn`")",
        'use_remoteexec = false',
        'use_reclient = false',
        'use_siso = true'
      )
      out = $OutName
    }
    preserveSDK = 5
    env = @{
      CHROMIUM_BUILDTOOLS_PATH = (Join-Path $root 'src\buildtools')
      GIT_CACHE_PATH = (Join-Path $HOME '.git_cache')
    }
  } | ConvertTo-Json -Depth 8
}

Write-IfChanged -Path $releaseConfigFile -Content (New-ConfigJson release Release) -Force:$ForceConfig
Write-IfChanged -Path $testingConfigFile -Content (New-ConfigJson testing Testing) -Force:$ForceConfig

if ($SetCurrent) {
  [System.IO.File]::WriteAllText($currentFile, "$releaseConfig`n", [System.Text.UTF8Encoding]::new($false))
  Write-Host "+ wrote $currentFile"
}

if ($Sync) {
  Invoke-Logged e "--config=$releaseConfig" sync
  $electronDir = Join-Path $root 'src\electron'
  if (Test-Path -LiteralPath (Join-Path $electronDir '.git')) {
    Invoke-Logged git -C $electronDir fetch origin $Branch
    Invoke-Logged git -C $electronDir checkout $Branch
    Invoke-Logged git -C $electronDir pull --ff-only origin $Branch
  } else {
    Write-Warning "sync completed but Electron checkout was not found: $electronDir"
  }
}

@"

Done.
Workspace:
  $root

Configs:
  $releaseConfig
  $testingConfig
"@ | Write-Host
