param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$ForwardArgs
)

$ErrorActionPreference = 'Stop'
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$python = $null
foreach ($candidate in @('python3', 'python', 'py')) {
  $resolved = Get-Command $candidate -ErrorAction SilentlyContinue
  if ($resolved) {
    $python = $resolved.Path
    break
  }
}
if (-not $python) {
  throw 'python3/python not found'
}

if ((Split-Path -Leaf $python).ToLowerInvariant() -eq 'py.exe' -or (Split-Path -Leaf $python).ToLowerInvariant() -eq 'py') {
  & $python -3 (Join-Path $scriptDir 'dope') @ForwardArgs
} else {
  & $python (Join-Path $scriptDir 'dope') @ForwardArgs
}
exit $LASTEXITCODE
