param(
  [Parameter(Position = 0, Mandatory = $true)]
  [ValidateSet('list', 'export', 'apply', 'undo', 'drop', 'status')]
  [string]$Command,

  [Parameter(Position = 1)]
  [string]$PortName,

  [string]$Target,
  [Alias('base-dir')]
  [string]$BaseDir,
  [Alias('src-root')]
  [string]$SrcRoot,
  [string]$Repos = 'auto',

  [Alias('chromium-base')]
  [string]$ChromiumBase,
  [Alias('chromium-head')]
  [string]$ChromiumHead,
  [Alias('chromium-direct-only')]
  [switch]$ChromiumDirectOnly,
  [Alias('electron-base')]
  [string]$ElectronBase,
  [Alias('electron-head')]
  [string]$ElectronHead,
  [Alias('electronized-chromium-patches')]
  [switch]$ElectronizedChromiumPatches,
  [Alias('depends-on')]
  [string]$DependsOn,
  [switch]$Clear,
  [Alias('ignore-dependencies')]
  [switch]$IgnoreDependencies,

  [Alias('backup-branch')]
  [switch]$BackupBranch,
  [Alias('backup-branch-name')]
  [string]$BackupBranchName
)

$ErrorActionPreference = 'Stop'
$DependsOnSpecified = $PSBoundParameters.ContainsKey('DependsOn')
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $BaseDir) { $BaseDir = (Resolve-Path (Join-Path $ScriptDir '..')).Path }
if (-not $SrcRoot) {
  $defaultTarget = if ($Target) { $Target } else { '41' }
  $SrcRoot = Join-Path $BaseDir "$defaultTarget\src"
}

function Invoke-Logged {
  Write-Host "+ $($args -join ' ')"
  & $args[0] @($args | Select-Object -Skip 1)
  if ($LASTEXITCODE -ne 0) {
    throw "command failed with exit code $LASTEXITCODE`: $($args -join ' ')"
  }
}

function Get-CommandOutput {
  $output = & $args[0] @($args | Select-Object -Skip 1)
  if ($LASTEXITCODE -ne 0) {
    throw "command failed with exit code $LASTEXITCODE`: $($args -join ' ')"
  }
  return ($output -join "`n").Trim()
}

function Test-ExternalOk {
  & $args[0] @($args | Select-Object -Skip 1) *> $null
  return ($LASTEXITCODE -eq 0)
}

function Copy-Logged {
  param([string]$Source, [string]$Destination)
  Write-Host "+ Copy-Item -LiteralPath $Source -Destination $Destination"
  Copy-Item -LiteralPath $Source -Destination $Destination
}

function Assert-Name {
  param([string]$Name, [string]$Kind)
  if (-not $Name) { throw "$Kind is required" }
  if ($Name -match '/') { throw "$Kind must not contain slash: $Name" }
  if ($Name -notmatch '^[A-Za-z0-9._-]+$') { throw "$Kind may contain only A-Za-z0-9._-" }
  return $Name
}

function Convert-PortList {
  param([string]$Value)
  if (-not $Value) { return '' }
  $names = @()
  foreach ($name in $Value.Split(',')) {
    $trimmed = $name.Trim()
    if (-not $trimmed) { continue }
    $names += (Assert-Name $trimmed 'port dependency')
  }
  return ($names -join ',')
}

function Get-PortDir {
  param([string]$Name, [string]$BundleTarget)
  Join-Path (Join-Path $BaseDir 'ports') (Join-Path $Name $BundleTarget)
}

function Get-RepoPath {
  param([ValidateSet('chromium', 'electron')][string]$Repo)
  if ($Repo -eq 'chromium') { return $SrcRoot }
  return (Join-Path $SrcRoot 'electron')
}

function Assert-GitRepo {
  param([string]$RepoDir)
  $gitPath = Join-Path $RepoDir '.git'
  if (-not (Test-Path -LiteralPath $gitPath)) {
    throw "not a git repo: $RepoDir"
  }
}

function Assert-CleanWorktree {
  param([string]$RepoDir)
  if (-not (Test-ExternalOk git -C $RepoDir diff --quiet)) {
    throw "worktree has unstaged changes: $RepoDir"
  }
  if (-not (Test-ExternalOk git -C $RepoDir diff --cached --quiet)) {
    throw "worktree has staged changes: $RepoDir"
  }
}

function Assert-NoAmInProgress {
  param([string]$RepoDir)
  $gitDir = Get-CommandOutput git -C $RepoDir rev-parse --git-dir
  if (-not [System.IO.Path]::IsPathRooted($gitDir)) {
    $gitDir = Join-Path $RepoDir $gitDir
  }
  if (Test-Path -LiteralPath (Join-Path $gitDir 'rebase-apply')) {
    throw "git am is already in progress in $RepoDir"
  }
}

function Get-GitConfigOrEmpty {
  param([string]$RepoDir, [string]$Key)
  $output = & git -C $RepoDir config --get $Key 2>$null
  if ($LASTEXITCODE -ne 0) { return '' }
  return ($output -join "`n").Trim()
}

