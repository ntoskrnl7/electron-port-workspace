param(
  [string]$Target = $env:ELECTRON_WORKSPACE_TARGET,
  [string]$Tag,
  [string[]]$Ports = @(),
  [string]$BaseDir,
  [string]$SrcRoot,
  [string]$ConfigName,
  [string]$BranchName,
  [string]$BackupBranchName,
  [switch]$NoSync,
  [switch]$NoBackup,
  [switch]$NoBranch,
  [switch]$SkipCheckout,
  [switch]$Build,
  [switch]$IncludeWidevineCdm,
  [switch]$NoEUse,
  [string[]]$PackageArgs = @(),
  [switch]$Help
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $BaseDir) { $BaseDir = (Resolve-Path (Join-Path $ScriptDir '..')).Path }

function Show-Usage {
  @'
Usage:
  upgrade-electron-target.ps1 -Target <target> -Tag <tag> [options]

Examples:
  scripts\upgrade-electron-target.ps1 `
    -Target 42 `
    -Tag v42.1.0 `
    -Ports print-request-handler,vaapi-hevc-wip,widevine-cdm,preload,text-caret-info,user-agent-override,dispatch-input-event,picture-in-picture-handle-api `
    -Build `
    -IncludeWidevineCdm

Options:
  -Target <target>        Workspace target under <base-dir>, for example 42.
                          Defaults to ELECTRON_WORKSPACE_TARGET when set.
  -Tag <tag>              Electron upstream tag to check out, for example v42.1.0.
  -Ports <list>           Port bundles to apply in order. Accepts a PowerShell
                          array or comma-separated names.
  -BaseDir <path>         Workspace root. Default: parent of this script dir.
  -SrcRoot <path>         Chromium src root. Default: <base-dir>\<target>\src.
  -ConfigName <name>      Build-tools config. Default: <target>-release.
  -BranchName <name>      Work branch created in both repos after sync.
                          Default: upgrade/<target>-<tag>-<timestamp>.
  -BackupBranchName <n>   Backup branch created in both repos before checkout.
                          Default: backup/<target>-before-<tag>-<timestamp>.
  -NoSync                 Skip e --config=<config> sync after tag checkout.
  -NoBackup               Do not create backup branches.
  -NoBranch               Do not create a new work branch after sync.
  -SkipCheckout           Do not check out the Electron tag, do not move
                          Chromium, and do not sync. Use only to continue after
                          the workspace is already at the desired clean base.
  -Build                  Run build-dev-electron-npm.ps1 after applying ports.
  -IncludeWidevineCdm     Pass Widevine packaging flags to the build script.
  -NoEUse                 Do not run e use <config> before building.
  -PackageArgs <args>     Extra arguments forwarded to the build script.
  -Help                   Show this help.
'@ | Write-Host
}

if ($Help) {
  Show-Usage
  exit 0
}

if (-not $Target) { throw '-Target is required, or set ELECTRON_WORKSPACE_TARGET.' }
if (-not $Tag) { throw '-Tag is required, for example v42.1.0.' }
if ($Target -match '[\\/]') { throw "target must not contain slash: $Target" }

if (-not $SrcRoot) { $SrcRoot = Join-Path $BaseDir "$Target\src" }
if (-not $ConfigName) { $ConfigName = "$Target-release" }

$ElectronDir = Join-Path $SrcRoot 'electron'
$PortBundleScript = Join-Path $ScriptDir 'port-bundle.ps1'
$BuildScript = Join-Path $ScriptDir 'build-dev-electron-npm.ps1'

function Get-SafeTagName {
  param([string]$Value)
  ($Value -replace '[^A-Za-z0-9._-]+', '-').Trim('-')
}

function Get-Timestamp {
  (Get-Date).ToString('yyyyMMdd-HHmmss')
}

function Format-Command {
  param([string]$FilePath, [string[]]$Arguments)
  "$FilePath $($Arguments -join ' ')".Trim()
}

function Invoke-Logged {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [string[]]$Arguments = @()
  )

  $exe = $FilePath
  $actualArguments = $Arguments
  if ($exe -eq 'e' -and $env:OS -eq 'Windows_NT') {
    $eCmd = Get-Command e.cmd -ErrorAction SilentlyContinue
    if ($eCmd) { $exe = $eCmd.Source }
  } elseif ($exe.EndsWith('.ps1', [System.StringComparison]::OrdinalIgnoreCase)) {
    $actualArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $exe) + $Arguments
    $exe = 'powershell'
  }

  Write-Host "+ $(Format-Command $exe $actualArguments)"
  & $exe @actualArguments
  if ($LASTEXITCODE -ne 0) {
    throw "command failed with exit code $LASTEXITCODE`: $(Format-Command $exe $actualArguments)"
  }
}

