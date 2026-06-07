#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  resolve-widevine-cdm.sh [options]

Options:
  --target <target>                 Electron workspace target. Default: ELECTRON_WORKSPACE_TARGET or 41.
  --src-dir <path>                  Chromium src root. Default: <workspace-root>/<target>/src.
  --output-dir <path>               Destination WidevineCdm directory.
                                    Default: <src-dir>/out/widevine-cdm/WidevineCdm.
  --download-if-missing             Download a compatible CDM if no local candidate is found.
  --prefer-download                 With --download-if-missing, try target Chromium downloads before
                                    local candidates.
  --license-ack                     Acknowledge that CDM use/redistribution is separately licensed.
  --require-chrome-major-match      Reject local candidates from a different Chrome major version
                                    when the source path contains a Chrome version.
  --force                           Replace an existing output directory.
  --print-environment               Print packaging environment exports to stderr.
  -h, --help                        Show this help.

The script first searches local CDM directories, unless --prefer-download is set.
It downloads only when --download-if-missing is set. It prints the prepared
WidevineCdm path on stdout.
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TARGET="${ELECTRON_WORKSPACE_TARGET:-41}"
SRC_DIR="${ELECTRON_WORKSPACE_SRC_DIR:-}"
OUTPUT_DIR=""
DOWNLOAD_IF_MISSING=0
PREFER_DOWNLOAD=0
LICENSE_ACK=0
REQUIRE_CHROME_MAJOR_MATCH=0
FORCE=0
PRINT_ENVIRONMENT=0

CDM_COMPONENT_ID="oimompecagnajdejgnnjijobebaeigek"
UPDATE2_JSON_URL="https://update.googleapis.com/service/update2/json"
CHROME_FOR_TESTING_KNOWN_GOOD_URL="https://googlechromelabs.github.io/chrome-for-testing/known-good-versions-with-downloads.json"

log() {
  echo "$*" >&2
}

warn() {
  echo "warning: $*" >&2
}

die() {
  echo "error: $*" >&2
  exit 1
}

truthy() {
  case "${1:-}" in
    1|true|TRUE|True|yes|YES|Yes|on|ON|On) return 0 ;;
    *) return 1 ;;
  esac
}

real_path() {
  realpath -m "$1"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET=$2
      shift 2
      ;;
    --target=*)
      TARGET=${1#--target=}
      shift
      ;;
    --src-dir)
      SRC_DIR=$2
      shift 2
      ;;
    --src-dir=*)
      SRC_DIR=${1#--src-dir=}
      shift
      ;;
    --output-dir)
      OUTPUT_DIR=$2
      shift 2
      ;;
    --output-dir=*)
      OUTPUT_DIR=${1#--output-dir=}
      shift
      ;;
    --download-if-missing)
      DOWNLOAD_IF_MISSING=1
      shift
      ;;
    --prefer-download)
      PREFER_DOWNLOAD=1
      shift
      ;;
    --license-ack)
      LICENSE_ACK=1
      shift
      ;;
    --require-chrome-major-match)
      REQUIRE_CHROME_MAJOR_MATCH=1
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --print-environment)
      PRINT_ENVIRONMENT=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

if [[ -z "$SRC_DIR" ]]; then
  SRC_DIR="$WORKSPACE_ROOT/$TARGET/src"
fi
SRC_DIR="$(real_path "$SRC_DIR")"
if [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR="$SRC_DIR/out/widevine-cdm/WidevineCdm"
fi
OUTPUT_DIR="$(real_path "$OUTPUT_DIR")"

if [[ ! -d "$SRC_DIR" ]]; then
  die "source directory not found: $SRC_DIR"
fi

if [[ "$LICENSE_ACK" -ne 1 ]] && ! truthy "${ELECTRON_PACKAGE_WIDEVINE_LICENSE_ACK:-}"; then
  die "refusing to resolve/copy/download Widevine CDM without --license-ack or ELECTRON_PACKAGE_WIDEVINE_LICENSE_ACK=1"
fi

require_command node
require_command realpath

detect_cdm_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "x64" ;;
    aarch64|arm64) echo "arm64" ;;
    i386|i686) echo "x86" ;;
    *) uname -m ;;
  esac
}