function Ensure-GitIdentity {
  param([string]$RepoDir)
  if (-not (Get-GitConfigOrEmpty $RepoDir 'user.name')) {
    Invoke-Logged git -C $RepoDir config user.name 'Electron Scripts'
  }
  if (-not (Get-GitConfigOrEmpty $RepoDir 'user.email')) {
    Invoke-Logged git -C $RepoDir config user.email 'scripts@electron'
  }
}

function Invoke-GitAm {
  param([string]$RepoDir, [string]$Patch)
  Ensure-GitIdentity $RepoDir
  Write-Host "+ git -C $RepoDir am -3 $Patch"
  & git -C $RepoDir am -3 $Patch
  if ($LASTEXITCODE -eq 0) { return }

  $message = @"

Patch failed: $Patch
Resolve conflicts in $RepoDir, then run:
  git -C "$RepoDir" am --continue

Or abort this apply:
  git -C "$RepoDir" am --abort

No applied-state file was written for this repo.
"@
  throw $message.Trim()
}

function Get-StateName {
  param([string]$Name, [string]$BundleTarget)
  "$Name.$BundleTarget"
}

function Get-StateFile {
  param([string]$RepoDir, [string]$StateName)
  $stateDir = Get-CommandOutput git -C $RepoDir rev-parse --path-format=absolute --git-path port-bundles
  Join-Path $stateDir "$StateName.state"
}

function Get-TimestampForBranch {
  (Get-Date).ToString('yyyyMMdd-HHmmss')
}

function Get-PatchesForRepo {
  param([string]$PortDir, [ValidateSet('chromium', 'electron')][string]$Repo)
  $dir = Join-Path $PortDir $Repo
  if (-not (Test-Path -LiteralPath $dir)) { return @() }
  @(Get-ChildItem -LiteralPath $dir -Filter '*.patch' -File | Sort-Object Name | ForEach-Object { $_.FullName })
}

function Get-PatchFilenameFromFile {
  param([string]$Patch)
  $patchFilename = @(Get-Content -LiteralPath $Patch | Where-Object { $_.StartsWith('Patch-Filename: ') } | Select-Object -First 1)
  if ($patchFilename.Count -gt 0) {
    return $patchFilename[0].Substring('Patch-Filename: '.Length)
  }

  $subjectLine = @(Get-Content -LiteralPath $Patch | Where-Object { $_.StartsWith('Subject: ') } | Select-Object -First 1)
  $subject = if ($subjectLine.Count -gt 0) { $subjectLine[0].Substring('Subject: '.Length) } else { '' }
  $subject = $subject -replace '^\[PATCH\]\s+', ''
  $subject = $subject -replace '^\[PATCH\s+\d+/\d+\]\s+', ''
  $filename = ($subject.ToLowerInvariant() -replace '[^a-z0-9]+', '_') -replace '^_+', ''
  $filename = $filename -replace '_+$', ''
  if (-not $filename) { $filename = [System.IO.Path]::GetFileNameWithoutExtension($Patch) }
  "$filename.patch"
}

function Trim-TrailingWhitespaceInFile {
  param([string]$Path)
  $text = [System.IO.File]::ReadAllText($Path)
  $text = [regex]::Replace($text, '[ \t]+(?=\r?$)', '', [System.Text.RegularExpressions.RegexOptions]::Multiline)
  [System.IO.File]::WriteAllText($Path, $text, [System.Text.UTF8Encoding]::new($false))
}

function Normalize-PatchFiles {
  param([string]$PatchDir)
  if (-not (Test-Path -LiteralPath $PatchDir)) { return }
  foreach ($patch in Get-ChildItem -LiteralPath $PatchDir -Filter '*.patch' -File | Sort-Object Name) {
    Write-Host "+ normalize $($patch.FullName)"
    Trim-TrailingWhitespaceInFile $patch.FullName
  }
}

function Copy-DirectoryPatchesToElectronBundle {
  param([string]$SourceDir, [string]$PortDir)
  if (-not (Test-Path -LiteralPath $SourceDir)) { return }
  $destDir = Join-Path $PortDir 'electron'
  New-Item -ItemType Directory -Force -Path $destDir | Out-Null

  $existing = @(Get-ChildItem -LiteralPath $destDir -Filter '*.patch' -File |
    ForEach-Object {
      if ($_.Name -match '^(\d+)-') { [int]$Matches[1] }
    } | Sort-Object -Descending | Select-Object -First 1)
  $next = if ($existing.Count -gt 0) { $existing[0] + 1 } else { 1 }

  foreach ($patch in Get-ChildItem -LiteralPath $SourceDir -Filter '*.patch' -File | Sort-Object Name) {
    $suffix = $patch.Name -replace '^\d+-', ''
    $target = Join-Path $destDir ('{0:D4}-{1}' -f $next, $suffix)
    Copy-Logged $patch.FullName $target
    $next++
  }
}