function Get-CommandOutput {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [string[]]$Arguments = @()
  )

  $output = & $FilePath @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "command failed with exit code $LASTEXITCODE`: $(Format-Command $FilePath $Arguments)"
  }
  return ($output -join "`n").Trim()
}

function Test-GitOk {
  param([string]$RepoDir, [string[]]$Arguments)
  & git -C $RepoDir @Arguments *> $null
  return ($LASTEXITCODE -eq 0)
}

function Test-GitRefExists {
  param([string]$RepoDir, [string]$Ref)
  Test-GitOk $RepoDir @('rev-parse', '--verify', '--quiet', $Ref)
}

function Assert-GitRepo {
  param([string]$RepoDir)
  if (-not (Test-GitOk $RepoDir @('rev-parse', '--is-inside-work-tree'))) {
    throw "not a git repo: $RepoDir"
  }
}

function Assert-CleanWorktree {
  param([string]$RepoDir)
  if (-not (Test-GitOk $RepoDir @('diff', '--quiet'))) {
    throw "worktree has unstaged changes: $RepoDir"
  }
  if (-not (Test-GitOk $RepoDir @('diff', '--cached', '--quiet'))) {
    throw "worktree has staged changes: $RepoDir"
  }
}

function Assert-CleanOrGitlinkChangesOnly {
  param([string]$RepoDir)
  if (-not (Test-GitOk $RepoDir @('diff', '--cached', '--quiet'))) {
    throw "worktree has staged changes: $RepoDir"
  }
  if (Test-GitOk $RepoDir @('diff', '--quiet')) { return }

  $rawText = Get-CommandOutput git @('-C', $RepoDir, 'diff', '--raw', '--no-ext-diff')
  foreach ($line in ($rawText -split "`n")) {
    $line = $line.TrimEnd("`r")
    if (-not $line) { continue }

    $fields = $line -split "`t", 2
    if ($fields.Count -lt 2 -or -not $fields[1]) {
      throw "could not parse gitlink path from raw diff in $RepoDir`: $line"
    }

    $meta = $fields[0]
    $path = $fields[1]
    $parts = $meta -split '\s+'
    if ($parts.Count -lt 5) {
      throw "could not parse raw diff line in $RepoDir`: $line"
    }
    $oldMode = $parts[0].TrimStart(':')
    $newMode = $parts[1]
    $newOid = $parts[3]
    $status = $parts[4]
    if ($oldMode -ne '160000' -or $newMode -ne '160000' -or $status -ne 'M' -or $newOid -notmatch '^0+$') {
      throw "worktree has non-dirty-gitlink unstaged changes: $RepoDir"
    }

    $nestedPath = Join-Path $RepoDir $path
    try {
      $nestedTop = Get-CommandOutput git @('-C', $nestedPath, 'rev-parse', '--show-toplevel')
    } catch {
      throw "gitlink path is not a nested git repo: $nestedPath"
    }

    $nestedPathReal = (Resolve-Path -LiteralPath $nestedPath).ProviderPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $nestedTopReal = (Resolve-Path -LiteralPath $nestedTop).ProviderPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    if ($nestedPathReal -ine $nestedTopReal) {
      throw "gitlink path resolves to a parent repo instead of a nested repo: $nestedPath"
    }
    if (-not (Test-GitOk $nestedPath @('diff', '--quiet'))) {
      throw "nested gitlink repo has unstaged changes: $nestedPath"
    }
    if (-not (Test-GitOk $nestedPath @('diff', '--cached', '--quiet'))) {
      throw "nested gitlink repo has staged changes: $nestedPath"
    }
  }

  Write-Host "Worktree has only clean gitlink dirty markers; continuing: $RepoDir"
}