CDM_OS="linux"
CDM_ARCH="$(detect_cdm_arch)"
CDM_PLATFORM="linux_$CDM_ARCH"
CDM_LIBRARY_NAME="libwidevinecdm.so"

get_chromium_version() {
  local source_dir=$1
  local version_file="$source_dir/chrome/VERSION"
  if [[ -f "$version_file" ]]; then
    local major minor build patch
    major=$(awk -F= '$1 == "MAJOR" { print $2 }' "$version_file" | head -n1)
    minor=$(awk -F= '$1 == "MINOR" { print $2 }' "$version_file" | head -n1)
    build=$(awk -F= '$1 == "BUILD" { print $2 }' "$version_file" | head -n1)
    patch=$(awk -F= '$1 == "PATCH" { print $2 }' "$version_file" | head -n1)
    if [[ -n "$major" && -n "$minor" && -n "$build" && -n "$patch" ]]; then
      echo "$major.$minor.$build.$patch"
      return
    fi
  fi

  local deps_file="$source_dir/electron/DEPS"
  if [[ -f "$deps_file" ]]; then
    local version
    version=$(sed -nE "s/.*['\"]chromium_version['\"][[:space:]]*:[[:space:]]*['\"]([^'\"]+)['\"].*/\1/p" "$deps_file" | head -n1)
    if [[ -n "$version" ]]; then
      echo "$version"
      return
    fi
  fi

  die "could not determine Chromium version from $source_dir"
}

get_supported_host_range() {
  local source_dir=$1
  local file="$source_dir/media/cdm/supported_cdm_versions.h"
  if [[ ! -f "$file" ]]; then
    echo "10 12"
    return
  fi

  local min max
  min=$(sed -nE 's/.*kMinSupportedCdmHostVersion[[:space:]]*=[[:space:]]*([0-9]+).*/\1/p' "$file" | head -n1)
  max=$(sed -nE 's/.*kMaxSupportedCdmHostVersion[[:space:]]*=[[:space:]]*([0-9]+).*/\1/p' "$file" | head -n1)
  if [[ -z "$min" || -z "$max" ]]; then
    echo "10 12"
    return
  fi
  echo "$min $max"
}

declare -a CANDIDATE_PATHS=()
declare -A SEEN_CANDIDATE_PATHS=()

add_unique_candidate() {
  local path_value
  path_value="$(real_path "$1")"
  if [[ -n "${SEEN_CANDIDATE_PATHS[$path_value]:-}" ]]; then
    return
  fi
  SEEN_CANDIDATE_PATHS[$path_value]=1
  CANDIDATE_PATHS+=("$path_value")
}

add_candidate_path() {
  local path_value=${1:-}
  if [[ -z "$path_value" ]]; then
    return
  fi

  local full_path nested_path
  full_path="$(real_path "$path_value")"
  if [[ -f "$full_path/manifest.json" ]]; then
    add_unique_candidate "$full_path"
  fi
  nested_path="$full_path/WidevineCdm"
  if [[ -f "$nested_path/manifest.json" ]]; then
    add_unique_candidate "$nested_path"
  fi
}

