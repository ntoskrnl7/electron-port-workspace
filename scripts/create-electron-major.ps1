param(
  [Parameter(Position = 0, Mandatory = $true)]
  [ValidatePattern('^[0-9]+$')]
  [string]$Major,

  [string]$BaseDir,
  [string]$ConfigsDir = (Join-Path $HOME '.electron_build_tools\configs'),
  [string]$Tag,
  [switch]$Sync,
  [switch]$SetCurrent,
  [switch]$ForceConfig,
  [switch]$NoGitCache,
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
  param(
    [string]$Path,
    [string]$Content,
    [switch]$Force
  )

  $parent = Split-Path -Parent $Path
  if ($parent) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }

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

function Initialize-ElectronCheckoutAtTag {
  param([string]$CheckoutTag)

  $electronParent = Split-Path -Parent $electronDir
  if (Test-Path -LiteralPath $electronDir) {
    if (-not (Test-Path -LiteralPath (Join-Path $electronDir '.git'))) {
      throw "Electron checkout path exists but is not a git repo: $electronDir"
    }
    return
  }

  Write-Host "Electron checkout is not present; bootstrapping Electron at $CheckoutTag before sync."
  New-Item -ItemType Directory -Force -Path $electronParent | Out-Null
  Invoke-Logged git init $electronDir
  Invoke-Logged git -C $electronDir remote add origin $electronOrigin
  Invoke-Logged git -C $electronDir fetch --no-tags --filter=blob:none origin "refs/tags/$CheckoutTag`:refs/tags/$CheckoutTag"
  Invoke-Logged git -C $electronDir checkout $CheckoutTag
}

$root = Join-Path $BaseDir $Major
$releaseConfig = "$Major-release"
$testingConfig = "$Major-testing"
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
  $configEnv = [ordered]@{
    CHROMIUM_BUILDTOOLS_PATH = (Join-Path $root 'src\buildtools')
  }
  if (-not $NoGitCache) {
    $gitCachePath = if ($env:ELECTRON_WORKSPACE_GIT_CACHE_PATH) {
      $env:ELECTRON_WORKSPACE_GIT_CACHE_PATH
    } else {
      Join-Path $HOME '.git_cache'
    }
    $configEnv.GIT_CACHE_PATH = $gitCachePath
  }
  $config = [ordered]@{
    '$schema' = "file:///$schemaPath"
    root = $root
    remotes = @{
      electron = @{
        origin = $electronOrigin
      }
    }
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
    env = $configEnv
  }
  return ($config | ConvertTo-Json -Depth 8)
}

Write-IfChanged -Path $releaseConfigFile -Content (New-ConfigJson -ImportName release -OutName Release) -Force:$ForceConfig
Write-IfChanged -Path $testingConfigFile -Content (New-ConfigJson -ImportName testing -OutName Testing) -Force:$ForceConfig

if ($SetCurrent) {
  [System.IO.File]::WriteAllText($currentFile, "$releaseConfig`n", [System.Text.UTF8Encoding]::new($false))
  Write-Host "+ wrote $currentFile"
}

$electronDir = Join-Path $root 'src\electron'
if ($Tag) {
  if (-not (Test-Path -LiteralPath (Join-Path $electronDir '.git'))) {
    Initialize-ElectronCheckoutAtTag $Tag
  } else {
    Invoke-Logged git -C $electronDir fetch --no-tags origin "refs/tags/$Tag`:refs/tags/$Tag"
    Invoke-Logged git -C $electronDir checkout $Tag
  }
}

if ($Sync) {
  Invoke-Logged e "--config=$releaseConfig" sync
}

@"

Done.
Workspace:
  $root

Configs:
  $releaseConfig
  $testingConfig

Next commands:
  cd $root\src
  e --config=$releaseConfig build -local_jobs 2
  e --config=$releaseConfig build -local_jobs 2 -t electron:electron_dist_zip
"@ | Write-Host
