<#
  Parque Solar Valle Aurora · Integra a la app las respuestas que mandan las áreas por correo

  Busca en la Bandeja de entrada de Outlook las respuestas a los recordatorios/avisos de incumplimiento,
  guarda el mensaje (.msg) y sus archivos adjuntos en OneDrive:
     OneDrive\Parque Solar Valle Aurora\Respuestas de áreas\<obligación>\<fecha - remitente>\
  y registra en la app el texto, los archivos y la liga a la carpeta.

  Cómo reconoce una respuesta:
    1. El asunto trae el código [VA-xxxxxxxx] que llevan los correos enviados, o
    2. el asunto es RE:/RV: y contiene entre comillas el título exacto de una obligación.

  Uso:
    powershell -NoProfile -ExecutionPolicy Bypass -File procesar-respuestas-outlook.ps1             # procesa
    powershell -NoProfile -ExecutionPolicy Bypass -File procesar-respuestas-outlook.ps1 -Simular    # solo muestra qué haría
    powershell -NoProfile -ExecutionPolicy Bypass -File procesar-respuestas-outlook.ps1 -Prueba     # crea una respuesta de prueba (sin enviar correos)
#>
param(
  [switch]$Simular,
  [switch]$Prueba,
  [int]$Dias = 30
)

$ErrorActionPreference = 'Stop'
$SupabaseUrl = 'https://dndeinbqjpvdakufkofy.supabase.co'
$Llave = 'sb_publishable_KD3lrsm4ioaa_AdRXUkW1A_-CAoRs6T'
$Proyecto = 'Parque Solar Valle Aurora'
$Carpeta = Join-Path $env:LOCALAPPDATA 'ValleAurora'
# OneDrive de la persona que ejecuta el script (carpeta sincronizada y su dirección web).
# La dirección web se toma de %LOCALAPPDATA%\ValleAurora\config.json → "onedrive_web",
# p. ej. https://<empresa>-my.sharepoint.com/personal/<usuario>/Documents
$OneDriveLocal = $env:OneDriveCommercial
if (-not $OneDriveLocal) { $OneDriveLocal = $env:OneDrive }
if (-not $OneDriveLocal) { throw 'No se encontró la carpeta de OneDrive sincronizada.' }
$OneDriveWeb = (Get-Content -Raw (Join-Path $Carpeta 'config.json') | ConvertFrom-Json).onedrive_web.TrimEnd('/')
$Base = Join-Path (Join-Path $OneDriveLocal $Proyecto) 'Respuestas de áreas'
$Bitacora = Join-Path $Carpeta 'respuestas.log'
New-Item -ItemType Directory -Force $Carpeta, $Base | Out-Null