find_local_widevine_candidates() {
  shopt -s nullglob

  add_candidate_path "${ELECTRON_PACKAGE_WIDEVINE_CDM_DIR:-}"
  add_candidate_path "$SRC_DIR/out/widevine-cdm/WidevineCdm"
  add_candidate_path "$SRC_DIR/out/Release/WidevineCdm"
  add_candidate_path "$WORKSPACE_ROOT/WidevineCdm"

  local chrome_root
  for chrome_root in \
    /opt/google/chrome \
    /opt/google/chrome-beta \
    /opt/google/chrome-unstable \
    /usr/lib/google-chrome \
    /usr/lib/chromium \
    /usr/lib/chromium-browser \
    /snap/chromium/current; do
    [[ -d "$chrome_root" ]] || continue
    add_candidate_path "$chrome_root"
    add_candidate_path "$chrome_root/WidevineCdm"
    local child
    for child in "$chrome_root"/*; do
      [[ -d "$child" ]] || continue
      if [[ "$(basename "$child")" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        add_candidate_path "$child/WidevineCdm"
      fi
    done
  done

  local profile_root
  for profile_root in \
    "$HOME/.config/google-chrome/WidevineCdm" \
    "$HOME/.config/google-chrome-beta/WidevineCdm" \
    "$HOME/.config/google-chrome-unstable/WidevineCdm" \
    "$HOME/.config/chromium/WidevineCdm" \
    "$HOME/snap/chromium/common/chromium/WidevineCdm"; do
    [[ -d "$profile_root" ]] || continue
    add_candidate_path "$profile_root"
    local child
    for child in "$profile_root"/*; do
      [[ -d "$child" ]] && add_candidate_path "$child"
    done
  done

  local manual_root
  for manual_root in "$HOME/Desktop" "$HOME/Downloads"; do
    [[ -d "$manual_root" ]] || continue
    add_candidate_path "$manual_root/WidevineCdm"
    local child
    for child in "$manual_root"/*; do
      [[ -d "$child" ]] || continue
      if [[ "$(basename "$child")" == "WidevineCdm" || "$(basename "$child")" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        add_candidate_path "$child"
      fi
    done
  done
}

select_best_widevine_candidate() {
  local chromium_version=$1
  local host_min=$2
  local host_max=$3
  local allow_unknown_source_version=$4
  shift 4

  node - "$chromium_version" "$host_min" "$host_max" "$CDM_OS" "$CDM_ARCH" "$CDM_PLATFORM" "$CDM_LIBRARY_NAME" "$REQUIRE_CHROME_MAJOR_MATCH" "$allow_unknown_source_version" "$@" <<'NODE'
const fs = require('node:fs');
const path = require('node:path');

const [
  chromiumVersionText,
  hostMinText,
  hostMaxText,
  cdmOs,
  cdmArch,
  cdmPlatform,
  cdmLibraryName,
  requireMajorMatchText,
  allowUnknownSourceVersionText,
  ...candidatePaths
] = process.argv.slice(2);

const chromiumVersion = parseVersion(chromiumVersionText);
const hostMin = Number(hostMinText);
const hostMax = Number(hostMaxText);
const requireMajorMatch = requireMajorMatchText === '1';
const allowUnknownSourceVersion = allowUnknownSourceVersionText === '1';

function parseVersion(value) {
  const parts = String(value || '').split('.').map((part) => Number(part));
  if (parts.length === 0 || parts.some((part) => !Number.isInteger(part) || part < 0)) {
    throw new Error(`Invalid version string: ${value}`);
  }
  while (parts.length < 4) parts.push(0);
  return parts.slice(0, 4);
}

function compareVersion(a, b) {
  for (let i = 0; i < 4; i++) {
    if (a[i] !== b[i]) return a[i] - b[i];
  }
  return 0;
}

function versionScore(value) {
  const version = parseVersion(value);
  return (version[0] * 1000000000) + (version[1] * 1000000) + (version[2] * 1000) + version[3];
}

function splitCdmVersionList(value) {
  if (!value) return [];
  return String(value)
    .split(',')
    .map((item) => item.trim())
    .filter((item) => /^\d+$/.test(item))
    .map((item) => Number(item));
}

function browserVersionFromPath(pathValue) {
  const parts = pathValue.split(/[\\/]/);
  for (let i = parts.length - 1; i >= 0; i--) {
    if (/^\d+\.\d+\.\d+\.\d+$/.test(parts[i])) {
      return parts[i];
    }
  }
  return null;
}

function validateCandidate(pathValue) {
  const manifestPath = path.join(pathValue, 'manifest.json');
  const licensePath = path.join(pathValue, 'LICENSE');
  const libraryPath = path.join(pathValue, '_platform_specific', cdmPlatform, cdmLibraryName);
  if (!fs.existsSync(manifestPath) || !fs.existsSync(licensePath) || !fs.existsSync(libraryPath)) {
    return null;
  }

  let manifest;
  try {
    manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  } catch {
    console.error(`warning: skipping malformed Widevine manifest: ${manifestPath}`);
    return null;
  }

  const platformOk = Array.isArray(manifest.platforms) &&
    manifest.platforms.some((platform) => platform.os === cdmOs && platform.arch === cdmArch);
  if (!platformOk) return null;

  const minimumChromeVersion = parseVersion(manifest.minimum_chrome_version);
  if (compareVersion(minimumChromeVersion, chromiumVersion) > 0) return null;

  const hostVersions = splitCdmVersionList(manifest['x-cdm-host-versions']);
  if (!hostVersions.some((version) => version >= hostMin && version <= hostMax)) {
    return null;
  }

  const browserVersion = browserVersionFromPath(pathValue);
  if (requireMajorMatch) {
    if (browserVersion) {
      if (parseVersion(browserVersion)[0] !== chromiumVersion[0]) {
        return null;
      }
    } else if (!allowUnknownSourceVersion) {
      return null;
    }
  }

  let score = 100;
  if (browserVersion) {
    const browser = parseVersion(browserVersion);
    if (compareVersion(browser, chromiumVersion) === 0) {
      score += 500;
    } else if (browser[0] === chromiumVersion[0]) {
      score += 400;
    } else {
      score += Math.max(0, 200 - Math.abs(browser[0] - chromiumVersion[0]));
    }
  }

  return {
    Path: path.resolve(pathValue),
    ManifestPath: manifestPath,
    LibraryPath: libraryPath,
    LicensePath: licensePath,
    SigPath: `${libraryPath}.sig`,
    CdmVersion: String(manifest.version || ''),
    CdmVersionScore: versionScore(manifest.version || '0.0.0.0'),
    MinimumChromeVersion: String(manifest.minimum_chrome_version || ''),
    HostVersions: hostVersions.join(','),
    BrowserVersion: browserVersion,
    Score: score,
    LastWriteTimeMs: fs.statSync(libraryPath).mtimeMs
  };
}

const candidates = candidatePaths
  .map(validateCandidate)
  .filter(Boolean)
  .sort((a, b) =>
    (b.Score - a.Score) ||
    (b.CdmVersionScore - a.CdmVersionScore) ||
    (b.LastWriteTimeMs - a.LastWriteTimeMs));

if (candidates.length === 0) {
  process.exit(1);
}

console.log(JSON.stringify(candidates[0]));
NODE
}

json_get() {
  local json=$1
  local key=$2
  node -e 'const value = JSON.parse(process.argv[1])[process.argv[2]]; if (value !== undefined && value !== null) console.log(value);' "$json" "$key"
}

find_widevine_root_from_library() {
  local library_path=$1
  local directory
  directory="$(dirname "$library_path")"
  for _ in 1 2 3 4 5; do
    if [[ -f "$directory/manifest.json" ]]; then
      real_path "$directory"
      return 0
    fi
    local parent
    parent="$(dirname "$directory")"
    [[ "$parent" != "$directory" ]] || break
    directory="$parent"
  done
  return 1
}

extract_zip() {
  local zip_path=$1
  local destination_dir=$2
  mkdir -p "$destination_dir"
  if command -v unzip >/dev/null 2>&1; then
    unzip -q "$zip_path" -d "$destination_dir"
  else
    tar -xf "$zip_path" -C "$destination_dir"
  fi
}

expand_crx_to_directory() {
  local crx_path=$1
  local destination_dir=$2
  local zip_path
  zip_path="$(dirname "$crx_path")/component.zip"

  node - "$crx_path" "$zip_path" <<'NODE'
const fs = require('node:fs');
const [crxPath, zipPath] = process.argv.slice(2);
const data = fs.readFileSync(crxPath);
let offset = 0;
if (data.subarray(0, 4).toString('ascii') === 'Cr24') {
  const version = data.readUInt32LE(4);
  if (version === 3) {
    offset = 12 + data.readUInt32LE(8);
  } else if (version === 2) {
    offset = 16 + data.readUInt32LE(8) + data.readUInt32LE(12);
  } else {
    throw new Error(`Unsupported CRX version: ${version}`);
  }
}
fs.writeFileSync(zipPath, data.subarray(offset));
NODE

  extract_zip "$zip_path" "$destination_dir"
}

get_update2_download_json() {
  local response_file=$1
  node - "$response_file" <<'NODE'
const fs = require('node:fs');
const responsePath = process.argv[2];
const content = fs.readFileSync(responsePath, 'utf8').replace(/^\)\]\}'\s*/, '');
const json = JSON.parse(content);
const app = json.response && Array.isArray(json.response.apps) ? json.response.apps[0] : null;
if (!app || app.status !== 'ok' || !app.updatecheck || app.updatecheck.status !== 'ok') {
  const status = app && app.updatecheck ? app.updatecheck.status : 'missing response';
  throw new Error(`Google update2 did not provide a Widevine update: ${status}`);
}

