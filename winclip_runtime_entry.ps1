param(
  [string]$ConfigPath,
  [bool]$PauseOnExit = $false,
  [int]$PauseSeconds = 0
)

Start-Sleep -Seconds 1

$exeDir = Split-Path -Parent ([System.Reflection.Assembly]::GetEntryAssembly().Location)
if (-not $ConfigPath) {
  $ConfigPath = Join-Path -Path $exeDir -ChildPath 'clipboard_snippets.config.json'
}

function Show-ErrorBox([string]$message) {
  try {
    Add-Type -AssemblyName System.Windows.Forms | Out-Null
    [System.Windows.Forms.MessageBox]::Show($message, 'WinClip - Error') | Out-Null
  } catch {
    # Si no se puede mostrar UI, no hacemos nada.
  }
}

try {
  $runtime = Join-Path -Path $exeDir -ChildPath 'clipboard_snippets.ps1'
  if (-not (Test-Path -LiteralPath $runtime)) {
    throw "No existe el runtime: $runtime"
  }

  & $runtime -ConfigPath $ConfigPath
}
catch {
  Show-ErrorBox ("Error: $($_.Exception.Message)")
  throw
}
finally {
  if ($PauseOnExit) {
    Start-Sleep -Seconds $PauseSeconds
  }
}