function Convert-ChromiumPatchesToElectronBundle {
  param(
    [string]$Name,
    [string]$PatchDir,
    [string]$PortDir,
    [string]$ElectronPatchOutputDir
  )

  $electronDir = Get-RepoPath electron
  $chromiumPatchDir = Join-Path $electronDir 'patches\chromium'
  $patchList = Join-Path $chromiumPatchDir '.patches'

  Assert-GitRepo $electronDir
  Assert-CleanWorktree $electronDir

  $before = Get-CommandOutput git -C $electronDir rev-parse HEAD
  New-Item -ItemType Directory -Force -Path $chromiumPatchDir | Out-Null

  foreach ($patch in Get-ChildItem -LiteralPath $PatchDir -Filter '*.patch' -File | Sort-Object Name) {
    $filename = Get-PatchFilenameFromFile $patch.FullName
    $target = Join-Path $chromiumPatchDir $filename
    Copy-Logged $patch.FullName $target
    Write-Host "+ normalize $target"
    Trim-TrailingWhitespaceInFile $target

    $listed = $false
    if (Test-Path -LiteralPath $patchList) {
      $listed = @(Get-Content -LiteralPath $patchList | Where-Object { $_ -eq $filename }).Count -gt 0
    }
    if (-not $listed) {
      [System.IO.File]::AppendAllText($patchList, "$filename`n", [System.Text.UTF8Encoding]::new($false))
    }
  }

  Invoke-Logged git -C $electronDir add patches/chromium
  Ensure-GitIdentity $electronDir
  Invoke-Logged git -C $electronDir commit -m "patches: add $Name chromium patches"

  $after = Get-CommandOutput git -C $electronDir rev-parse HEAD
  New-Item -ItemType Directory -Force -Path $ElectronPatchOutputDir | Out-Null
  Invoke-Logged git -C $electronDir format-patch --keep-subject --no-signature -o $ElectronPatchOutputDir "$before..$after"
  Normalize-PatchFiles $ElectronPatchOutputDir

  return @{
    Before = $before
    After = $after
  }
}

function Get-ManifestValue {
  param([string]$PortDir, [string]$Key)
  $manifest = Join-Path $PortDir 'manifest.txt'
  if (-not (Test-Path -LiteralPath $manifest)) { return $null }
  $prefix = "$Key="
  $value = @(Get-Content -LiteralPath $manifest | Where-Object { $_.StartsWith($prefix) } | ForEach-Object { $_.Substring($prefix.Length).TrimEnd("`r") } | Select-Object -Last 1)
  if ($value.Count -eq 0) { return $null }
  return $value[0]
}

function Get-PortDependencies {
  param([string]$PortDir)
  $dependsOn = Get-ManifestValue $PortDir 'depends_on'
  if (-not $dependsOn) { return @() }
  $dependencies = @()
  foreach ($dependency in $dependsOn.Split(',')) {
    $trimmed = $dependency.Trim()
    if (-not $trimmed) { continue }
    $dependencies += (Assert-Name $trimmed 'port dependency')
  }
  return $dependencies
}

function Test-ElectronizedChromiumPort {
  param([string]$PortDir)
  (Get-ManifestValue $PortDir 'electronized_chromium_patches') -eq 'true'
}

function Test-ChromiumDirectElectronPatchStackPort {
  param([string]$PortDir)
  (Get-ManifestValue $PortDir 'electron_patch_stack_source') -eq 'chromium-direct'
}

function Test-SameFileContent {
  param([string]$Left, [string]$Right)
  if (-not (Test-Path -LiteralPath $Left) -or -not (Test-Path -LiteralPath $Right)) {
    return $false
  }
  (Get-FileHash -LiteralPath $Left -Algorithm SHA256).Hash -eq
    (Get-FileHash -LiteralPath $Right -Algorithm SHA256).Hash
}

function Read-StateValue {
  param([string]$Path, [string]$Key)
  $prefix = "$Key="
  @(Get-Content -LiteralPath $Path | Where-Object { $_.StartsWith($prefix) } | ForEach-Object { $_.Substring($prefix.Length) } | Select-Object -Last 1)[0]
}

function Write-Manifest {
  param([string]$PortDir, [string]$Name, [string]$BundleTarget, [string[]]$Lines)
  $content = @(
    'schema_version=1',
    "name=$Name",
    "target=$BundleTarget"
  ) + $Lines
  [System.IO.File]::WriteAllLines((Join-Path $PortDir 'manifest.txt'), $content, [System.Text.UTF8Encoding]::new($false))
}