function preferredUrl(urlItems) {
  const urls = [];
  for (const item of urlItems || []) {
    if (!item) continue;
    if (typeof item === 'string') urls.push(item);
    else if (item.url) urls.push(String(item.url));
  }
  return urls.find((url) => url.startsWith('https://')) || urls[0] || null;
}

const updatecheck = app.updatecheck;
for (const pipeline of updatecheck.pipelines || []) {
  for (const operation of pipeline.operations || []) {
    if (operation.type !== 'download') continue;
    const url = preferredUrl(operation.urls);
    if (!url) continue;
    console.log(JSON.stringify({
      url,
      sha256: operation.out && operation.out.sha256 ? String(operation.out.sha256) : ''
    }));
    process.exit(0);
  }
}

const baseUrl = updatecheck.urls && updatecheck.urls.url && updatecheck.urls.url[0] && updatecheck.urls.url[0].url;
const pkg = updatecheck.manifest && updatecheck.manifest.packages && updatecheck.manifest.packages.package && updatecheck.manifest.packages.package[0];
if (baseUrl && pkg && pkg.name) {
  console.log(JSON.stringify({
    url: `${baseUrl}${pkg.name}`,
    sha256: pkg.hash_sha256 ? String(pkg.hash_sha256) : ''
  }));
  process.exit(0);
}

