#!/usr/bin/env node

const childProcess = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const args = parseArgs(process.argv.slice(2));
const target = args.target || process.env.ELECTRON_WORKSPACE_TARGET || '41';
const defaultSrcDir = path.resolve(__dirname, '..', target, 'src');
const srcDir = path.resolve(args.srcDir || process.env.ELECTRON_WORKSPACE_SRC_DIR || defaultSrcDir);
const electronDir = path.join(srcDir, 'electron');
const { getElectronVersion } = require(path.join(electronDir, 'script', 'lib', 'get-version'));
const defaultOutDir = path.resolve(srcDir, 'out', 'Release');
const defaultPackageName = 'electron';
const defaultPackageKind = 'platform';
const defaultPackageDescription = 'Electron distribution';
const defaultOptionalPlatformTargets = [
  ['linux', 'x64'],
  ['win32', 'x64']
];

const mode = args.mode || 'dev';
const packageName = args.packageName || process.env.ELECTRON_PACKAGE_NAME || defaultPackageName;
const packageKind = args.packageKind || process.env.ELECTRON_PACKAGE_KIND || defaultPackageKind;
const platformPackageName = args.platformPackageName || process.env.ELECTRON_PLATFORM_PACKAGE_NAME || platformPackageNameFor(packageName);
const outDir = path.resolve(args.outDir || process.env.ELECTRON_BUILD_OUT_DIR || defaultOutDir);
const registry = args.registry || process.env.npm_config_registry || '';
const baseVersion = stripLeadingV(args.baseVersion || process.env.ELECTRON_PACKAGE_BASE_VERSION || getElectronVersion());
const stagingRoot = path.resolve(args.stagingDir || process.env.ELECTRON_PACKAGE_STAGING_DIR || path.join(srcDir, 'out', 'electron-npm'));
const packageVersion = args.version || resolvePackageVersion();
const optionalPlatformPackages = resolveOptionalPlatformPackages();
const includeWidevineCdm = parseBoolean(args.includeWidevineCdm || process.env.ELECTRON_PACKAGE_INCLUDE_WIDEVINE_CDM);
const widevineCdmDir = args.widevineCdmDir || process.env.ELECTRON_PACKAGE_WIDEVINE_CDM_DIR;
const widevineLicenseAck = parseBoolean(args.widevineLicenseAck || process.env.ELECTRON_PACKAGE_WIDEVINE_LICENSE_ACK);

main();

function main () {
  validateMode();
  validatePackageKind();
  validatePackageVersion();
  validateInputs();

  const tarballs = [];

  switch (packageKind) {
    case 'bundled':
      tarballs.push(createBundledPackage(packageName));
      break;
    case 'platform':
      tarballs.push(createPlatformPackage(platformPackageName));
      break;
    case 'wrapper':
      tarballs.push(createWrapperPackage(packageName));
      break;
    case 'split':
      tarballs.push(createPlatformPackage(platformPackageName));
      tarballs.push(createWrapperPackage(packageName));
      break;
  }

  console.log(tarballs.join('\n'));
}

function parseArgs (argv) {
  const parsed = {};
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (!arg.startsWith('--')) {
      continue;
    }
    const key = arg.slice(2).replace(/-([a-z])/g, (_, c) => c.toUpperCase());
    const next = argv[i + 1];
    if (next && !next.startsWith('--')) {
      parsed[key] = next;
      i++;
    } else {
      parsed[key] = true;
    }
  }
  return parsed;
}

function validateMode () {
  if (mode !== 'dev' && mode !== 'release') {
    throw new Error(`Unsupported mode: ${mode}. Use "dev" or "release".`);
  }
}

function validatePackageKind () {
  if (!['bundled', 'platform', 'wrapper', 'split'].includes(packageKind)) {
    throw new Error(`Unsupported package kind: ${packageKind}. Use "bundled", "platform", "wrapper", or "split".`);
  }
}

function validateInputs () {
  if (packageKind !== 'wrapper') {
    assertFile(path.join(outDir, 'dist.zip'), 'missing Electron distribution zip');
  } else if (includeWidevineCdm) {
    throw new Error('Widevine CDM can only be included in bundled, platform, or split package modes.');
  }
  assertFile(path.join(electronDir, 'electron.d.ts'), 'missing generated TypeScript definitions; run npm run create-typescript-definitions first');
  assertFile(path.join(electronDir, 'npm', 'index.js'), 'missing npm package template');
  assertFile(path.join(electronDir, 'npm', 'cli.js'), 'missing npm package CLI template');
  validateWidevineCdmInputs();
}

