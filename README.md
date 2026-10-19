# WinClip

WinClip es una utilidad para Windows que copia varios textos ("snippets") al portapapeles de forma consecutiva, para que puedas reutilizarlos desde el historial de portapapeles de Windows (**Win + V**).

El proyecto se compone de dos aplicaciones:

| Aplicación | Script de entrada | Ejecutable | Función |
|---|---|---|---|
| **WinClipGenerator** | `winclip_generator_entry.ps1` | `WinClipGenerator.exe` | Crea el fichero de configuración con los snippets cifrados. |
| **WinClip** | `winclip_runtime_entry.ps1` | `WinClip.exe` | Pide la clave, descifra los snippets y los copia al portapapeles. |

> **Importante:** WinClip está pensado para textos **no sensibles** (plantillas, notas, códigos internos, etc.). No es un gestor de contraseñas. El historial de Windows (`Win+V`) conserva los textos copiados, así que no lo uses para credenciales reales.

---

## Activar el historial de portapapeles (multiportapapeles)

Por defecto, Windows solo guarda **un único texto** en el portapapeles: cada vez que copias algo, se sobrescribe lo anterior. Para poder conservar **varios textos** y elegirlos después, hay que activar el **historial de portapapeles** de Windows.

WinClip depende de ese historial: copia varios snippets seguidos y tú los recuperas después con **Win + V**. Si el historial no está activado, solo tendrás disponible el último texto copiado.

1. Pulsa **Win + V** en cualquier momento.
2. Si es la primera vez, aparecerá un aviso: pulsa **Activar**.
3. Si no aparece el aviso:
   - Abre **Configuración** (`Win + I`).
   - Ve a **Sistema → Portapapeles**.
   - Activa **Historial de portapapeles**.
4. Opcional recomendado:
   - Activa **Sincronizar entre dispositivos** si quieres compartir el historial.
   - Activa **Anclar** elementos frecuentes para que no se borren.

Para comprobarlo: copia un texto con **Ctrl + C**, pulsa **Win + V** y debería aparecer en la lista.

> Nota: el historial guarda un número limitado de elementos (los más recientes). Si copias muchos snippets seguidos, los más antiguos pueden desaparecer.

---

## Índice