throw new Error('Google update2 response did not include a downloadable package URL.');
NODE
}

download_widevine_from_update2() {
  local chromium_version=$1
  local temp_dir=$2
  require_command curl

  local request_file response_file update_uri crx_path download_json download_url download_sha extract_dir
  request_file="$temp_dir/update2-request.json"
  response_file="$temp_dir/update2-response.json"
  crx_path="$temp_dir/widevine.crx3"
  extract_dir="$temp_dir/update2"

  update_uri=$(node - "$chromium_version" "$CDM_COMPONENT_ID" "$CDM_ARCH" "$UPDATE2_JSON_URL" "$request_file" <<'NODE'
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const [chromiumVersion, componentId, cdmArch, updateUrl, requestPath] = process.argv.slice(2);
const request = {
  request: {
    protocol: '4.0',
    dedup: 'cr',
    acceptformat: 'crx3,download,puff,run,xz,zucc',
    ismachine: true,
    sessionid: `{${crypto.randomUUID().toUpperCase()}}`,
    requestid: `{${crypto.randomUUID().toUpperCase()}}`,
    '@os': 'linux',
    arch: cdmArch,
    nacl_arch: cdmArch === 'x64' ? 'x86-64' : cdmArch,
    prodversion: chromiumVersion,
    updaterversion: chromiumVersion,
    '@updater': 'chrome',
    prodchannel: 'stable',
    updaterchannel: 'stable',
    os: { platform: 'linux', version: os.release(), arch: cdmArch },
    hw: { physmemory: Math.max(1, Math.floor(os.totalmem() / 1024 / 1024 / 1024)) },
    apps: [{
      appid: componentId,
      version: '0.0.0.0',
      lang: 'en-US',
      enabled: true,
      installsource: 'ondemand',
      updatecheck: {}
    }]
  }
};
const body = JSON.stringify(request);
fs.writeFileSync(requestPath, body);
const requestHash = crypto.createHash('sha256').update(body).digest('hex');
const nonce = crypto.randomBytes(32).toString('base64').replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
console.log(`${updateUrl}?cup2key=16:${nonce}&cup2hreq=${requestHash}`);
NODE
)

  curl -fsSL \
    -X POST "$update_uri" \
    -H "Content-Type: application/json" \
    -H "X-Goog-Update-Updater: chrome-$chromium_version" \
    -H "X-Goog-Update-Interactivity: fg" \
    -H "X-Goog-Update-AppId: $CDM_COMPONENT_ID" \
    --data-binary "@$request_file" \
    --max-time 90 \
    -o "$response_file"

  download_json=$(get_update2_download_json "$response_file")
  download_url=$(json_get "$download_json" url)
  download_sha=$(json_get "$download_json" sha256)
  [[ -n "$download_url" ]] || die "Google update2 response did not include a downloadable package URL"

  curl -fL --max-time 300 -o "$crx_path" "$download_url"
  if [[ -n "$download_sha" ]]; then
    local actual_sha
    actual_sha=$(sha256sum "$crx_path" | awk '{ print $1 }')
    if [[ "$actual_sha" != "${download_sha,,}" ]]; then
      die "downloaded Widevine CRX hash mismatch. Expected $download_sha, got $actual_sha"
    fi
  fi

  mkdir -p "$extract_dir"
  expand_crx_to_directory "$crx_path" "$extract_dir"
  echo "$extract_dir"
}