function Write-DefaultReadmes {
  param([string]$Name, [string]$BundleTarget, [string]$PortDir)
  $featureDir = Join-Path (Join-Path $BaseDir 'ports') $Name
  $featureReadme = Join-Path $featureDir 'README.md'
  if (-not (Test-Path -LiteralPath $featureReadme)) {
    $content = @"
# $Name

Reusable Electron feature port.

Target bundles live under:

````text
ports/$Name/<target>/
````
"@
    [System.IO.File]::WriteAllText($featureReadme, $content, [System.Text.UTF8Encoding]::new($false))
  }

  $targetReadme = Join-Path $PortDir 'README.md'
  if (-not (Test-Path -LiteralPath $targetReadme)) {
    $content = @"
# $Name / $BundleTarget

Reusable Electron target bundle.

Patch directories:

- ``electron/*.patch``: primary patch sequence for ``src/electron``
- ``chromium-direct/*.patch``: archived Chromium source patches for review/debugging
- ``chromium/*.patch``: direct Chromium ``src`` patches for explicit direct-only bundles

For ``electronized_chromium_patches=true``, apply registers the archived
Chromium patches in Electron's ``patches/chromium`` stack, then materializes
those Chromium patches into Chromium ``src``.

Use:

````bash
scripts/port-bundle.sh apply $Name --target $BundleTarget --src-root /path/to/src
scripts/port-bundle.sh undo $Name --target $BundleTarget --src-root /path/to/src
````

````powershell
.\scripts\port-bundle.ps1 apply $Name -Target $BundleTarget -SrcRoot C:\path\to\src
.\scripts\port-bundle.ps1 undo $Name -Target $BundleTarget -SrcRoot C:\path\to\src
````
"@
    [System.IO.File]::WriteAllText($targetReadme, $content, [System.Text.UTF8Encoding]::new($false))
  }
}

function Get-SelectedRepos {
  param([string]$ReposArg, [string]$PortDir, [string]$StateName)
  if ($ReposArg -ne 'auto') {
    $result = @()
    foreach ($repo in $ReposArg.Split(',')) {
      $repo = $repo.Trim()
      if ($repo -notin @('chromium', 'electron')) { throw "invalid repo in -Repos: $repo" }
      $result += $repo
    }
    return $result
  }

  $result = @()
  $chromiumDir = Get-RepoPath chromium
  $electronDir = Get-RepoPath electron
  $chromiumState = if (Test-Path -LiteralPath (Join-Path $chromiumDir '.git')) { Get-StateFile $chromiumDir $StateName } else { $null }
  $electronState = if (Test-Path -LiteralPath (Join-Path $electronDir '.git')) { Get-StateFile $electronDir $StateName } else { $null }

  if ((Get-PatchesForRepo $PortDir chromium).Count -gt 0 -or ($chromiumState -and (Test-Path -LiteralPath $chromiumState))) {
    $result += 'chromium'
  }
  if ((Get-PatchesForRepo $PortDir electron).Count -gt 0 -or
      (Test-ChromiumDirectElectronPatchStackPort $PortDir) -or
      ($electronState -and (Test-Path -LiteralPath $electronState))) {
    $result += 'electron'
  }
  if ($result.Count -eq 0) { throw "no patches found in $PortDir" }
  return $result
}

function Add-UniqueRepo {
  param([string[]]$Repos, [string]$Repo)
  if ($Repos -contains $Repo) { return $Repos }
  return @($Repos + $Repo)
}

function Get-DependencyRequiredRepos {
  param([string]$PortDir, [string]$StateName)
  $repos = @()
  foreach ($repo in Get-SelectedRepos 'auto' $PortDir $StateName) {
    $repos = Add-UniqueRepo $repos $repo
  }
  if (Test-ElectronizedChromiumPort $PortDir) {
    $repos = Add-UniqueRepo $repos 'chromium'
  }
  return $repos
}

function Write-DependencyStatus {
  param([string]$Dependency, [string]$BundleTarget, [string]$DependencyPortDir)
  $dependencyStateName = Get-StateName $Dependency $BundleTarget
  foreach ($repo in Get-DependencyRequiredRepos $DependencyPortDir $dependencyStateName) {
    $repoDir = Get-RepoPath $repo
    Assert-GitRepo $repoDir
    $state = Get-StateFile $repoDir $dependencyStateName
    $status = if (Test-Path -LiteralPath $state) { 'applied' } else { 'missing' }
    Write-Host "  $Dependency/$BundleTarget ($repo): $status"
  }
}

function Assert-PortDependenciesApplied {
  param([string]$Name, [string]$BundleTarget, [string]$PortDir)
  $dependencies = @(Get-PortDependencies $PortDir)
  if ($dependencies.Count -eq 0) { return }

  $missing = $false
  foreach ($dependency in $dependencies) {
    if ($dependency -eq $Name) {
      throw "$Name/$BundleTarget cannot depend on itself"
    }

    $dependencyPortDir = Get-PortDir $dependency $BundleTarget
    if (-not (Test-Path -LiteralPath $dependencyPortDir)) {
      [Console]::Error.WriteLine("Missing dependency bundle: $dependency/$BundleTarget ($dependencyPortDir)")
      $missing = $true
      continue
    }

    $dependencyStateName = Get-StateName $dependency $BundleTarget
    foreach ($repo in Get-DependencyRequiredRepos $dependencyPortDir $dependencyStateName) {
      $repoDir = Get-RepoPath $repo
      Assert-GitRepo $repoDir
      $state = Get-StateFile $repoDir $dependencyStateName
      if (-not (Test-Path -LiteralPath $state)) {
        [Console]::Error.WriteLine("Missing dependency apply state: $dependency/$BundleTarget in $repo repo")
        [Console]::Error.WriteLine("  expected state: $state")
        $missing = $true
      }
    }
  }

  if ($missing) {
    throw (@"
Cannot apply $Name/$BundleTarget until its dependencies are applied.
Apply the missing dependency ports first, or rerun with -IgnoreDependencies
only if this workspace was prepared manually and you have verified the order.
"@).Trim()
  }
}

function Get-ChromiumDirectArchivePatches {
  param([string]$PortDir)
  $dir = Join-Path $PortDir 'chromium-direct'
  if (-not (Test-Path -LiteralPath $dir)) { return @() }
  @(Get-ChildItem -LiteralPath $dir -Filter '*.patch' -File | Sort-Object Name | ForEach-Object { $_.FullName })
}

function Register-ChromiumDirectElectronPatchStack {
  param([string]$Name, [string]$PortDir)
  if (-not (Test-ChromiumDirectElectronPatchStackPort $PortDir)) { return }

  $electronDir = Get-RepoPath electron
  $chromiumPatchDir = Join-Path $electronDir 'patches\chromium'
  $patchList = Join-Path $chromiumPatchDir '.patches'
  $patches = @(Get-ChromiumDirectArchivePatches $PortDir)
  if ($patches.Count -eq 0) {
    throw "electron_patch_stack_source=chromium-direct but no chromium-direct patches found in $PortDir"
  }

  Assert-CleanWorktree $electronDir
  New-Item -ItemType Directory -Force -Path $chromiumPatchDir | Out-Null
  if (-not (Test-Path -LiteralPath $patchList)) {
    New-Item -ItemType File -Force -Path $patchList | Out-Null
  }

  $changed = $false
  foreach ($patch in $patches) {
    $filename = Get-PatchFilenameFromFile $patch
    $target = Join-Path $chromiumPatchDir $filename

    if (Test-Path -LiteralPath $target) {
      if (-not (Test-SameFileContent $patch $target)) {
        throw "target Chromium patch already exists with different content: $target"
      }
    } else {
      Copy-Logged $patch $target
      Write-Host "+ normalize $target"
      Trim-TrailingWhitespaceInFile $target
      $changed = $true
    }

    $listed = @(Get-Content -LiteralPath $patchList | Where-Object { $_ -eq $filename }).Count -gt 0
    if (-not $listed) {
      [System.IO.File]::AppendAllText($patchList, "$filename`n", [System.Text.UTF8Encoding]::new($false))
      $changed = $true
    }
  }

  if ($changed) {
    Invoke-Logged git -C $electronDir add patches/chromium
    Ensure-GitIdentity $electronDir
    Invoke-Logged git -C $electronDir commit -m "patches: add $Name chromium patches"
  } else {
    Write-Host "Electron Chromium patch stack already contains $Name patches."
  }
}

function Get-ElectronizedChromiumPatchList {
  param([string]$ElectronDir, [string]$Before, [string]$After)
  $patchList = Join-Path $ElectronDir 'patches\chromium\.patches'
  if (-not (Test-Path -LiteralPath $patchList)) { return @() }

  $changed = @(& git -C $ElectronDir diff --name-only --diff-filter=AM "$Before..$After" -- patches/chromium)
  if ($LASTEXITCODE -ne 0) { throw "git diff failed while finding electronized Chromium patches" }
  $changedNames = @{}
  foreach ($path in $changed) {
    if ($path -like 'patches/chromium/*.patch') {
      $changedNames[$path.Substring('patches/chromium/'.Length)] = $true
    }
  }

  $patches = @()
  foreach ($filename in Get-Content -LiteralPath $patchList) {
    if ($changedNames.ContainsKey($filename)) {
      $patches += (Join-Path (Join-Path $ElectronDir 'patches\chromium') $filename)
    }
  }
  return $patches
}

function Apply-ElectronizedChromiumPatches {
  param([string]$Name, [string]$BundleTarget, [string]$PortDir, [string]$ElectronBefore, [string]$ElectronAfter)
  if (-not (Test-ElectronizedChromiumPort $PortDir)) { return }

  $chromiumDir = Get-RepoPath chromium
  $electronDir = Get-RepoPath electron
  Assert-GitRepo $chromiumDir
  Assert-NoAmInProgress $chromiumDir

  $state = Get-StateFile $chromiumDir (Get-StateName $Name $BundleTarget)
  if (Test-Path -LiteralPath $state) {
    Write-Host "Chromium patch apply state already recorded: $state"
    return
  }

  $patches = if (Test-ChromiumDirectElectronPatchStackPort $PortDir) {
    @(Get-ChromiumDirectArchivePatches $PortDir)
  } else {
    @(Get-ElectronizedChromiumPatchList $electronDir $ElectronBefore $ElectronAfter)
  }
  if ($patches.Count -eq 0) { throw "no electronized Chromium patches found in $electronDir for $Name" }

  $before = Get-CommandOutput git -C $chromiumDir rev-parse HEAD
  Write-Host "Applying $Name Chromium patches from Electron patch stack: $chromiumDir"
  foreach ($patch in $patches) {
    Invoke-GitAm $chromiumDir $patch
  }
  $after = Get-CommandOutput git -C $chromiumDir rev-parse HEAD

  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $state) | Out-Null
  $content = @(
    "port=$Name",
    "target=$BundleTarget",
    'repo=chromium',
    "repo_dir=$chromiumDir",
    'source=electronized_chromium_patches',
    "electron_before=$ElectronBefore",
    "electron_after=$ElectronAfter",
    "before=$before",
    "after=$after",
    "applied_at=$((Get-Date).ToString('o'))",
    "patch_count=$($patches.Count)"
  ) + ($patches | ForEach-Object { "patch=$_" })
  [System.IO.File]::WriteAllLines($state, $content, [System.Text.UTF8Encoding]::new($false))
  Write-Host "Recorded Chromium patch apply state: $state"
}

function Invoke-Export {
  param([string]$Name, [string]$BundleTarget)

  if ($ElectronizedChromiumPatches) {
    if (-not $ElectronHead) { throw "-ElectronizedChromiumPatches requires -ElectronHead" }
    if ($ChromiumHead -and -not $ChromiumDirectOnly) {
      throw "-ElectronizedChromiumPatches is only for Electron-only or Chromium direct-only exports"
    }
  }
  if (-not $ChromiumHead -and -not $ElectronHead) {
    throw "nothing to export: pass -ChromiumHead and/or -ElectronHead"
  }

  $portDir = Get-PortDir $Name $BundleTarget
  $existingNotes = Get-ManifestValue $portDir 'notes'
  $existingDependsOn = Get-ManifestValue $portDir 'depends_on'
  $manifestDependsOn = if ($DependsOnSpecified) {
    Convert-PortList $DependsOn
  } elseif ($existingDependsOn) {
    Convert-PortList $existingDependsOn
  } else {
    ''
  }
  $electronizedManifest = $false
  $electronPatchStackSource = $null
  $exportTmp = Join-Path $portDir ".tmp-export-$PID"

  if ($Clear) {
    foreach ($child in @('chromium', 'chromium-direct', 'electron')) {
      $path = Join-Path $portDir $child
      if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force }
    }
  }
  New-Item -ItemType Directory -Force -Path $portDir | Out-Null
  if (Test-Path -LiteralPath $exportTmp) { Remove-Item -LiteralPath $exportTmp -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $exportTmp | Out-Null

  try {
    $electronBaseResolved = $null
    $electronHeadResolved = $null
    $electronDir = Get-RepoPath electron
    if ($ElectronHead) {
      if (-not $ElectronBase) { throw "-ElectronBase is required with -ElectronHead" }
      Assert-GitRepo $electronDir
      $electronBaseResolved = Get-CommandOutput git -C $electronDir rev-parse --verify $ElectronBase
      $electronHeadResolved = Get-CommandOutput git -C $electronDir rev-parse --verify $ElectronHead
    }

    if ($ChromiumHead) {
      if (-not $ChromiumBase) { throw "-ChromiumBase is required with -ChromiumHead" }
      Assert-GitRepo $SrcRoot
      Invoke-Logged git -C $SrcRoot rev-parse --verify $ChromiumBase
      Invoke-Logged git -C $SrcRoot rev-parse --verify $ChromiumHead

      $chromiumExportDir = Join-Path $portDir 'chromium-direct'
      if ($ChromiumDirectOnly) { $chromiumExportDir = Join-Path $portDir 'chromium' }
      New-Item -ItemType Directory -Force -Path $chromiumExportDir | Out-Null
      Invoke-Logged git -C $SrcRoot format-patch --keep-subject --no-signature -o $chromiumExportDir "$ChromiumBase..$ChromiumHead"
      Normalize-PatchFiles $chromiumExportDir

      if (-not $ChromiumDirectOnly) {
        $electronizedManifest = $true
        $electronPatchStackSource = 'chromium-direct'
      }
    }

    if ($ElectronHead) {
      $electronPatchDir = Join-Path $exportTmp 'electron'
      $formatPatchArgs = @(
        'git', '-C', $electronDir,
        'format-patch', '--keep-subject', '--no-signature',
        '-o', $electronPatchDir,
        "$electronBaseResolved..$electronHeadResolved"
      )
      if ($electronPatchStackSource -eq 'chromium-direct') {
        $formatPatchArgs += @('--', '.', ':(exclude)patches/chromium')
      }
      Invoke-Logged @formatPatchArgs
      Normalize-PatchFiles $electronPatchDir
      Copy-DirectoryPatchesToElectronBundle $electronPatchDir $portDir
    }

    if ($ElectronizedChromiumPatches) {
      $electronizedManifest = $true
    }

    $manifestLines = @("electronized_chromium_patches=$($electronizedManifest.ToString().ToLowerInvariant())")
    if ($manifestDependsOn) {
      $manifestLines += "depends_on=$manifestDependsOn"
    }
    if ($electronPatchStackSource) {
      $manifestLines += "electron_patch_stack_source=$electronPatchStackSource"
    }
    if ((Get-PatchesForRepo $portDir electron).Count -gt 0) {
      $manifestLines += 'electron_patch_files=electron/*.patch'
    }
    if ((Get-PatchesForRepo $portDir chromium).Count -gt 0) {
      $manifestLines += 'chromium_patch_files=chromium/*.patch'
    }
    $chromiumDirectDir = Join-Path $portDir 'chromium-direct'
    if ((Test-Path -LiteralPath $chromiumDirectDir) -and
        ((Get-ChildItem -LiteralPath $chromiumDirectDir -Filter '*.patch' -File).Count -gt 0)) {
      $manifestLines += 'chromium_direct_archive=chromium-direct'
    }
    if ($existingNotes) {
      $manifestLines += "notes=$existingNotes"
    }

    Write-Manifest $portDir $Name $BundleTarget $manifestLines
    Write-DefaultReadmes $Name $BundleTarget $portDir
  } finally {
    if (Test-Path -LiteralPath $exportTmp) { Remove-Item -LiteralPath $exportTmp -Recurse -Force }
  }

  Write-Host ''
  Write-Host "Saved port bundle: $portDir"
}

function Invoke-Apply {
  param([string]$Name, [string]$BundleTarget)
  $portDir = Get-PortDir $Name $BundleTarget
  if (-not (Test-Path -LiteralPath $portDir)) { throw "port not found: $portDir" }
  $stateName = Get-StateName $Name $BundleTarget

  if (-not $IgnoreDependencies) {
    Assert-PortDependenciesApplied $Name $BundleTarget $portDir
  }

  foreach ($repo in Get-SelectedRepos $Repos $portDir $stateName) {
    $repoDir = Get-RepoPath $repo
    Assert-GitRepo $repoDir
    Assert-NoAmInProgress $repoDir
    $state = Get-StateFile $repoDir $stateName

    if (Test-Path -LiteralPath $state) {
      if ($repo -eq 'electron' -and (Test-ElectronizedChromiumPort $portDir)) {
        $recordedBefore = Read-StateValue $state before
        $recordedAfter = Read-StateValue $state after
        $current = Get-CommandOutput git -C $repoDir rev-parse HEAD
        if ($current -ne $recordedAfter) {
          throw "$Name is already recorded as applied in $repoDir, but HEAD differs: $state"
        }
        Apply-ElectronizedChromiumPatches $Name $BundleTarget $portDir $recordedBefore $recordedAfter
        continue
      }
      throw "$Name is already recorded as applied in $repoDir`: $state"
    }

    $patches = @(Get-PatchesForRepo $portDir $repo)
    $registerChromiumDirectPatchStack = $repo -eq 'electron' -and (Test-ChromiumDirectElectronPatchStackPort $portDir)
    if ($patches.Count -eq 0 -and -not $registerChromiumDirectPatchStack) {
      throw "no $repo patches found for $Name"
    }

    $before = Get-CommandOutput git -C $repoDir rev-parse HEAD
    Write-Host "Applying $Name to $repo repo: $repoDir"
    if ($registerChromiumDirectPatchStack) {
      Register-ChromiumDirectElectronPatchStack $Name $portDir
    }
    foreach ($patch in $patches) {
      Invoke-GitAm $repoDir $patch
    }
    $after = Get-CommandOutput git -C $repoDir rev-parse HEAD

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $state) | Out-Null
    $content = @(
      "port=$Name",
      "target=$BundleTarget",
      "repo=$repo",
      "repo_dir=$repoDir",
      "before=$before",
      "after=$after",
      "applied_at=$((Get-Date).ToString('o'))",
      "patch_count=$($patches.Count)"
    ) + ($patches | ForEach-Object { "patch=$_" })
    [System.IO.File]::WriteAllLines($state, $content, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Recorded apply state: $state"

    if ($repo -eq 'electron') {
      Apply-ElectronizedChromiumPatches $Name $BundleTarget $portDir $before $after
    }
  }
}

function Invoke-Status {
  param([string]$Name, [string]$BundleTarget)
  $portDir = Get-PortDir $Name $BundleTarget
  if (-not (Test-Path -LiteralPath $portDir)) { throw "port not found: $portDir" }
  $stateName = Get-StateName $Name $BundleTarget
  $dependencies = @(Get-PortDependencies $portDir)
  if ($dependencies.Count -gt 0) {
    Write-Host 'dependencies:'
    foreach ($dependency in $dependencies) {
      $dependencyPortDir = Get-PortDir $dependency $BundleTarget
      if (Test-Path -LiteralPath $dependencyPortDir) {
        Write-DependencyStatus $dependency $BundleTarget $dependencyPortDir
      } else {
        Write-Host "  $dependency/$BundleTarget`: missing bundle"
      }
    }
  }
  foreach ($repo in Get-SelectedRepos $Repos $portDir $stateName) {
    $repoDir = Get-RepoPath $repo
    Assert-GitRepo $repoDir
    $state = Get-StateFile $repoDir $stateName
    if (Test-Path -LiteralPath $state) {
      Write-Host "$repo`: applied"
      Get-Content -LiteralPath $state | ForEach-Object { Write-Host "  $_" }
    } else {
      Write-Host "$repo`: not applied"
    }
  }
}

function Invoke-Undo {
  param([string]$Name, [string]$BundleTarget)
  $portDir = Get-PortDir $Name $BundleTarget
  if (-not (Test-Path -LiteralPath $portDir)) { throw "port not found: $portDir" }
  $stateName = Get-StateName $Name $BundleTarget
  foreach ($repo in Get-SelectedRepos $Repos $portDir $stateName) {
    $repoDir = Get-RepoPath $repo
    Assert-GitRepo $repoDir
    Assert-NoAmInProgress $repoDir
    $state = Get-StateFile $repoDir $stateName
    if (-not (Test-Path -LiteralPath $state)) { throw "$Name is not recorded as applied in $repoDir" }

    $before = Read-StateValue $state before
    $after = Read-StateValue $state after
    if (-not $before -or -not $after) { throw "invalid state file: $state" }
    Invoke-Logged git -C $repoDir rev-parse --verify $before
    Invoke-Logged git -C $repoDir rev-parse --verify $after
    if (-not (Test-ExternalOk git -C $repoDir merge-base --is-ancestor $after HEAD)) {
      throw "recorded applied head $after is not an ancestor of current HEAD in $repoDir"
    }

    $commits = @(& git -C $repoDir rev-list "$before..$after")
    if ($LASTEXITCODE -ne 0) { throw "git rev-list failed in $repoDir" }
    if ($commits.Count -eq 0) { throw "no commits to revert for $Name in $repoDir" }

    Write-Host "Reverting $Name from $repo repo: $repoDir"
    Ensure-GitIdentity $repoDir
    foreach ($commit in $commits) {
      Invoke-Logged git -C $repoDir revert --no-edit $commit
    }

    $archive = "$state.undone-$((Get-Date).ToString('yyyyMMdd-HHmmss'))"
    Move-Item -LiteralPath $state -Destination $archive
    Write-Host "Archived apply state: $archive"
  }
}

function Invoke-Drop {
  param([string]$Name, [string]$BundleTarget)
  $portDir = Get-PortDir $Name $BundleTarget
  if (-not (Test-Path -LiteralPath $portDir)) { throw "port not found: $portDir" }
  $stateName = Get-StateName $Name $BundleTarget
  $selectedRepos = @(Get-SelectedRepos $Repos $portDir $stateName)
  if ($BackupBranchName -and $selectedRepos.Count -ne 1) {
    throw "-BackupBranchName requires dropping exactly one repo; use -Repos electron or -Repos chromium"
  }

  foreach ($repo in $selectedRepos) {
    $repoDir = Get-RepoPath $repo
    Assert-GitRepo $repoDir
    Assert-NoAmInProgress $repoDir
    $state = Get-StateFile $repoDir $stateName
    if (-not (Test-Path -LiteralPath $state)) { throw "$Name is not recorded as applied in $repoDir" }

    $before = Read-StateValue $state before
    $after = Read-StateValue $state after
    $current = Get-CommandOutput git -C $repoDir rev-parse HEAD
    if (-not $before -or -not $after) { throw "invalid state file: $state" }
    Invoke-Logged git -C $repoDir rev-parse --verify $before
    Invoke-Logged git -C $repoDir rev-parse --verify $after
    if ($current -ne $after) {
      throw @"
refusing to drop $Name in $repoDir

The recorded applied head is:
  $after

Current HEAD is:
  $current

This usually means extra commits were added after the port was applied.
Use undo if you want revert commits, or manually inspect before resetting.
"@
    }

    if ($BackupBranch -or $BackupBranchName) {
      $branchName = if ($BackupBranchName) { $BackupBranchName } else { "backup/drop-$Name-$BundleTarget-$repo-$(Get-TimestampForBranch)" }
      if (Test-ExternalOk git -C $repoDir show-ref --verify --quiet "refs/heads/$branchName") {
        throw "backup branch already exists in $repoDir`: $branchName"
      }
      Write-Host "Creating backup branch for $Name in $repo repo: $repoDir"
      Invoke-Logged git -C $repoDir branch $branchName $current
    }

    Write-Host "Dropping $Name from $repo repo without revert commits: $repoDir"
    Invoke-Logged git -C $repoDir reset --keep $before
    $archive = "$state.dropped-$((Get-Date).ToString('yyyyMMdd-HHmmss'))"
    Move-Item -LiteralPath $state -Destination $archive
    Write-Host "Archived apply state: $archive"
  }
}

switch ($Command) {
  'list' {
    $portsDir = Join-Path $BaseDir 'ports'
    if (-not (Test-Path -LiteralPath $portsDir)) {
      Write-Host "No ports directory: $portsDir"
      return
    }
    Get-ChildItem -LiteralPath $portsDir -Directory | ForEach-Object {
      $feature = $_.Name
      Get-ChildItem -LiteralPath $_.FullName -Directory | ForEach-Object { "$feature/$($_.Name)" }
    } | Sort-Object | Write-Output
  }
  default {
    $name = Assert-Name $PortName 'port name'
    $bundleTarget = Assert-Name $Target 'target'
    switch ($Command) {
      'export' { Invoke-Export $name $bundleTarget }
      'apply' { Invoke-Apply $name $bundleTarget }
      'status' { Invoke-Status $name $bundleTarget }
      'undo' { Invoke-Undo $name $bundleTarget }
      'drop' { Invoke-Drop $name $bundleTarget }
    }
  }
}
