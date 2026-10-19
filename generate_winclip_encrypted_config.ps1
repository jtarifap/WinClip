param(
  [string]$OutputPath = (Join-Path -Path $PSScriptRoot -ChildPath 'clipboard_snippets.config.json'),
  [int]$Pbkdf2Iterations = 150000,
  [int]$CopyDelayMs = 300,
  [int]$ClearAfterMs = 0
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

function RandomBytes([int]$len) {
  $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
  $bytes = New-Object byte[] $len
  $rng.GetBytes($bytes)
  return $bytes
}

Write-Host 'Genera un clipboard_snippets.config.json con portapapeles cifrado.'

$secure = Read-Host -Prompt 'Clave' -AsSecureString
$password = Get-PlainTextFromSecureString $secure

$portapapelesPlain = Read-Host -Prompt "Snippets separados por | (ej: Texto1|Texto2|Texto3)"

try {
  $saltBytes = RandomBytes 16
  $ivBytes = RandomBytes 16

  $keys = DeriveEncAndMacKeys -password $password -saltBytes $saltBytes -iterations $Pbkdf2Iterations
  $encKey = $keys[0]
  $macKey = $keys[1]

  $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($portapapelesPlain)

  $aes = New-Object System.Security.Cryptography.AesManaged
  $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
  $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
  $aes.KeySize = 256
  $aes.BlockSize = 128
  $aes.Key = $encKey
  $aes.IV = $ivBytes

  $encryptor = $aes.CreateEncryptor()
  $cipherBytes = $encryptor.TransformFinalBlock($plainBytes, 0, $plainBytes.Length)

  # HMAC sobre iv || ciphertext
  $dataToMac = New-Object byte[] ($ivBytes.Length + $cipherBytes.Length)
  [Array]::Copy($ivBytes, 0, $dataToMac, 0, $ivBytes.Length)
  [Array]::Copy($cipherBytes, 0, $dataToMac, $ivBytes.Length, $cipherBytes.Length)

  $hmac = New-Object System.Security.Cryptography.HMACSHA256
  $hmac.Key = [byte[]]$macKey
  $hmacBytes = $hmac.ComputeHash($dataToMac)

  $passwordHash = Sha256Base64 $password

  $config = [pscustomobject]@{
    passwordHash = $passwordHash
    pbkdf2Iterations = $Pbkdf2Iterations
    portapapelesEnc = [Convert]::ToBase64String($cipherBytes)
    portapapelesSalt = [Convert]::ToBase64String($saltBytes)
    portapapelesIv = [Convert]::ToBase64String($ivBytes)
    portapapelesHmac = [Convert]::ToBase64String($hmacBytes)
    copyDelayMs = $CopyDelayMs
    clearAfterMs = $ClearAfterMs
  }

  $configJson = $config | ConvertTo-Json -Depth 10
  Set-Content -LiteralPath $OutputPath -Value $configJson -Encoding UTF8
  Write-Host "OK. Config cifrada generada en: $OutputPath"
}
finally {
  $password = $null
}
