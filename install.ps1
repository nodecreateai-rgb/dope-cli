$ErrorActionPreference = 'Stop'

$Repo = if ($env:DOPE_CLI_REPO) { $env:DOPE_CLI_REPO } else { 'nodecreateai-rgb/dope-cli' }
$Branch = if ($env:DOPE_CLI_BRANCH) { $env:DOPE_CLI_BRANCH } else { 'main' }
$ArchiveUrl = if ($env:DOPE_CLI_ARCHIVE_URL) { $env:DOPE_CLI_ARCHIVE_URL } else { "https://github.com/$Repo/archive/refs/heads/$Branch.zip" }
$InstallRoot = Join-Path $HOME '.dope\bundle'
$BinDir = Join-Path $HOME '.dope\bin'
$CmdLauncher = Join-Path $BinDir 'dope.cmd'
$PsLauncher = Join-Path $BinDir 'dope.ps1'

function Resolve-Python {
  foreach ($candidate in @('py', 'python3', 'python')) {
    $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Path }
  }
  throw 'python3/python not found'
}

function Ensure-UserPath([string]$PathToAdd) {
  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  $parts = @()
  if ($userPath) { $parts = $userPath -split ';' | Where-Object { $_ } }
  if ($parts -notcontains $PathToAdd) {
    $newPath = @($PathToAdd) + $parts
    [Environment]::SetEnvironmentVariable('Path', ($newPath -join ';'), 'User')
  }
}

$python = Resolve-Python
New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("dope-cli-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
$zipPath = Join-Path $tempDir 'dope-cli.zip'

try {
  Write-Host "Downloading dope-cli bundle from $ArchiveUrl ..."
  Invoke-WebRequest -UseBasicParsing -Uri $ArchiveUrl -OutFile $zipPath
  Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force
  $src = Get-ChildItem -Path $tempDir -Directory | Where-Object { $_.Name -like 'dope-cli-*' } | Select-Object -First 1
  if (-not $src) { throw 'failed to unpack dope-cli bundle' }

  if (Test-Path $InstallRoot) { Remove-Item -Recurse -Force $InstallRoot }
  New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
  Copy-Item -Recurse -Force -Path (Join-Path $src.FullName '*') -Destination $InstallRoot

  @"
@echo off
setlocal
py -3 "$InstallRoot\dope" %*
if errorlevel 9009 python "$InstallRoot\dope" %*
"@ | Set-Content -Path $CmdLauncher -Encoding ASCII

  @"
param(
  [Parameter(ValueFromRemainingArguments = `$true)]
  [string[]]`$ForwardArgs
)
`$python = '$python'
if ((Split-Path -Leaf `$python).ToLowerInvariant() -eq 'py.exe' -or (Split-Path -Leaf `$python).ToLowerInvariant() -eq 'py') {
  & `$python -3 "$InstallRoot\dope" @ForwardArgs
} else {
  & `$python "$InstallRoot\dope" @ForwardArgs
}
exit `$LASTEXITCODE
"@ | Set-Content -Path $PsLauncher -Encoding UTF8

  Ensure-UserPath $BinDir
  Write-Host "Installed dope to: $InstallRoot"
  Write-Host "Launchers: $CmdLauncher , $PsLauncher"
  Write-Host "Open a new terminal, then run: dope --help"
}
finally {
  if (Test-Path $tempDir) { Remove-Item -Recurse -Force $tempDir }
}