download_widevine_from_chrome_for_testing() {
  local chromium_version=$1
  local temp_dir=$2
  require_command curl

  local platform
  case "$CDM_ARCH" in
    x64) platform="linux64" ;;
    arm64) platform="linux-arm64" ;;
    *) platform="linux-$CDM_ARCH" ;;
  esac

  local known_file zip_path extract_dir download_url
  known_file="$temp_dir/chrome-for-testing-known-good.json"
  zip_path="$temp_dir/chrome-for-testing.zip"
  extract_dir="$temp_dir/chrome-for-testing"

  curl -fsSL --max-time 90 -o "$known_file" "$CHROME_FOR_TESTING_KNOWN_GOOD_URL"
  download_url=$(node - "$known_file" "$chromium_version" "$platform" <<'NODE'
const fs = require('node:fs');
const [knownPath, chromiumVersion, platform] = process.argv.slice(2);
const known = JSON.parse(fs.readFileSync(knownPath, 'utf8'));
const entry = (known.versions || []).find((item) => item.version === chromiumVersion);
if (!entry) {
  throw new Error(`Chrome for Testing has no exact ${platform} archive for Chromium ${chromiumVersion}.`);
}
const download = entry.downloads && entry.downloads.chrome &&
  entry.downloads.chrome.find((item) => item.platform === platform);
if (!download || !download.url) {
  throw new Error(`Chrome for Testing has no ${platform} Chrome archive for Chromium ${chromiumVersion}.`);
}
console.log(download.url);
NODE
)

  curl -fL --max-time 900 -o "$zip_path" "$download_url"
  mkdir -p "$extract_dir"
  extract_zip "$zip_path" "$extract_dir"
  echo "$extract_dir"
}

collect_download_candidates() {
  local root=$1
  add_candidate_path "$root"
  while IFS= read -r -d '' library_path; do
    local widevine_root
    if widevine_root=$(find_widevine_root_from_library "$library_path"); then
      add_candidate_path "$widevine_root"
    fi
  done < <(find "$root" -type f -name "$CDM_LIBRARY_NAME" -print0 2>/dev/null)
}

select_downloaded_widevine_candidate() {
  local temp_dir="$SRC_DIR/out/widevine-cdm-download"
  rm -rf "$temp_dir"
  mkdir -p "$temp_dir"

  local download_roots=()
  log "Trying Google update2 for target Chromium Widevine CDM..."
  if update2_root=$(download_widevine_from_update2 "$CHROMIUM_VERSION_TEXT" "$temp_dir" 2> >(sed 's/^/warning: /' >&2)); then
    download_roots+=("$update2_root")
  fi

  if [[ "${#download_roots[@]}" -eq 0 ]]; then
    log "Trying Chrome for Testing exact-version archive..."
    if cft_root=$(download_widevine_from_chrome_for_testing "$CHROMIUM_VERSION_TEXT" "$temp_dir" 2> >(sed 's/^/warning: /' >&2)); then
      download_roots+=("$cft_root")
    fi
  fi

  for root in "${download_roots[@]}"; do
    collect_download_candidates "$root"
  done

  if [[ "${#CANDIDATE_PATHS[@]}" -eq 0 ]]; then
    return 1
  fi
  select_best_widevine_candidate "$CHROMIUM_VERSION_TEXT" "$HOST_MIN" "$HOST_MAX" 1 "${CANDIDATE_PATHS[@]}"
}

