param(
  [string]$Target = $env:ELECTRON_WORKSPACE_TARGET,
  [string]$SrcDir = $env:ELECTRON_WORKSPACE_SRC_DIR,
  [string]$OutputDir,
  [switch]$DownloadIfMissing,
  [switch]$PreferDownload,
  [switch]$LicenseAck,
  [switch]$RequireChromeMajorMatch,
  [switch]$Force,
  [switch]$PrintEnvironment
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Target) { $Target = '41' }
if (-not $SrcDir) {
  $SrcDir = Join-Path (Resolve-Path (Join-Path $ScriptDir '..')).Path "$Target\src"
}
$SrcDir = [System.IO.Path]::GetFullPath($SrcDir)
if (-not $OutputDir) {
  $OutputDir = Join-Path $SrcDir 'out\widevine-cdm\WidevineCdm'
}
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)

$CdmComponentId = 'oimompecagnajdejgnnjijobebaeigek'
$Update2JsonUrl = 'https://update.googleapis.com/service/update2/json'
$ChromeForTestingKnownGoodUrl = 'https://googlechromelabs.github.io/chrome-for-testing/known-good-versions-with-downloads.json'

$CdmOs = 'win'
$CdmArch = switch ($env:PROCESSOR_ARCHITECTURE) {
  'AMD64' { 'x64' }
  'ARM64' { 'arm64' }
  'x86' { 'x86' }
  default { if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' } }
}
$CdmPlatform = "win_$CdmArch"
$CdmLibraryName = 'widevinecdm.dll'

function Test-Truthy {
  param([object]$Value)
  if ($Value -eq $true) { return $true }
  if (-not $Value) { return $false }
  return [regex]::IsMatch([string]$Value, '^(1|true|yes|on)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

function Convert-ToVersion {
  param([string]$Value)
  try {
    return [version]$Value
  } catch {
    throw "Invalid version string: $Value"
  }
}

function Get-VersionScore {
  param([string]$Value)
  $version = Convert-ToVersion $Value
  return ($version.Major * 1000000000) + ($version.Minor * 1000000) + ($version.Build * 1000) + [Math]::Max($version.Revision, 0)
}

function Get-ChromiumVersion {
  param([string]$SourceDir)
  $versionFile = Join-Path $SourceDir 'chrome\VERSION'
  if (Test-Path -LiteralPath $versionFile) {
    $parts = @{}
    Get-Content -LiteralPath $versionFile | ForEach-Object {
      if ($_ -match '^([^=]+)=(.+)$') {
        $parts[$matches[1]] = $matches[2]
      }
    }
    if ($parts.ContainsKey('MAJOR') -and $parts.ContainsKey('MINOR') -and $parts.ContainsKey('BUILD') -and $parts.ContainsKey('PATCH')) {
      return "$($parts.MAJOR).$($parts.MINOR).$($parts.BUILD).$($parts.PATCH)"
    }
  }

  $depsFile = Join-Path $SourceDir 'electron\DEPS'
  if (Test-Path -LiteralPath $depsFile) {
    $deps = Get-Content -Raw -LiteralPath $depsFile
    if ($deps -match "'chromium_version'\s*:\s*'([^']+)'") {
      return $matches[1]
    }
  }

  throw "Could not determine Chromium version from $SourceDir"
}

function Get-SupportedHostVersionRange {
  param([string]$SourceDir)
  $file = Join-Path $SourceDir 'media\cdm\supported_cdm_versions.h'
  if (-not (Test-Path -LiteralPath $file)) {
    return @{ Min = 10; Max = 12 }
  }
  $text = Get-Content -Raw -LiteralPath $file
  $minMatch = [regex]::Match($text, 'kMinSupportedCdmHostVersion\s*=\s*(\d+)')
  $maxMatch = [regex]::Match($text, 'kMaxSupportedCdmHostVersion\s*=\s*(\d+)')
  if (-not $minMatch.Success -or -not $maxMatch.Success) {
    return @{ Min = 10; Max = 12 }
  }
  return @{ Min = [int]$minMatch.Groups[1].Value; Max = [int]$maxMatch.Groups[1].Value }
}

function Split-CdmVersionList {
  param([object]$Value)
  if (-not $Value) { return @() }
  return ([string]$Value).Split(',') |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -match '^\d+$' } |
    ForEach-Object { [int]$_ }
}

function Get-BrowserVersionFromPath {
  param([string]$PathValue)
  $parts = $PathValue -split '[\\/]'
  for ($i = $parts.Count - 1; $i -ge 0; $i--) {
    if ($parts[$i] -match '^\d+\.\d+\.\d+\.\d+$') {
      return $parts[$i]
    }
  }
  return $null
}

function Find-WidevineRootFromLibrary {
  param([string]$LibraryPath)
  $directory = Split-Path -Parent $LibraryPath
  for ($i = 0; $i -lt 5 -and $directory; $i++) {
    if (Test-Path -LiteralPath (Join-Path $directory 'manifest.json')) {
      return [System.IO.Path]::GetFullPath($directory)
    }
    $parent = Split-Path -Parent $directory
    if ($parent -eq $directory) { break }
    $directory = $parent
  }
  return $null
}

function Add-CandidatePath {
  param(
    [System.Collections.Generic.HashSet[string]]$Paths,
    [string]$PathValue
  )
  if (-not $PathValue) { return }
  try {
    $fullPath = [System.IO.Path]::GetFullPath($PathValue)
  } catch {
    return
  }
  if (Test-Path -LiteralPath (Join-Path $fullPath 'manifest.json')) {
    [void]$Paths.Add($fullPath)
  }
  $nested = Join-Path $fullPath 'WidevineCdm'
  if (Test-Path -LiteralPath (Join-Path $nested 'manifest.json')) {
    [void]$Paths.Add([System.IO.Path]::GetFullPath($nested))
  }
}

function Find-LocalWidevineCandidates {
  param(
    [string]$SourceDir,
    [string]$WorkspaceRoot
  )

  $paths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  Add-CandidatePath $paths $env:ELECTRON_PACKAGE_WIDEVINE_CDM_DIR
  Add-CandidatePath $paths (Join-Path $SourceDir 'out\widevine-cdm\WidevineCdm')
  Add-CandidatePath $paths (Join-Path $SourceDir 'out\Release\WidevineCdm')
  Add-CandidatePath $paths (Join-Path $WorkspaceRoot 'WidevineCdm')

  $chromeApplicationRoots = @(
    (Join-Path $env:ProgramFiles 'Google\Chrome\Application'),
    (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application'),
    (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application'),
    (Join-Path $env:LOCALAPPDATA 'Google\Chrome SxS\Application')
  ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

  foreach ($root in $chromeApplicationRoots) {
    Add-CandidatePath $paths $root
    Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
      ForEach-Object {
        Add-CandidatePath $paths (Join-Path $_.FullName 'WidevineCdm')
      }
  }

  $chromeUserDataRoots = @(
    (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\WidevineCdm'),
    (Join-Path $env:LOCALAPPDATA 'Google\Chrome SxS\User Data\WidevineCdm')
  ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

  foreach ($root in $chromeUserDataRoots) {
    Add-CandidatePath $paths $root
    Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
      ForEach-Object { Add-CandidatePath $paths $_.FullName }
  }

  $manualRoots = @(
    (Join-Path $env:USERPROFILE 'Desktop'),
    (Join-Path $env:USERPROFILE 'Downloads')
  ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

  foreach ($root in $manualRoots) {
    Add-CandidatePath $paths (Join-Path $root 'WidevineCdm')
    Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -eq 'WidevineCdm' -or $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
      ForEach-Object { Add-CandidatePath $paths $_.FullName }
  }

  return @($paths)
}

function Test-WidevineCandidate {
  param(
    [string]$PathValue,
    [version]$ChromiumVersion,
    [int]$HostMin,
    [int]$HostMax,
    [switch]$AllowUnknownSourceVersion
  )

  $manifestPath = Join-Path $PathValue 'manifest.json'
  $licensePath = Join-Path $PathValue 'LICENSE'
  $libraryPath = Join-Path $PathValue "_platform_specific\$script:CdmPlatform\$script:CdmLibraryName"
  if (-not (Test-Path -LiteralPath $manifestPath)) { return $null }
  if (-not (Test-Path -LiteralPath $licensePath)) { return $null }
  if (-not (Test-Path -LiteralPath $libraryPath)) { return $null }

  try {
    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
  } catch {
    Write-Warning "Skipping malformed Widevine manifest: $manifestPath"
    return $null
  }

  $platformOk = $false
  foreach ($platform in @($manifest.platforms)) {
    if ($platform.os -eq $script:CdmOs -and $platform.arch -eq $script:CdmArch) {
      $platformOk = $true
    }
  }
  if (-not $platformOk) { return $null }

  $minimumChromeVersion = Convert-ToVersion ([string]$manifest.minimum_chrome_version)
  if ($minimumChromeVersion -gt $ChromiumVersion) { return $null }

  $hostVersions = Split-CdmVersionList $manifest.'x-cdm-host-versions'
  if (-not ($hostVersions | Where-Object { $_ -ge $HostMin -and $_ -le $HostMax })) {
    return $null
  }

  $browserVersion = Get-BrowserVersionFromPath $PathValue
  if ($RequireChromeMajorMatch) {
    if ($browserVersion) {
      if ((Convert-ToVersion $browserVersion).Major -ne $ChromiumVersion.Major) {
        return $null
      }
    } elseif (-not $AllowUnknownSourceVersion) {
      return $null
    }
  }

  $score = 100
  if ($browserVersion) {
    $browser = Convert-ToVersion $browserVersion
    if ($browser -eq $ChromiumVersion) {
      $score += 500
    } elseif ($browser.Major -eq $ChromiumVersion.Major) {
      $score += 400
    } else {
      $score += [Math]::Max(0, 200 - [Math]::Abs($browser.Major - $ChromiumVersion.Major))
    }
  }

  return [pscustomobject]@{
    Path = [System.IO.Path]::GetFullPath($PathValue)
    ManifestPath = $manifestPath
    LibraryPath = $libraryPath
    LicensePath = $licensePath
    SigPath = "$libraryPath.sig"
    CdmVersion = [string]$manifest.version
    CdmVersionScore = Get-VersionScore ([string]$manifest.version)
    MinimumChromeVersion = [string]$manifest.minimum_chrome_version
    HostVersions = ($hostVersions -join ',')
    BrowserVersion = $browserVersion
    Score = $score
    LastWriteTime = (Get-Item -LiteralPath $libraryPath).LastWriteTime
  }
}

function Select-BestWidevineCandidate {
  param(
    [string[]]$Paths,
    [version]$ChromiumVersion,
    [int]$HostMin,
    [int]$HostMax,
    [switch]$AllowUnknownSourceVersion
  )

  $valid = foreach ($path in $Paths) {
    Test-WidevineCandidate -PathValue $path -ChromiumVersion $ChromiumVersion -HostMin $HostMin -HostMax $HostMax -AllowUnknownSourceVersion:$AllowUnknownSourceVersion
  }
  return $valid | Sort-Object Score, CdmVersionScore, LastWriteTime -Descending | Select-Object -First 1
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

function Get-Sha256Hex {
  param([string]$Text)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text))
  } finally {
    $sha.Dispose()
  }
  return -join ($hash | ForEach-Object { $_.ToString('x2') })
}

function Get-FileSha256Hex {
  param([string]$PathValue)
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $PathValue).Hash.ToLowerInvariant()
}

function New-Base64UrlNonce {
  $bytes = New-Object byte[] 32
  $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  try {
    $rng.GetBytes($bytes)
  } finally {
    $rng.Dispose()
  }
  return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Get-CupSignedUpdate2Uri {
  param([string]$RequestBody)
  $nonce = New-Base64UrlNonce
  $requestHash = Get-Sha256Hex $RequestBody
  return ('{0}?cup2key=16:{1}&cup2hreq={2}' -f $script:Update2JsonUrl, $nonce, $requestHash)
}

function Get-PhysicalMemoryGb {
  try {
    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    return [Math]::Max(1, [int]([int64]$computerSystem.TotalPhysicalMemory / 1GB))
  } catch {
    return 8
  }
}

function Select-PreferredDownloadUrl {
  param([object[]]$UrlItems)
  $urls = foreach ($item in @($UrlItems)) {
    if (-not $item) { continue }
    if ($item -is [string]) {
      $item
    } elseif ($item.url) {
      [string]$item.url
    }
  }
  $httpsUrl = $urls | Where-Object { $_ -like 'https://*' } | Select-Object -First 1
  if ($httpsUrl) { return $httpsUrl }
  return $urls | Select-Object -First 1
}

function Get-WidevineUpdateDownload {
  param([object]$UpdateCheck)

  $pipelineDownloads = foreach ($pipeline in @($UpdateCheck.pipelines)) {
    foreach ($operation in @($pipeline.operations)) {
      if ($operation.type -ne 'download') { continue }
      $url = Select-PreferredDownloadUrl @($operation.urls)
      if (-not $url) { continue }
      [pscustomobject]@{
        Url = $url
        Sha256 = if ($operation.out -and $operation.out.sha256) { [string]$operation.out.sha256 } else { $null }
      }
    }
  }
  $download = @($pipelineDownloads) | Select-Object -First 1
  if ($download) { return $download }

  $baseUrl = @($UpdateCheck.urls.url)[0].url
  $package = @($UpdateCheck.manifest.packages.package)[0]
  if ($baseUrl -and $package.name) {
    return [pscustomobject]@{
      Url = "$baseUrl$($package.name)"
      Sha256 = if ($package.hash_sha256) { [string]$package.hash_sha256 } else { $null }
    }
  }

  return $null
}

function Expand-CrxToDirectory {
  param(
    [string]$CrxPath,
    [string]$DestinationDir
  )
  $zipPath = Join-Path (Split-Path -Parent $CrxPath) 'component.zip'
  $stream = [System.IO.File]::OpenRead($CrxPath)
  try {
    $reader = [System.IO.BinaryReader]::new($stream, [System.Text.Encoding]::ASCII, $true)
    $magic = [System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(4))
    if ($magic -eq 'Cr24') {
      $version = $reader.ReadUInt32()
      if ($version -ne 2 -and $version -ne 3) {
        throw "Unsupported CRX version: $version"
      }
      if ($version -eq 3) {
        $headerSize = $reader.ReadUInt32()
        $zipOffset = 12 + [int64]$headerSize
      } else {
        $publicKeySize = $reader.ReadUInt32()
        $signatureSize = $reader.ReadUInt32()
        $zipOffset = 16 + [int64]$publicKeySize + [int64]$signatureSize
      }
      [void]$stream.Seek($zipOffset, [System.IO.SeekOrigin]::Begin)
    } else {
      [void]$stream.Seek(0, [System.IO.SeekOrigin]::Begin)
    }
    $output = [System.IO.File]::Create($zipPath)
    try {
      $stream.CopyTo($output)
    } finally {
      $output.Dispose()
    }
  } finally {
    $stream.Dispose()
  }
  New-Item -ItemType Directory -Force -Path $DestinationDir | Out-Null
  Invoke-NativeCommand -FilePath 'tar' -Arguments @('-xf', $zipPath, '-C', $DestinationDir) -Name 'tar extract crx payload'
}

function Download-WidevineFromUpdate2 {
  param(
    [string]$ChromiumVersion,
    [string]$TempDir
  )

  $request = @{
    request = @{
      protocol = '4.0'
      dedup = 'cr'
      acceptformat = 'crx3,download,puff,run,xz,zucc'
      ismachine = $true
      sessionid = '{' + [guid]::NewGuid().ToString().ToUpperInvariant() + '}'
      requestid = '{' + [guid]::NewGuid().ToString().ToUpperInvariant() + '}'
      '@os' = 'win'
      arch = $script:CdmArch
      nacl_arch = if ($script:CdmArch -eq 'x64') { 'x86-64' } else { $script:CdmArch }
      prodversion = $ChromiumVersion
      updaterversion = $ChromiumVersion
      '@updater' = 'chrome'
      prodchannel = 'stable'
      updaterchannel = 'stable'
      os = @{ platform = 'win'; version = [System.Environment]::OSVersion.Version.ToString(); arch = $script:CdmArch }
      hw = @{ physmemory = Get-PhysicalMemoryGb }
      apps = @(@{
        appid = $script:CdmComponentId
        version = '0.0.0.0'
        lang = 'en-US'
        enabled = $true
        installsource = 'ondemand'
        updatecheck = @{}
      })
    }
  } | ConvertTo-Json -Depth 20 -Compress

  $headers = @{
    'X-Goog-Update-Updater' = "chrome-$ChromiumVersion"
    'X-Goog-Update-Interactivity' = 'fg'
    'X-Goog-Update-AppId' = $script:CdmComponentId
  }
  $updateUri = Get-CupSignedUpdate2Uri -RequestBody $request
  $response = Invoke-WebRequest -Method Post -Uri $updateUri -Headers $headers -Body $request -ContentType 'application/json' -TimeoutSec 90 -UseBasicParsing
  $content = $response.Content -replace "^\)\]\}'\s*", ''
  $json = $content | ConvertFrom-Json
  $app = @($json.response.apps)[0]
  if (-not $app -or $app.status -ne 'ok' -or $app.updatecheck.status -ne 'ok') {
    $status = if ($app -and $app.updatecheck) { $app.updatecheck.status } else { 'missing response' }
    throw "Google update2 did not provide a Widevine update: $status"
  }

  $download = Get-WidevineUpdateDownload -UpdateCheck $app.updatecheck
  if (-not $download -or -not $download.Url) {
    throw 'Google update2 response did not include a downloadable package URL.'
  }

  $crxPath = Join-Path $TempDir 'widevine.crx3'
  Invoke-WebRequest -Uri $download.Url -OutFile $crxPath -UseBasicParsing -TimeoutSec 300
  if ($download.Sha256) {
    $actualHash = Get-FileSha256Hex -PathValue $crxPath
    if ($actualHash -ne $download.Sha256.ToLowerInvariant()) {
      throw "Downloaded Widevine CRX hash mismatch. Expected $($download.Sha256), got $actualHash."
    }
  }

  $extractDir = Join-Path $TempDir 'update2'
  Expand-CrxToDirectory -CrxPath $crxPath -DestinationDir $extractDir
  return $extractDir
}

function Download-WidevineFromChromeForTesting {
  param(
    [string]$ChromiumVersion,
    [string]$TempDir
  )

  $known = Invoke-RestMethod -Uri $script:ChromeForTestingKnownGoodUrl -TimeoutSec 90
  $entry = $known.versions | Where-Object { $_.version -eq $ChromiumVersion } | Select-Object -First 1
  if (-not $entry) {
    throw "Chrome for Testing has no exact win64 archive for Chromium $ChromiumVersion."
  }

  $platform = if ($script:CdmArch -eq 'x64') { 'win64' } elseif ($script:CdmArch -eq 'x86') { 'win32' } else { "win-$($script:CdmArch)" }
  $download = $entry.downloads.chrome | Where-Object { $_.platform -eq $platform } | Select-Object -First 1
  if (-not $download) {
    throw "Chrome for Testing has no $platform Chrome archive for Chromium $ChromiumVersion."
  }

  $zipPath = Join-Path $TempDir 'chrome-for-testing.zip'
  Invoke-WebRequest -Uri $download.url -OutFile $zipPath -UseBasicParsing -TimeoutSec 900
  $extractDir = Join-Path $TempDir 'chrome-for-testing'
  New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
  Invoke-NativeCommand -FilePath 'tar' -Arguments @('-xf', $zipPath, '-C', $extractDir) -Name 'tar extract Chrome for Testing'
  return $extractDir
}

function Select-DownloadedWidevineCandidate {
  param(
    [string]$ChromiumVersionText,
    [version]$ChromiumVersion,
    [int]$HostMin,
    [int]$HostMax
  )

  $tempDir = Join-Path $SrcDir 'out\widevine-cdm-download'
  if (Test-Path -LiteralPath $tempDir) {
    Remove-Item -LiteralPath $tempDir -Recurse -Force
  }
  New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

  $downloadRoots = @()
  try {
    Write-Host 'Trying Google update2 for target Chromium Widevine CDM...'
    $downloadRoots += Download-WidevineFromUpdate2 -ChromiumVersion $ChromiumVersionText -TempDir $tempDir
  } catch {
    Write-Warning $_.Exception.Message
  }

  if ($downloadRoots.Count -eq 0) {
    try {
      Write-Host 'Trying Chrome for Testing exact-version archive...'
      $downloadRoots += Download-WidevineFromChromeForTesting -ChromiumVersion $ChromiumVersionText -TempDir $tempDir
    } catch {
      Write-Warning $_.Exception.Message
    }
  }

  $downloadCandidatePaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($root in $downloadRoots) {
    Add-CandidatePath $downloadCandidatePaths $root
    Get-ChildItem -LiteralPath $root -Recurse -Filter $CdmLibraryName -File -ErrorAction SilentlyContinue |
      ForEach-Object {
        $widevineRoot = Find-WidevineRootFromLibrary $_.FullName
        if ($widevineRoot) {
          [void]$downloadCandidatePaths.Add($widevineRoot)
        }
      }
  }

  return Select-BestWidevineCandidate -Paths @($downloadCandidatePaths) -ChromiumVersion $ChromiumVersion -HostMin $HostMin -HostMax $HostMax -AllowUnknownSourceVersion
}

function Copy-WidevineCdm {
  param(
    [string]$SourceDir,
    [string]$DestinationDir
  )

  if (Test-Path -LiteralPath $DestinationDir) {
    if (-not $Force) {
      throw "Output directory already exists: $DestinationDir. Pass -Force to replace it."
    }
    Remove-Item -LiteralPath $DestinationDir -Recurse -Force
  }

  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $DestinationDir) | Out-Null
  Copy-Item -LiteralPath $SourceDir -Destination $DestinationDir -Recurse -Force
}

$licenseAccepted = $LicenseAck -or (Test-Truthy $env:ELECTRON_PACKAGE_WIDEVINE_LICENSE_ACK)
if (-not $licenseAccepted) {
  throw 'Refusing to resolve/copy/download Widevine CDM without -LicenseAck or ELECTRON_PACKAGE_WIDEVINE_LICENSE_ACK=1.'
}

$chromiumVersionText = Get-ChromiumVersion $SrcDir
$chromiumVersion = Convert-ToVersion $chromiumVersionText
$hostRange = Get-SupportedHostVersionRange $SrcDir
$workspaceRoot = [System.IO.Path]::GetFullPath((Join-Path $ScriptDir '..'))

Write-Host "Electron target: $Target"
Write-Host "Source dir: $SrcDir"
Write-Host "Chromium version: $chromiumVersionText"
Write-Host "Required CDM platform: $CdmPlatform"
Write-Host "Supported CDM host versions: $($hostRange.Min)..$($hostRange.Max)"

$selected = $null

if ($DownloadIfMissing -and $PreferDownload) {
  $selected = Select-DownloadedWidevineCandidate -ChromiumVersionText $chromiumVersionText -ChromiumVersion $chromiumVersion -HostMin $hostRange.Min -HostMax $hostRange.Max
}

if (-not $selected) {
  $candidatePaths = Find-LocalWidevineCandidates -SourceDir $SrcDir -WorkspaceRoot $workspaceRoot
  $selected = Select-BestWidevineCandidate -Paths $candidatePaths -ChromiumVersion $chromiumVersion -HostMin $hostRange.Min -HostMax $hostRange.Max
}

if (-not $selected -and $DownloadIfMissing -and -not $PreferDownload) {
  Write-Host 'No compatible local Widevine CDM found.'
  $selected = Select-DownloadedWidevineCandidate -ChromiumVersionText $chromiumVersionText -ChromiumVersion $chromiumVersion -HostMin $hostRange.Min -HostMax $hostRange.Max
}

if (-not $selected) {
  throw "No compatible Widevine CDM found for Chromium $chromiumVersionText and platform $CdmPlatform."
}

Write-Host "Selected Widevine CDM: $($selected.Path)"
Write-Host "Widevine version: $($selected.CdmVersion)"
if ($selected.BrowserVersion) {
  Write-Host "Source Chrome version: $($selected.BrowserVersion)"
  if ((Convert-ToVersion $selected.BrowserVersion).Major -ne $chromiumVersion.Major) {
    Write-Warning "Selected CDM comes from Chrome major $((Convert-ToVersion $selected.BrowserVersion).Major), while Electron Chromium major is $($chromiumVersion.Major). Manifest and host checks passed, but runtime playback should still be tested."
  }
}

Copy-WidevineCdm -SourceDir $selected.Path -DestinationDir $OutputDir
Write-Host "Prepared Widevine CDM directory: $OutputDir"

if ($PrintEnvironment) {
  Write-Host "`$env:ELECTRON_PACKAGE_INCLUDE_WIDEVINE_CDM='1'"
  Write-Host "`$env:ELECTRON_PACKAGE_WIDEVINE_LICENSE_ACK='1'"
  Write-Host "`$env:ELECTRON_PACKAGE_WIDEVINE_CDM_DIR='$OutputDir'"
}

Write-Output $OutputDir
