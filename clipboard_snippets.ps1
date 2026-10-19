# Copia “snippets” (texto NO sensible) al portapapeles, para que aparezcan en el historial de portapapeles (Win+V).
# Usa UNA clave para autorizar la operación.

param(
  [string]$ConfigPath = (Join-Path -Path $PSScriptRoot -ChildPath 'clipboard_snippets.config.json')
)

$ErrorActionPreference = 'Stop'

function Get-PlainTextFromSecureString([System.Security.SecureString]$secure) {
  $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try {
    return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
  } finally {
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
  }
}

function Sha256Base64([string]$s) {
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($s)
  $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
  return [Convert]::ToBase64String($hash)
}

function BytesEqual([byte[]]$a, [byte[]]$b) {
  if ($null -eq $a -or $null -eq $b) { return $false }
  if ($a.Length -ne $b.Length) { return $false }
  $diff = 0
  for ($i = 0; $i -lt $a.Length; $i++) {
    $diff = $diff -bor ($a[$i] -bxor $b[$i])
  }
  return ($diff -eq 0)
}

function DeriveEncAndMacKeys([string]$password, [byte[]]$saltBytes, [int]$iterations) {
  $pwdBytes = [System.Text.Encoding]::UTF8.GetBytes($password)
  $kdf = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($pwdBytes, $saltBytes, $iterations)
  $keyMaterial = $kdf.GetBytes(64) # 32 enc + 32 mac
  $encKey = [byte[]]($keyMaterial[0..31])
  $macKey = [byte[]]($keyMaterial[32..63])
  return @([byte[]]$encKey, [byte[]]$macKey)
}

function DecryptPortapapeles([string]$password, $config) {
  $iterations = [int]$config.pbkdf2Iterations
  $saltBytes = [Convert]::FromBase64String($config.portapapelesSalt)
  $ivBytes = [Convert]::FromBase64String($config.portapapelesIv)
  $cipherBytes = [Convert]::FromBase64String($config.portapapelesEnc)
  $hmacBytes = [Convert]::FromBase64String($config.portapapelesHmac)

  $keys = DeriveEncAndMacKeys -password $password -saltBytes $saltBytes -iterations $iterations
  $encKey = $keys[0]
  $macKey = $keys[1]

  # HMAC sobre iv || ciphertext (integridad)
  $dataToMac = New-Object byte[] ($ivBytes.Length + $cipherBytes.Length)
  [Array]::Copy($ivBytes, 0, $dataToMac, 0, $ivBytes.Length)
  [Array]::Copy($cipherBytes, 0, $dataToMac, $ivBytes.Length, $cipherBytes.Length)

  $hmac = New-Object System.Security.Cryptography.HMACSHA256
  $hmac.Key = [byte[]]$macKey
  $computed = $hmac.ComputeHash($dataToMac)
  if (-not (BytesEqual -a $computed -b $hmacBytes)) {
    throw 'Config cifrada inválida o clave incorrecta.'
  }

  $aes = New-Object System.Security.Cryptography.AesManaged
  $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
  $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
  $aes.KeySize = 256
  $aes.BlockSize = 128
  $aes.Key = $encKey
  $aes.IV = $ivBytes

  $decryptor = $aes.CreateDecryptor()
  $plainBytes = $decryptor.TransformFinalBlock($cipherBytes, 0, $cipherBytes.Length)
  return [System.Text.Encoding]::UTF8.GetString($plainBytes)
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
  throw "No existe config: $ConfigPath"
}

$configRaw = Get-Content -LiteralPath $ConfigPath -Raw
$config = $configRaw | ConvertFrom-Json

if (-not $config.passwordHash) {
  throw "La config debe incluir 'passwordHash' (SHA-256 en Base64)."
}
if (-not $config.portapapeles) {
  # Modo cifrado: exige los campos de portapapeles cifrado.
  if (-not $config.portapapelesEnc) {
    throw "La config debe incluir 'portapapeles' (en claro) o 'portapapelesEnc/portapapelesSalt/portapapelesIv/portapapelesHmac' (cifrado)."
  }
  if (-not $config.portapapelesSalt -or -not $config.portapapelesIv -or -not $config.portapapelesHmac) {
    throw "La config cifrada debe incluir portapapelesSalt/portapapelesIv/portapapelesHmac."
  }
  if (-not $config.pbkdf2Iterations) {
    throw "La config cifrada debe incluir pbkdf2Iterations."
  }
}

$copyDelayMs = if ($config.copyDelayMs -ne $null) { [int]$config.copyDelayMs } else { 300 }
$clearAfterMs = if ($config.clearAfterMs -ne $null) { [int]$config.clearAfterMs } else { 0 }

try {
  # Guardamos el portapapeles original para restaurarlo al final (evita dejar una entrada en blanco).
  $originalClipboard = $null
  try {
    $originalClipboard = Get-Clipboard -Raw -ErrorAction SilentlyContinue
  } catch {
    $originalClipboard = $null
  }

  $secure = Read-Host -Prompt 'Clave' -AsSecureString
  $plain = Get-PlainTextFromSecureString $secure

  $enteredHash = Sha256Base64 $plain
  $enteredPlainPassword = $plain
  if ($plain) { $plain = $null } # reduce el tiempo que vive en memoria

  if ($enteredHash -ne $config.passwordHash) {
    throw 'Clave incorrecta.'
  }
} catch {
  Write-Error $_.Exception.Message
  exit 1
}

$decrypted = $null
if ($config.portapapeles) {
  $decrypted = $config.portapapeles
} else {
  try {
    $decrypted = DecryptPortapapeles -password $enteredPlainPassword -config $config
  } catch {
    Write-Error 'No se pudo descifrar la config.'
    exit 1
  }
}

if ($enteredPlainPassword) { $enteredPlainPassword = $null }

$items = @(
  ($decrypted -split '\|') |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -ne '' }
)

if ($items.Count -eq 0) {
  throw "portapapeles no contiene elementos después de separar por '|'."
}

# Win+V suele mostrar primero lo más reciente. Para que el orden del config
# coincida con el orden de visualización, copiamos en orden inverso.
$itemsToCopy = @($items)
[Array]::Reverse($itemsToCopy)
foreach ($item in $itemsToCopy) {
  Set-Clipboard -Value $item
  Start-Sleep -Milliseconds $copyDelayMs
}

if ($clearAfterMs -gt 0) {
  Start-Sleep -Milliseconds $clearAfterMs
  # Restaurar el portapapeles original si tenía contenido; si estaba vacío, no hacemos nada.
  if ($originalClipboard -and $originalClipboard -ne '') {
    Set-Clipboard -Value $originalClipboard
  }
}

exit 0