copy_widevine_cdm() {
  local source_dir=$1
  local destination_dir=$2
  source_dir="$(real_path "$source_dir")"
  destination_dir="$(real_path "$destination_dir")"

  if [[ "$source_dir" == "$destination_dir" ]]; then
    return
  fi

  if [[ -e "$destination_dir" ]]; then
    if [[ "$FORCE" -ne 1 ]]; then
      die "output directory already exists: $destination_dir. Pass --force to replace it."
    fi
    rm -rf "$destination_dir"
  fi

  mkdir -p "$(dirname "$destination_dir")"
  cp -a "$source_dir" "$destination_dir"
}

CHROMIUM_VERSION_TEXT="$(get_chromium_version "$SRC_DIR")"
read -r HOST_MIN HOST_MAX < <(get_supported_host_range "$SRC_DIR")

log "Electron target: $TARGET"
log "Source dir: $SRC_DIR"
log "Chromium version: $CHROMIUM_VERSION_TEXT"
log "Required CDM platform: $CDM_PLATFORM"
log "Supported CDM host versions: $HOST_MIN..$HOST_MAX"

SELECTED_JSON=""

if [[ "$DOWNLOAD_IF_MISSING" -eq 1 && "$PREFER_DOWNLOAD" -eq 1 ]]; then
  SELECTED_JSON=$(select_downloaded_widevine_candidate || true)
fi

if [[ -z "$SELECTED_JSON" ]]; then
  find_local_widevine_candidates
  if [[ "${#CANDIDATE_PATHS[@]}" -gt 0 ]]; then
    SELECTED_JSON=$(select_best_widevine_candidate "$CHROMIUM_VERSION_TEXT" "$HOST_MIN" "$HOST_MAX" 0 "${CANDIDATE_PATHS[@]}" || true)
  fi
fi

if [[ -z "$SELECTED_JSON" && "$DOWNLOAD_IF_MISSING" -eq 1 && "$PREFER_DOWNLOAD" -ne 1 ]]; then
  log "No compatible local Widevine CDM found."
  SELECTED_JSON=$(select_downloaded_widevine_candidate || true)
fi

if [[ -z "$SELECTED_JSON" ]]; then
  die "no compatible Widevine CDM found for Chromium $CHROMIUM_VERSION_TEXT and platform $CDM_PLATFORM"
fi

SELECTED_PATH="$(json_get "$SELECTED_JSON" Path)"
SELECTED_VERSION="$(json_get "$SELECTED_JSON" CdmVersion)"
SELECTED_BROWSER_VERSION="$(json_get "$SELECTED_JSON" BrowserVersion)"

log "Selected Widevine CDM: $SELECTED_PATH"
log "Widevine version: $SELECTED_VERSION"
if [[ -n "$SELECTED_BROWSER_VERSION" ]]; then
  log "Source Chrome version: $SELECTED_BROWSER_VERSION"
  if [[ "${SELECTED_BROWSER_VERSION%%.*}" != "${CHROMIUM_VERSION_TEXT%%.*}" ]]; then
    warn "selected CDM comes from Chrome major ${SELECTED_BROWSER_VERSION%%.*}, while Electron Chromium major is ${CHROMIUM_VERSION_TEXT%%.*}. Manifest and host checks passed, but runtime playback should still be tested."
  fi
fi

copy_widevine_cdm "$SELECTED_PATH" "$OUTPUT_DIR"
log "Prepared Widevine CDM directory: $OUTPUT_DIR"

if [[ "$PRINT_ENVIRONMENT" -eq 1 ]]; then
  log "export ELECTRON_PACKAGE_INCLUDE_WIDEVINE_CDM=1"
  log "export ELECTRON_PACKAGE_WIDEVINE_LICENSE_ACK=1"
  log "export ELECTRON_PACKAGE_WIDEVINE_CDM_DIR='$OUTPUT_DIR'"
fi

echo "$OUTPUT_DIR"