function Assert-NoGitOperation {
  param([string]$RepoDir)
  $gitDir = Get-CommandOutput git @('-C', $RepoDir, 'rev-parse', '--path-format=absolute', '--git-dir')
  $paths = @(
    'rebase-apply',
    'rebase-merge',
    'MERGE_HEAD',
    'CHERRY_PICK_HEAD',
    'REVERT_HEAD'
  )
  foreach ($path in $paths) {
    if (Test-Path -LiteralPath (Join-Path $gitDir $path)) {
      throw "git operation is already in progress in $RepoDir`: $path"
    }
  }
}

function New-GitBranchAtHead {
  param([string]$RepoDir, [string]$Name)
  if (Test-GitRefExists $RepoDir "refs/heads/$Name") {
    throw "branch already exists in $RepoDir`: $Name"
  }
  Invoke-Logged git @('-C', $RepoDir, 'branch', $Name, 'HEAD')
}

function Switch-NewBranch {
  param([string]$RepoDir, [string]$Name)
  if (Test-GitRefExists $RepoDir "refs/heads/$Name") {
    throw "branch already exists in $RepoDir`: $Name"
  }
  Invoke-Logged git @('-C', $RepoDir, 'switch', '-c', $Name)
}

function Normalize-Ports {
  param([string[]]$Values)
  $result = @()
  foreach ($value in $Values) {
    foreach ($part in ($value -split ',')) {
      $name = $part.Trim()
      if ($name) { $result += $name }
    }
  }
  return $result
}

function Archive-PortBundleStateForTarget {
  param(
    [string]$RepoDir,
    [string]$BundleTarget,
    [string]$SafeTag,
    [string]$Timestamp
  )

  $stateDir = Get-CommandOutput git @('-C', $RepoDir, 'rev-parse', '--path-format=absolute', '--git-path', 'port-bundles')
  if (-not (Test-Path -LiteralPath $stateDir)) { return }

  $states = @(Get-ChildItem -LiteralPath $stateDir -Filter "*.$BundleTarget.state" -File -ErrorAction SilentlyContinue)
  if ($states.Count -eq 0) { return }

  $archiveDir = Join-Path $stateDir "archive-before-$SafeTag-$Timestamp"
  New-Item -ItemType Directory -Force -Path $archiveDir | Out-Null

  foreach ($state in $states) {
    $destination = Join-Path $archiveDir $state.Name
    Write-Host "+ Move-Item -LiteralPath $($state.FullName) -Destination $destination"
    Move-Item -LiteralPath $state.FullName -Destination $destination
  }
}

function Get-ElectronChromiumVersion {
  $depsPath = Join-Path $ElectronDir 'DEPS'
  if (-not (Test-Path -LiteralPath $depsPath)) {
    throw "missing Electron DEPS file: $depsPath"
  }

  $lines = Get-Content -LiteralPath $depsPath
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -notmatch "'chromium_version'\s*:") { continue }
    if ($lines[$i] -match ":\s*'([^']+)'") {
      return $Matches[1]
    }
    for ($j = $i + 1; $j -lt [Math]::Min($i + 4, $lines.Count); $j++) {
      if ($lines[$j] -match "'([^']+)'") {
        return $Matches[1]
      }
    }
  }

  throw "could not find chromium_version in $depsPath"
}

Assert-GitRepo $SrcRoot
Assert-GitRepo $ElectronDir
if (-not (Test-Path -LiteralPath $PortBundleScript)) { throw "missing script: $PortBundleScript" }
if ($Build -and -not (Test-Path -LiteralPath $BuildScript)) { throw "missing script: $BuildScript" }