- [Activar el historial de portapapeles (multiportapapeles)](#activar-el-historial-de-portapapeles-multiportapapeles)
- [Cómo funciona](#cómo-funciona)
- [Requisitos](#requisitos)
- [Estructura del proyecto](#estructura-del-proyecto)
- [Uso rápido](#uso-rápido)
- [Formato de configuración](#formato-de-configuración)
- [Compilar los ejecutables](#compilar-los-ejecutables)
- [Crear un acceso directo en la barra de tareas](#crear-un-acceso-directo-en-la-barra-de-tareas)
- [Solución de problemas](#solución-de-problemas)
- [Seguridad](#seguridad)
- [Publicar en GitHub](#publicar-en-github)

---

## Cómo funciona

1. **WinClipGenerator** te pide:
   - una clave,
   - una lista de textos separados por `|`.

   Con esos datos genera `clipboard_snippets.config.json`, guardando los textos **cifrados** (AES-256-CBC + HMAC-SHA256) y un `passwordHash` para validar la clave.

2. **WinClip** te pide la clave:
   - valida el `passwordHash`,
   - descifra los textos,
   - los copia uno a uno al portapapeles,
   - termina automáticamente.

3. Los textos quedan disponibles en el historial de **Win + V**.

> Win+V muestra primero lo más reciente. Para que el **primer texto de tu lista** aparezca **primero** en el historial, WinClip copia los snippets en orden inverso.

---

## Requisitos

- Windows 10 u 11.
- **Windows PowerShell 5.1** (incluido en Windows).
- Historial de portapapeles activado:
  - Pulsa **Win + V** y selecciona **Activar**.
- Para compilar los `.exe`: módulo [ps2exe](https://www.powershellgallery.com/packages/ps2exe).

---

## Estructura del proyecto

```text
WinClip/
├─ clipboard_snippets.ps1              # Núcleo: valida la clave, descifra y copia los snippets
├─ generate_winclip_encrypted_config.ps1 # Genera el JSON con los snippets cifrados
├─ winclip_generator_entry.ps1         # Entrada de WinClipGenerator (genera el .exe)
├─ winclip_runtime_entry.ps1           # Entrada de WinClip (genera el .exe)
├─ clipboard_snippets.config.json      # Configuración real (NO subir a GitHub)
├─ README.md
└─ WinClip.exe / WinClipGenerator.exe  # Ejecutables compilados (opcional)
```

### Responsabilidad de cada script

#### `generate_winclip_encrypted_config.ps1`

Generador interactivo. Solicita la clave y los snippets, y escribe el JSON cifrado.

Parámetros:

| Parámetro | Por defecto | Descripción |
|---|---|---|
| `-OutputPath` | `clipboard_snippets.config.json` | Ruta del JSON a generar. |
| `-Pbkdf2Iterations` | `150000` | Iteraciones de PBKDF2 para derivar claves. |
| `-CopyDelayMs` | `300` | Retardo entre copias (lo usa WinClip). |
| `-ClearAfterMs` | `0` | Tiempo antes de restaurar el portapapeles anterior (`0` = no restaurar). |

#### `winclip_generator_entry.ps1`

Entrada pensada para empaquetar con `ps2exe`:

- Espera 1 segundo al arrancar.
- Llama al generador.
- Muestra un cuadro de error si algo falla.
- Se cierra automáticamente al terminar.

#### `clipboard_snippets.ps1`

Núcleo de WinClip:

- Acepta configuración **en claro** (`portapapeles`) o **cifrada** (`portapapelesEnc`, `portapapelesSalt`, `portapapelesIv`, `portapapelesHmac`).
- Pide la clave **una sola vez**.
- Valida `passwordHash`.
- Descifra si es necesario.
- Divide por `|`, elimina elementos vacíos y copia cada snippet.
- Opcionalmente restaura el portapapeles anterior (`clearAfterMs > 0`), sin dejar una entrada en blanco.

#### `winclip_runtime_entry.ps1`

Entrada de WinClip para `ps2exe`:

- Espera 1 segundo al arrancar.
- Ejecuta `clipboard_snippets.ps1` con el `-ConfigPath` indicado.
- Muestra un cuadro de error si algo falla.
- Se cierra automáticamente al terminar.

> Los `.exe` **no son autocontenidos**: `WinClip.exe` necesita `clipboard_snippets.ps1` a su lado, y `WinClipGenerator.exe` necesita `generate_winclip_encrypted_config.ps1`. Si quieres un único `.exe` totalmente independiente, habría que incrustar esa lógica en el entrypoint.

---

## Uso rápido

### 1. Generar la configuración

```bat
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\generate_winclip_encrypted_config.ps1" -OutputPath ".\clipboard_snippets.config.json"
```

Te pedirá:

- **Clave**: la que usarás cada vez que ejecutes WinClip.
- **Snippets separados por `|`**: por ejemplo `Texto uno|Texto dos|Texto tres`.

Se generará `clipboard_snippets.config.json` con los textos cifrados.

### 2. Ejecutar WinClip

```bat
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\clipboard_snippets.ps1" -ConfigPath ".\clipboard_snippets.config.json"
```

Introduce la clave y los textos quedarán en el historial de **Win + V**.

---

## Formato de configuración

### Configuración cifrada (recomendada)

```json
{
  "passwordHash": "SHA256_EN_BASE64_DE_LA_CLAVE",
  "pbkdf2Iterations": 150000,
  "portapapelesEnc": "CIPHERTEXT_EN_BASE64",
  "portapapelesSalt": "SALT_EN_BASE64",
  "portapapelesIv": "IV_EN_BASE64",
  "portapapelesHmac": "HMAC_EN_BASE64",
  "copyDelayMs": 300,
  "clearAfterMs": 0
}
```

| Campo | Descripción |
|---|---|
| `passwordHash` | SHA-256 en Base64 de la clave. Se usa para validarla rápidamente. |
| `pbkdf2Iterations` | Iteraciones de PBKDF2. |
| `portapapelesEnc` | Textos cifrados (AES-256-CBC) en Base64. |
| `portapapelesSalt` | Salt de PBKDF2 en Base64. |
| `portapapelesIv` | IV de AES en Base64. |
| `portapapelesHmac` | HMAC-SHA256 de `IV || ciphertext` en Base64. |
| `copyDelayMs` | Retardo entre copias, en milisegundos. |
| `clearAfterMs` | Si es `> 0`, espera ese tiempo y restaura el portapapeles anterior. |

### Configuración en claro (solo para pruebas)

```json
{
  "passwordHash": "SHA256_EN_BASE64_DE_LA_CLAVE",
  "portapapeles": "Texto uno|Texto dos|Texto tres",
  "copyDelayMs": 300,
  "clearAfterMs": 0
}
```

En este modo los textos se ven al abrir el JSON. Úsalo solo para pruebas locales.

### Generar `passwordHash` manualmente

```powershell
$plain = 'miClave123'
$hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash(
  [System.Text.Encoding]::UTF8.GetBytes($plain)
)
[Convert]::ToBase64String($hash)
```

---

## Compilar los ejecutables

### 1. Instalar `ps2exe`

```powershell
Install-Module ps2exe -Scope CurrentUser -Force
```

Si PowerShell te pide confirmar la instalación del proveedor NuGet, acepta.

### 2. Compilar

Desde la carpeta del proyecto:

```bat
cd C:\ruta\a\WinClip
ps2exe .\winclip_generator_entry.ps1 .\WinClipGenerator.exe
ps2exe .\winclip_runtime_entry.ps1 .\WinClip.exe
```

Resultado:

- `WinClipGenerator.exe`
- `WinClip.exe`

### 3. Distribuir

Copia junto a los ejecutables:

- `clipboard_snippets.ps1`
- `generate_winclip_encrypted_config.ps1`

Sin esos scripts, los `.exe` no podrán ejecutar su lógica.

---

## Crear un acceso directo en la barra de tareas

1. Clic derecho en el escritorio → **Nuevo → Acceso directo**.
2. En **Ubicación del elemento**, escribe:

   ```bat
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ruta\a\WinClip\clipboard_snippets.ps1" -ConfigPath "C:\ruta\a\WinClip\clipboard_snippets.config.json"
   ```

   O, si usas el ejecutable:

   ```bat
   "C:\ruta\a\WinClip\WinClip.exe" -ConfigPath "C:\ruta\a\WinClip\clipboard_snippets.config.json"
   ```

3. Ponle nombre `WinClip`.
4. Clic derecho sobre el acceso directo → **Anclar a la barra de tareas**.

---

## Solución de problemas

### El `.exe` se abre y se cierra inmediatamente

- Comprueba que el JSON de configuración existe y tiene un nombre correcto.
- Ejecuta el `.exe` desde una consola para ver el mensaje de error.

### “Clave incorrecta”

La clave introducida no coincide con `passwordHash`. Genera de nuevo la configuración o calcula el hash correcto.

### “No se pudo descifrar la config”

- La clave no es la correcta, o
- El JSON se ha modificado/corrompido.

Vuelve a generar la configuración con `WinClipGenerator`.

### No aparecen todas las entradas en Win+V

Aumenta `copyDelayMs` en el JSON (por ejemplo, a `500` o `600`). Algunos equipos necesitan más tiempo entre copias para que Windows registre cada entrada.

### Aparece una entrada en blanco al final

Asegúrate de tener `"clearAfterMs": 0`. Si lo activas, WinClip restaura el portapapeles anterior solo si tenía contenido, para evitar entradas vacías.

### Windows bloquea la ejecución de scripts

Usa `-ExecutionPolicy Bypass` al invocar PowerShell, o ejecuta los `.exe` compilados.

---

## Seguridad

- **No uses WinClip para contraseñas reales.** Usa un gestor de contraseñas.
- El cifrado protege el JSON en reposo, pero la clave se introduce en memoria y los textos acaban en el portapapeles/historial de Windows.
- `passwordHash` es SHA-256 sin salt; sirve para validar la clave, no para proteger los textos.
- Los textos se cifran con AES-256-CBC y se autentican con HMAC-SHA256 (Encrypt-then-MAC).
- Las claves se derivan con PBKDF2 (`Rfc2898DeriveBytes`), 150 000 iteraciones por defecto.
- No subas `clipboard_snippets.config.json` a GitHub si contiene datos reales.

---

## Publicar en GitHub

Antes de subir el proyecto, crea un `.gitignore` con al menos:

```gitignore
# Configuración real
clipboard_snippets.config.json

# Ejecutables compilados (opcional)
*.exe

# Logs
*.log
```

Incluye en el repositorio únicamente:

- los scripts `.ps1`,
- el `README.md`,
- ejemplos de configuración sin datos reales.

Ejemplo de ejemplo de configuración cifrada vacía: `clipboard_snippets.config.encrypted.example.json`.

---

## Licencia

Añade aquí la licencia que quieras usar (MIT, Apache-2.0, etc.).