function Log($texto) {
  $linea = '{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $texto
  Write-Output $linea
  Add-Content -Path $Bitacora -Value $linea -Encoding UTF8
}
function NombreSeguro([string]$s, [int]$max = 60) {
  $s = ($s -replace '[\\/:*?"<>|#%]', ' ' -replace '\s+', ' ').Trim().TrimEnd('.')
  if ($s.Length -gt $max) { $s = $s.Substring(0, $max).Trim() }
  return $s
}
function UrlWeb([string]$rutaLocal) {
  $rel = $rutaLocal.Substring($OneDriveLocal.Length).TrimStart('\')
  return $OneDriveWeb + '/' + (($rel -split '\\' | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/')
}
function TextoSinHistorial([string]$cuerpo) {
  # Corta el hilo citado ("De:", "From:", "-----Mensaje original-----", línea de subrayados)
  $lineas = $cuerpo -split "`r?`n"
  $salida = foreach ($l in $lineas) {
    if ($l -match '^\s*(De|From|Enviado el|Sent)\s*:' -or $l -match '^\s*-{3,}\s*(Mensaje original|Original Message)' -or $l -match '^\s*_{10,}') { break }
    $l
  }
  return (($salida -join "`n").Trim())
}
function Remitente($m) {
  try {
    if ($m.SenderEmailType -eq 'EX') { $u = $m.Sender.GetExchangeUser(); if ($u) { return "$($m.SenderName) <$($u.PrimarySmtpAddress)>" } }
  } catch {}
  return "$($m.SenderName) <$($m.SenderEmailAddress)>"
}

$cab = @{ apikey = $Llave; Authorization = "Bearer $Llave" }
$json = 'application/json; charset=utf-8'

try {
  # Catálogos para reconocer a qué obligación pertenece cada respuesta
  $obligaciones = @(Invoke-RestMethod -Uri "$SupabaseUrl/rest/v1/obligaciones?select=id,titulo" -Headers $cab | ForEach-Object { $_ })
  $correos = @(Invoke-RestMethod -Uri "$SupabaseUrl/rest/v1/correos?select=id,obligacion_id" -Headers $cab | ForEach-Object { $_ })
  $procesadosArchivo = Join-Path $Carpeta 'respuestas-procesadas.txt'
  $procesados = @{}
  if (Test-Path $procesadosArchivo) { Get-Content $procesadosArchivo | ForEach-Object { $procesados[$_] = $true } }
  $token = (Get-Content -Raw -Path (Join-Path $Carpeta 'token.txt')).Trim()

  $outlook = New-Object -ComObject Outlook.Application

  # Mensajes candidatos
  $candidatos = @()
  if ($Prueba) {
    $adj = Join-Path $env:TEMP 'Evidencia de prueba - Valle Aurora.txt'
    [IO.File]::WriteAllText($adj, "Archivo de PRUEBA generado por Angel para demostrar la integración de respuestas. Datos ficticios.", (New-Object Text.UTF8Encoding($true)))
    $m = $outlook.CreateItem(0)   # borrador en memoria: nunca se envía
    $m.Subject = 'RE: [PRUEBA] INCUMPLIMIENTO: "Entregar estados financieros trimestrales" venció el 27/10/2026'
    $m.Body = "Buen día:`r`n`r`n(PRUEBA) Adjunto los estados financieros del tercer trimestre. Se enviaron al banco el día de hoy; quedamos atentos al acuse.`r`n`r`nSaludos,`r`nRicardo Peña (ficticio) – Finanzas`r`n`r`nDe: Consuelo Freyre`r`nEnviado el: viernes`r`nAsunto: INCUMPLIMIENTO..."
    $m.Attachments.Add($adj) | Out-Null
    $candidatos += [pscustomobject]@{ Item = $m; Id = 'PRUEBA-' + (Get-Date -Format 'yyyyMMddHHmmss'); Remitente = 'Ricardo Peña (ficticio, PRUEBA) <finanzas@aurora-energia.example>'; Fecha = Get-Date }
  } else {
    $inbox = $outlook.Session.GetDefaultFolder(6)
    $desde = (Get-Date).AddDays(-$Dias).ToString('g')
    $items = $inbox.Items.Restrict("[ReceivedTime] >= '$desde'")
    foreach ($m in $items) {
      if ($m.Class -ne 43) { continue }   # solo correos
      $s = [string]$m.Subject
      if ($s -notmatch '\[VA-[0-9a-f]{8}\]' -and $s -notmatch '^\s*(RE|Re|RV|Rv|FW|Fw|RES)\s*:') { continue }
      $id = $null
      try { $id = $m.PropertyAccessor.GetProperty('http://schemas.microsoft.com/mapi/proptag/0x1035001F') } catch {}
      if (-not $id) { $id = $m.EntryID }
      if (-not $id -or $procesados.ContainsKey([string]$id)) { continue }
      $candidatos += [pscustomobject]@{ Item = $m; Id = $id; Remitente = (Remitente $m); Fecha = $m.ReceivedTime }
    }
  }

  $nuevas = 0
  foreach ($c in $candidatos) {
    $m = $c.Item
    $asunto = [string]$m.Subject

    # 1) Código de referencia → correo → obligación
    $obligacionId = $null; $correoId = $null
    if ($asunto -match '\[VA-([0-9a-f]{8})\]') {
      $pref = $Matches[1]
      $co = $correos | Where-Object { $_.id.StartsWith($pref) } | Select-Object -First 1
      if ($co) { $correoId = $co.id; $obligacionId = $co.obligacion_id }
    }
    # 2) Título de la obligación entre comillas
    if (-not $obligacionId) {
      foreach ($t in [regex]::Matches($asunto, '"([^"]+)"')) {
        $ob = $obligaciones | Where-Object { $_.titulo -eq $t.Groups[1].Value } | Select-Object -First 1
        if ($ob) { $obligacionId = $ob.id; break }
      }
    }
    if (-not $obligacionId) { continue }   # no es respuesta a un aviso del proyecto

    $titulo = ($obligaciones | Where-Object { $_.id -eq $obligacionId }).titulo
    $remNombre = ($c.Remitente -replace '\s*<.*$', '')
    $destino = Join-Path (Join-Path $Base (NombreSeguro $titulo)) (NombreSeguro ('{0:yyyy-MM-dd HHmm} - {1}' -f $c.Fecha, $remNombre) 80)

    if ($Simular) { Log "SIMULACIÓN · $titulo · $($c.Remitente) · $($m.Attachments.Count) adjunto(s) → $destino"; continue }

    New-Item -ItemType Directory -Force $destino | Out-Null
    $texto = TextoSinHistorial ([string]$m.Body)
    [IO.File]::WriteAllText((Join-Path $destino 'Mensaje.txt'),
      "De: $($c.Remitente)`r`nFecha: $($c.Fecha)`r`nAsunto: $asunto`r`n`r`n$texto", (New-Object Text.UTF8Encoding($true)))
    if (-not $Prueba) { $m.SaveAs((Join-Path $destino 'Correo original.msg'), 3) }

    $archivos = @()
    foreach ($a in $m.Attachments) {
      # Omite imágenes incrustadas en la firma
      $cid = $null; try { $cid = $a.PropertyAccessor.GetProperty('http://schemas.microsoft.com/mapi/proptag/0x3712001F') } catch {}
      if ($cid -and $a.FileName -match '\.(png|jpe?g|gif)$' -and $a.Size -lt 200KB) { continue }
      $nombre = NombreSeguro $a.FileName 120
      $ruta = Join-Path $destino $nombre
      $a.SaveAsFile($ruta)
      $archivos += @{ nombre = $nombre; url = (UrlWeb $ruta); tamano = [int]$a.Size }
    }

    $cuerpo = @{
      p_token = $token; p_obligacion = $obligacionId; p_correo = $correoId; p_mensaje_id = $c.Id
      p_remitente = $c.Remitente; p_asunto = $asunto; p_texto = $texto
      p_recibido = ([datetime]$c.Fecha).ToUniversalTime().ToString('o')
      p_archivos = @($archivos); p_carpeta_url = (UrlWeb $destino)
    } | ConvertTo-Json -Depth 5
    $r = Invoke-RestMethod -Method Post -Uri "$SupabaseUrl/rest/v1/rpc/registrar_respuesta" -Headers $cab -ContentType $json -Body ([Text.Encoding]::UTF8.GetBytes($cuerpo))
    if (-not $Prueba) { Add-Content -Path $procesadosArchivo -Value $c.Id -Encoding UTF8 }
    $nuevas++
    Log "Respuesta integrada · $titulo · $($c.Remitente) · $($archivos.Count) archivo(s) · $destino"
  }
  if ($Prueba) { $candidatos | ForEach-Object { $_.Item.Delete() } }
  if ($nuevas -eq 0 -and -not $Simular) { Log 'Sin respuestas nuevas.' }
} catch {
  Log "ERROR: $($_.Exception.Message)"
  exit 1
}
