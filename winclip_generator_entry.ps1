param(
  [string]$OutputPath,
  [int]$Pbkdf2Iterations = 150000,
  [int]$CopyDelayMs = 300,
  [int]$ClearAfterMs = 0,
  [bool]$PauseOnExit = $false,
  [int]$PauseSeconds = 0
)

Start-Sleep -Seconds 1

$exeDir = Split-Path -Parent ([System.Reflection.Assembly]::GetEntryAssembly().Location)
if (-not $OutputPath) {
  $OutputPath = Join-Path -Path $exeDir -ChildPath 'clipboard_snippets.config.json'
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
  $generator = Join-Path -Path $exeDir -ChildPath 'generate_winclip_encrypted_config.ps1'
  if (-not (Test-Path -LiteralPath $generator)) {
    throw "No existe el generador: $generator"
  }

  & $generator -OutputPath $OutputPath -Pbkdf2Iterations $Pbkdf2Iterations -CopyDelayMs $CopyDelayMs -ClearAfterMs $ClearAfterMs
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