function resolvePackageVersion () {
  if (mode === 'release') {
    return baseVersion;
  }

  const devSequence = args.devNumber || args.devSequence || process.env.ELECTRON_PACKAGE_DEV_NUMBER || 'auto';
  if (devSequence === 'auto') {
    return `${baseVersion}-dev.${nextDevSequence()}`;
  }
  if (!/^\d+$/.test(String(devSequence))) {
    throw new Error(`Invalid dev sequence: ${devSequence}. Use a non-negative integer or "auto".`);
  }
  return `${baseVersion}-dev.${devSequence}`;
}

function validatePackageVersion () {
  const devMatch = packageVersion.match(/-dev\.(.+)$/);
  if (devMatch && !/^\d+$/.test(devMatch[1])) {
    throw new Error(`Invalid dev package version: ${packageVersion}. Use ${baseVersion}-dev.<number>.`);
  }
}

function nextDevSequence () {
  const sequences = [
    ...publishedDevSequences(),
    ...localDevSequences()
  ];

  if (sequences.length === 0) {
    return 0;
  }

  return Math.max(...sequences) + 1;
}

function publishedDevSequences () {
  if (!registry) {
    return [];
  }

  return devSequencePackageNames()
    .flatMap(name => publishedDevSequencesForPackage(name));
}

function publishedDevSequencesForPackage (name) {
  const view = spawnNpmSync([
    'view',
    name,
    'versions',
    '--json',
    '--registry',
    registry
  ], electronDir, {
    cwd: electronDir,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe']
  });

  if (view.status !== 0) {
    return [];
  }

  return devSequencesFromVersions(parseNpmVersions(view.stdout));
}

function localDevSequences () {
  if (!fs.existsSync(stagingRoot)) {
    return [];
  }

  const packageDirPrefixes = devSequencePackageNames()
    .map(name => `${sanitizePackageName(name)}-${baseVersion}-dev.`);
  const matchingEntries = fs.readdirSync(stagingRoot)
    .filter(entry => packageDirPrefixes.some(prefix => entry.startsWith(prefix)));

  return devSequencesFromVersions(matchingEntries);
}

function devSequencePackageNames () {
  if (packageKind === 'platform') {
    return [platformPackageName];
  }

  return [
    ...new Set([
      packageName,
      platformPackageName,
      ...resolveOptionalPlatformPackages()
    ])
  ];
}

function parseNpmVersions (stdout) {
  try {
    const versions = JSON.parse(stdout);
    return Array.isArray(versions) ? versions : [versions];
  } catch {
    return [];
  }
}

function devSequencesFromVersions (versions) {
  const prefix = `${baseVersion}-dev.`;
  const pattern = new RegExp(`${escapeRegExp(prefix)}(\\d+)`);

  return versions
    .map(version => String(version).match(pattern))
    .filter(Boolean)
    .map(match => Number(match[1]))
    .filter(Number.isInteger);
}

function resolveOptionalPlatformPackages () {
  const value = args.optionalPlatformPackages || process.env.ELECTRON_OPTIONAL_PLATFORM_PACKAGES;
  if (!value) {
    return [
      ...new Set([
        ...defaultOptionalPlatformTargets.map(([platform, arch]) => platformPackageNameForTarget(packageName, platform, arch)),
        platformPackageName
      ])
    ];
  }
  return value
    .split(',')
    .map(name => name.trim())
    .filter(Boolean);
}

function createBundledPackage (name) {
  const packageDir = preparePackageDir(name);
  copyNpmTemplate(packageDir, ['index.js', 'cli.js', 'install.js']);
  copyTypeDefinitions(packageDir);
  extractDistribution(packageDir);
  const hasInjectedWidevineCdm = copyWidevineCdm(packageDir);
  writeBundledPackageJson(packageDir, name);
  writePathFile(packageDir);
  copyDistributionZip(packageDir, hasInjectedWidevineCdm);
  return packPackage(packageDir);
}