if ($SkipCheckout) {
  Assert-CleanOrGitlinkChangesOnly $SrcRoot
} else {
  Assert-CleanWorktree $SrcRoot
}
Assert-CleanWorktree $ElectronDir
Assert-NoGitOperation $SrcRoot
Assert-NoGitOperation $ElectronDir

$timestamp = Get-Timestamp
$safeTag = Get-SafeTagName $Tag
if (-not $BranchName) { $BranchName = "upgrade/$Target-$safeTag-$timestamp" }
if (-not $BackupBranchName) { $BackupBranchName = "backup/$Target-before-$safeTag-$timestamp" }
$portNames = Normalize-Ports $Ports

Write-Host "Upgrade target: $Target"
Write-Host "Electron tag: $Tag"
Write-Host "Source root: $SrcRoot"
Write-Host "Config: $ConfigName"
Write-Host "Ports: $(if ($portNames.Count) { $portNames -join ', ' } else { '(none)' })"
if (-not $NoBackup) { Write-Host "Backup branch: $BackupBranchName" }
if (-not $NoBranch) { Write-Host "Work branch: $BranchName" }

if (-not $NoBackup) {
  New-GitBranchAtHead $SrcRoot $BackupBranchName
  New-GitBranchAtHead $ElectronDir $BackupBranchName
}

if (-not $SkipCheckout) {
  Invoke-Logged git @('-C', $ElectronDir, 'fetch', '--no-tags', 'origin', "refs/tags/$Tag`:refs/tags/$Tag")
  Invoke-Logged git @('-C', $ElectronDir, 'checkout', $Tag)

  $chromiumVersion = Get-ElectronChromiumVersion
  Write-Host "Chromium revision from Electron DEPS: $chromiumVersion"
  Invoke-Logged git @('-C', $SrcRoot, 'fetch', '--no-tags', 'origin', "refs/tags/$chromiumVersion`:refs/tags/$chromiumVersion")
  Invoke-Logged git @('-C', $SrcRoot, 'switch', '--detach', $chromiumVersion)

  if (-not $NoSync) {
    Invoke-Logged e @("--config=$ConfigName", 'sync')
  }
} elseif (-not $NoSync) {
  Write-Host 'Skipping checkout and sync because -SkipCheckout was set.'
}

Assert-CleanOrGitlinkChangesOnly $SrcRoot
Assert-CleanWorktree $ElectronDir
Assert-NoGitOperation $SrcRoot
Assert-NoGitOperation $ElectronDir

if (-not $NoBranch) {
  Switch-NewBranch $SrcRoot $BranchName
  Switch-NewBranch $ElectronDir $BranchName
}

Archive-PortBundleStateForTarget -RepoDir $SrcRoot -BundleTarget $Target -SafeTag $safeTag -Timestamp $timestamp
Archive-PortBundleStateForTarget -RepoDir $ElectronDir -BundleTarget $Target -SafeTag $safeTag -Timestamp $timestamp

foreach ($port in $portNames) {
  Invoke-Logged -FilePath $PortBundleScript -Arguments @(
    'apply',
    $port,
    '-Target',
    $Target,
    '-SrcRoot',
    $SrcRoot,
    '-BaseDir',
    $BaseDir
  )
}

if ($Build) {
  if (-not $NoEUse) {
    Invoke-Logged e @('use', $ConfigName)
  }

  $buildArgs = @('-Target', $Target)
  if ($IncludeWidevineCdm) {
    $buildArgs += @('--include-widevine-cdm', '--widevine-license-ack')
  }
  $buildArgs += $PackageArgs
  Invoke-Logged -FilePath $BuildScript -Arguments $buildArgs
}

Write-Host ''
Write-Host 'Done.'
Write-Host "Chromium repo: $SrcRoot"
Write-Host "Electron repo: $ElectronDir"
if (-not $NoBranch) { Write-Host "Work branch: $BranchName" }