function createPlatformPackage (name) {
  const packageDir = preparePackageDir(name);
  copyNpmTemplate(packageDir, ['index.js', 'cli.js']);
  copyTypeDefinitions(packageDir);
  extractDistribution(packageDir);
  const hasInjectedWidevineCdm = copyWidevineCdm(packageDir);
  writePlatformPackageJson(packageDir, name);
  writePathFile(packageDir);
  copyDistributionZip(packageDir, hasInjectedWidevineCdm);
  return packPackage(packageDir);
}

function createWrapperPackage (name) {
  const packageDir = preparePackageDir(name);
  copyNpmTemplate(packageDir, ['cli.js']);
  copyTypeDefinitions(packageDir);
  writeWrapperIndex(packageDir);
  writeWrapperPackageJson(packageDir, name);
  return packPackage(packageDir);
}

function preparePackageDir (name) {
  const packageDir = path.join(stagingRoot, sanitizePackageDirName(name, packageVersion));
  fs.rmSync(packageDir, { recursive: true, force: true });
  fs.mkdirSync(packageDir, { recursive: true });
  return packageDir;
}

function copyNpmTemplate (packageDir, names) {
  for (const name of names) {
    fs.copyFileSync(path.join(electronDir, 'npm', name), path.join(packageDir, name));
  }
}

function copyTypeDefinitions (packageDir) {
  fs.copyFileSync(path.join(electronDir, 'electron.d.ts'), path.join(packageDir, 'electron.d.ts'));
}

function extractDistribution (packageDir) {
  const distDir = path.join(packageDir, 'dist');
  fs.mkdirSync(distDir, { recursive: true });
  extractZip(path.join(outDir, 'dist.zip'), distDir);
  fs.writeFileSync(path.join(distDir, 'version'), packageVersion);
}

function validateWidevineCdmInputs () {
  if (!includeWidevineCdm) {
    return;
  }
  if (!widevineLicenseAck) {
    throw new Error('Refusing to package Widevine CDM without --widevine-license-ack or ELECTRON_PACKAGE_WIDEVINE_LICENSE_ACK=1.');
  }
  if (!widevineCdmDir) {
    throw new Error('Missing Widevine CDM source directory. Use --widevine-cdm-dir or ELECTRON_PACKAGE_WIDEVINE_CDM_DIR.');
  }

  const sourceDir = resolveWidevineCdmSourceDir();
  assertFile(path.join(sourceDir, 'manifest.json'), 'missing Widevine CDM manifest');
  assertFile(path.join(sourceDir, 'LICENSE'), 'missing Widevine CDM license file');
  assertFile(
    path.join(sourceDir, '_platform_specific', widevinePlatformArch(), widevineLibraryName()),
    `missing Widevine CDM library for ${widevinePlatformArch()}`
  );
}

function copyWidevineCdm (packageDir) {
  if (!includeWidevineCdm) {
    return false;
  }

  const sourceDir = resolveWidevineCdmSourceDir();
  const targetDir = path.join(packageDir, 'dist', 'WidevineCdm');
  fs.rmSync(targetDir, { recursive: true, force: true });
  copyDirectory(sourceDir, targetDir);
  console.log(`Included Widevine CDM from ${sourceDir}`);
  return true;
}

function writeBundledPackageJson (packageDir, name) {
  const packageJson = basePackageJson(name);
  packageJson.description = defaultPackageDescription;
  packageJson.files = [
    'cli.js',
    'dist',
    'electron.d.ts',
    'index.js',
    'package.json',
    'path.txt',
    'zips'
  ];
  delete packageJson.dependencies['@electron/get'];
  delete packageJson.dependencies['extract-zip'];

  fs.writeFileSync(path.join(packageDir, 'package.json'), `${JSON.stringify(packageJson, null, 2)}\n`);
}

function writePlatformPackageJson (packageDir, name) {
  const packageJson = basePackageJson(name);
  packageJson.description = `Electron binary for ${electronPlatform()}-${electronArch()}`;
  packageJson.os = [electronPlatform()];
  packageJson.cpu = [electronArch()];
  packageJson.files = [
    'cli.js',
    'dist',
    'electron.d.ts',
    'index.js',
    'package.json',
    'path.txt',
    'zips'
  ];
  delete packageJson.bin['install-electron'];
  delete packageJson.dependencies['@electron/get'];
  delete packageJson.dependencies['extract-zip'];

  fs.writeFileSync(path.join(packageDir, 'package.json'), `${JSON.stringify(packageJson, null, 2)}\n`);
}

function writeWrapperPackageJson (packageDir, name) {
  const packageJson = basePackageJson(name);
  packageJson.description = 'Electron platform package selector';
  packageJson.files = [
    'cli.js',
    'electron.d.ts',
    'index.js',
    'package.json'
  ];
  delete packageJson.bin['install-electron'];
  packageJson.optionalDependencies = Object.fromEntries(
    optionalPlatformPackages.map(name => [name, packageVersion])
  );
  delete packageJson.dependencies['@electron/get'];
  delete packageJson.dependencies['extract-zip'];

  fs.writeFileSync(path.join(packageDir, 'package.json'), `${JSON.stringify(packageJson, null, 2)}\n`);
}

function basePackageJson (name) {
  const packageJsonPath = path.join(electronDir, 'npm', 'package.json');
  const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));

  packageJson.name = name;
  packageJson.version = packageVersion;
  packageJson.license = 'MIT';
  packageJson.scripts = {};
  return packageJson;
}

function writeWrapperIndex (packageDir) {
  const platformPackages = Object.fromEntries(
    optionalPlatformPackages.map(name => [platformKeyFromPackageName(name), name])
  );
  const source = `'use strict';

const platformPackages = ${JSON.stringify(platformPackages, null, 2)};
const platformKey = \`\${process.platform}-\${process.arch}\`;
const packageName = platformPackages[platformKey];

if (!packageName) {
  throw new Error(\`Electron does not support \${platformKey}. Available packages: \${Object.keys(platformPackages).join(', ') || 'none'}\`);
}

let packagePath;
try {
  packagePath = require.resolve(packageName);
} catch (error) {
  if (error && error.code === 'MODULE_NOT_FOUND') {
    throw new Error(\`Electron platform package \${packageName} is not installed. Reinstall \${packageName} for \${platformKey}.\`);
  }
  throw error;
}

module.exports = require(packagePath);
`;
  fs.writeFileSync(path.join(packageDir, 'index.js'), source);
}

function writePathFile (packageDir) {
  fs.writeFileSync(path.join(packageDir, 'path.txt'), platformPath());
}

function copyDistributionZip (packageDir, fromExtractedDist = false) {
  const zipsDir = path.join(packageDir, 'zips');
  fs.mkdirSync(zipsDir, { recursive: true });
  const zipPath = path.join(zipsDir, `electron-v${packageVersion}-${electronPlatform()}-${electronArch()}.zip`);
  if (fromExtractedDist) {
    fs.rmSync(zipPath, { force: true });
    createZipFromDirectory(zipPath, path.join(packageDir, 'dist'));
    validateDistributionZip(zipPath);
    return;
  }
  fs.copyFileSync(path.join(outDir, 'dist.zip'), zipPath);
  validateDistributionZip(zipPath);
}

function packPackage (packageDir) {
  fs.mkdirSync(stagingRoot, { recursive: true });
  const result = runNpm(['pack', packageDir, '--pack-destination', stagingRoot, '--json'], electronDir, {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe']
  });
  let packs;
  try {
    packs = JSON.parse(result.stdout);
  } catch {
    throw new Error(`Failed to parse npm pack output: ${result.stdout}`);
  }
  const tarballPath = path.join(stagingRoot, packs[0].filename);
  validatePackageTarball(tarballPath);
  return tarballPath;
}

function validateDistributionZip (zipPath) {
  const entries = listZipEntries(zipPath).map(entry => entry.replace(/\\/g, '/'));
  const dotEntries = entries.filter(entry => entry === '.' || entry === './' || entry.startsWith('./'));
  if (dotEntries.length > 0) {
    throw new Error(`Invalid distribution zip root entries in ${zipPath}: ${dotEntries.slice(0, 5).join(', ')}`);
  }

  const electronBinary = platformPath();
  if (!entries.includes(electronBinary)) {
    throw new Error(`Invalid distribution zip ${zipPath}: missing ${electronBinary}`);
  }

  if (includeWidevineCdm) {
    const widevineLibrary = `WidevineCdm/_platform_specific/${widevinePlatformArch()}/${widevineLibraryName()}`;
    if (!entries.includes(widevineLibrary)) {
      throw new Error(`Invalid distribution zip ${zipPath}: missing ${widevineLibrary}`);
    }
  }
}

function validatePackageTarball (tarballPath) {
  const result = run('tar', ['-tf', tarballPath], srcDir, {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe']
  });
  const entries = result.stdout.split(/\r?\n/).filter(Boolean);
  if (!entries.includes('package/package.json')) {
    throw new Error(`Invalid npm tarball ${tarballPath}: missing package/package.json`);
  }
}

function run (command, commandArgs, cwd, options = {}) {
  const result = childProcess.spawnSync(command, commandArgs, {
    cwd,
    encoding: options.encoding || 'utf8',
    stdio: options.stdio || 'inherit',
    maxBuffer: options.maxBuffer || 128 * 1024 * 1024
  });
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    throw new Error(`${command} ${commandArgs.join(' ')} failed with exit code ${result.status}`);
  }
  return result;
}

function assertFile (filePath, message) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`${message}: ${filePath}`);
  }
}

function copyDirectory (sourceDir, targetDir) {
  fs.cpSync(sourceDir, targetDir, {
    recursive: true,
    dereference: false,
    verbatimSymlinks: true
  });
}

function extractZip (zipPath, destinationDir) {
  if (process.platform === 'win32') {
    run('tar', ['-xf', zipPath, '-C', destinationDir], srcDir);
    return;
  }
  if (commandExists('unzip')) {
    run('unzip', ['-q', zipPath, '-d', destinationDir], srcDir);
    return;
  }
  if (commandExists('bsdtar')) {
    run('bsdtar', ['-xf', zipPath, '-C', destinationDir], srcDir);
    return;
  }
  throw new Error('Cannot extract dist.zip. Install unzip or bsdtar.');
}

function createZipFromDirectory (zipPath, sourceDir) {
  const entries = fs.readdirSync(sourceDir);
  if (entries.length === 0) {
    throw new Error(`Cannot create platform zip from empty directory: ${sourceDir}`);
  }

  if (process.platform === 'win32') {
    run('tar', ['-a', '-cf', zipPath, '-C', sourceDir, ...entries], srcDir);
    return;
  }
  if (commandExists('zip')) {
    run('zip', ['-q', '-r', '-y', zipPath, ...entries], sourceDir);
    return;
  }
  if (commandExists('bsdtar')) {
    run('bsdtar', ['-a', '-cf', zipPath, '-C', sourceDir, ...entries], srcDir);
    return;
  }
  throw new Error('Cannot create platform zip. Install zip or bsdtar.');
}

function listZipEntries (zipPath) {
  const commands = [];
  if (process.platform === 'win32') {
    commands.push(['tar', ['-tf', zipPath]]);
  }
  if (commandExists('unzip')) {
    commands.push(['unzip', ['-Z1', zipPath]]);
  }
  if (commandExists('bsdtar')) {
    commands.push(['bsdtar', ['-tf', zipPath]]);
  }
  if (commandExists('tar')) {
    commands.push(['tar', ['-tf', zipPath]]);
  }

  for (const [command, commandArgs] of commands) {
    const result = childProcess.spawnSync(command, commandArgs, {
      cwd: srcDir,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      maxBuffer: 128 * 1024 * 1024
    });
    if (result.status === 0) {
      return result.stdout.split(/\r?\n/).filter(Boolean);
    }
  }

  throw new Error(`Cannot list distribution zip entries: ${zipPath}`);
}

function resolveWidevineCdmSourceDir () {
  const sourceDir = path.resolve(widevineCdmDir);
  const nestedSourceDir = path.join(sourceDir, 'WidevineCdm');
  if (fs.existsSync(path.join(nestedSourceDir, 'manifest.json'))) {
    return nestedSourceDir;
  }
  return sourceDir;
}

function parseBoolean (value) {
  if (value === true) {
    return true;
  }
  if (!value) {
    return false;
  }
  return /^(1|true|yes|on)$/i.test(String(value));
}

function stripLeadingV (version) {
  return String(version).replace(/^v/, '');
}

function escapeRegExp (value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function sanitizePackageDirName (name, version) {
  return `${sanitizePackageName(name)}-${version}`;
}

function sanitizePackageName (name) {
  return name.replace(/^@/, '').replace(/\//g, '-');
}

function platformPackageNameFor (name) {
  return platformPackageNameForTarget(name, electronPlatform(), electronArch());
}

function platformPackageNameForTarget (name, platform, arch) {
  const suffix = `${platform}-${arch}`;
  if (name.startsWith('@')) {
    const [scope, packageBaseName] = name.split('/');
    if (!scope || !packageBaseName) {
      throw new Error(`Invalid scoped package name: ${name}`);
    }
    return `${scope}/${packageBaseName}-${suffix}`;
  }
  return `${name}-${suffix}`;
}

function platformKeyFromPackageName (name) {
  const match = name.match(/-([^-]+)-([^-]+)$/);
  if (!match) {
    throw new Error(`Cannot infer platform and arch from package name: ${name}`);
  }
  return `${match[1]}-${match[2]}`;
}

function electronPlatform () {
  const platform = process.env.npm_config_platform || os.platform();
  if (platform === 'darwin') {
    return 'darwin';
  }
  return platform;
}

function electronArch () {
  return process.env.npm_config_arch || os.arch();
}

function runNpm (commandArgs, cwd, options = {}) {
  const npm = npmCommand(commandArgs);
  return run(npm.command, npm.args, cwd, options);
}

function spawnNpmSync (commandArgs, cwd, options = {}) {
  const npm = npmCommand(commandArgs);
  return childProcess.spawnSync(npm.command, npm.args, {
    cwd,
    encoding: options.encoding || 'utf8',
    stdio: options.stdio || 'inherit',
    maxBuffer: options.maxBuffer || 128 * 1024 * 1024
  });
}

function npmCommand (commandArgs) {
  const npmCli = findNpmCli();
  if (npmCli) {
    return { command: process.execPath, args: [npmCli, ...commandArgs] };
  }
  return {
    command: process.platform === 'win32' ? 'npm.cmd' : 'npm',
    args: commandArgs
  };
}

function findNpmCli () {
  const nodeDir = path.dirname(process.execPath);
  const candidates = [
    path.join(nodeDir, 'node_modules', 'npm', 'bin', 'npm-cli.js'),
    path.join(nodeDir, '..', 'lib', 'node_modules', 'npm', 'bin', 'npm-cli.js'),
    path.join(nodeDir, '..', 'node_modules', 'npm', 'bin', 'npm-cli.js')
  ];
  return candidates.find(candidate => fs.existsSync(candidate));
}

function commandExists (command) {
  const pathDirs = (process.env.PATH || '').split(path.delimiter).filter(Boolean);
  const extensions = process.platform === 'win32'
    ? (process.env.PATHEXT || '.EXE;.CMD;.BAT;.COM').split(';')
    : [''];
  for (const dir of pathDirs) {
    for (const extension of extensions) {
      const candidate = path.join(dir, process.platform === 'win32' ? `${command}${extension}` : command);
      try {
        fs.accessSync(candidate, fs.constants.X_OK);
        return true;
      } catch {
        // Keep searching.
      }
    }
  }
  return false;
}

function widevinePlatformArch () {
  switch (electronPlatform()) {
    case 'darwin':
    case 'mas':
      return `mac_${electronArch()}`;
    case 'linux':
      return `linux_${electronArch()}`;
    case 'win32':
      return `win_${electronArch()}`;
    default:
      throw new Error(`Widevine CDM packaging is not supported on platform: ${electronPlatform()}`);
  }
}

function widevineLibraryName () {
  switch (electronPlatform()) {
    case 'darwin':
    case 'mas':
      return 'libwidevinecdm.dylib';
    case 'linux':
      return 'libwidevinecdm.so';
    case 'win32':
      return 'widevinecdm.dll';
    default:
      throw new Error(`Widevine CDM packaging is not supported on platform: ${electronPlatform()}`);
  }
}

function platformPath () {
  switch (electronPlatform()) {
    case 'mas':
    case 'darwin':
      return 'Electron.app/Contents/MacOS/Electron';
    case 'freebsd':
    case 'openbsd':
    case 'linux':
      return 'electron';
    case 'win32':
      return 'electron.exe';
    default:
      throw new Error(`Electron builds are not available on platform: ${electronPlatform()}`);
  }
}
