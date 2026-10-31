<#
  Parque Solar Valle Aurora · Envío de recordatorios desde Outlook de escritorio

  1. Pide a la app que genere los correos del día (recordatorios a 45 días e incumplimientos).
  2. Lee la bandeja de correos pendientes.
  3. Los envía con el Outlook de escritorio de la sesión actual (sin contraseñas).
  4. Los marca como enviados en la app con la llave privada guardada en
     %LOCALAPPDATA%\ValleAurora\token.txt (nunca se sube al repositorio).

  Uso:
    powershell -NoProfile -ExecutionPolicy Bypass -File enviar-correos-outlook.ps1            # envía
    powershell -NoProfile -ExecutionPolicy Bypass -File enviar-correos-outlook.ps1 -Simular   # solo muestra qué enviaría
#>
param(
  [switch]$Simular,
  # Modo prueba: mientras las áreas tengan correos ficticios (.example), todo se redirige aquí.
  # Si no se indica, se toma de %LOCALAPPDATA%\ValleAurora\config.json → "destino_pruebas".
  [string]$DestinoPruebas,
  [int]$Maximo = 25
)

$ErrorActionPreference = 'Stop'
$SupabaseUrl = 'https://dndeinbqjpvdakufkofy.supabase.co'
$Llave = 'sb_publishable_KD3lrsm4ioaa_AdRXUkW1A_-CAoRs6T'
$Carpeta = Join-Path $env:LOCALAPPDATA 'ValleAurora'
$ConfigLocal = Join-Path $Carpeta 'config.json'
if (-not $DestinoPruebas -and (Test-Path $ConfigLocal)) { $DestinoPruebas = (Get-Content -Raw $ConfigLocal | ConvertFrom-Json).destino_pruebas }
$Bitacora = Join-Path $Carpeta 'envios.log'
New-Item -ItemType Directory -Force $Carpeta | Out-Null

function Log($texto) {
  $linea = '{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $texto
  Write-Output $linea
  Add-Content -Path $Bitacora -Value $linea -Encoding UTF8
}
function Html($texto) {
  [System.Net.WebUtility]::HtmlEncode($texto) -replace "`r?`n", '<br>'
}

$cab = @{ apikey = $Llave; Authorization = "Bearer $Llave" }
$json = 'application/json; charset=utf-8'

try {
  # 1. Generar correos del día
  $gen = Invoke-RestMethod -Method Post -Uri "$SupabaseUrl/functions/v1/enviar-correos" -Headers $cab -ContentType $json -Body '{}'
  Log "Bandeja actualizada: $($gen.nuevos) nuevos, $($gen.pendientes) pendientes."

  # 2. Leer pendientes
  $url = "$SupabaseUrl/rest/v1/correos?estado=eq.pendiente&select=id,tipo,para,cc,asunto,cuerpo&order=tipo.asc,fecha_objetivo.asc&limit=$Maximo"
  # PowerShell 5.1 devuelve el arreglo JSON como un solo objeto; el pipeline lo desenrolla
  $pendientes = @(Invoke-RestMethod -Method Get -Uri $url -Headers $cab | ForEach-Object { $_ })
  if ($pendientes.Count -eq 0) { Log 'No hay correos pendientes.'; return }

  if (-not $Simular) {
    $token = (Get-Content -Raw -Path (Join-Path $Carpeta 'token.txt')).Trim()
    $outlook = New-Object -ComObject Outlook.Application
  }

  $enviados = @()
  foreach ($c in $pendientes) {
    $destinatarios = @($c.para) + @($c.cc | Where-Object { $_ })
    $ficticio = @($destinatarios | Where-Object { $_ -match '\.example$' }).Count -gt 0
    $redirigir = $DestinoPruebas -and $ficticio

    $para = if ($redirigir) { $DestinoPruebas } else { $c.para }
    $cc = if ($redirigir) { '' } else { $c.cc }
    # Código de referencia: permite reconocer las respuestas y ligarlas a la obligación
    $ref = "[VA-$($c.id.Substring(0, 8))]"
    $asunto = if ($redirigir) { "[PRUEBA → $($c.para)$(if ($c.cc) { ' · CC ' + $c.cc })] $($c.asunto) $ref" } else { "$($c.asunto) $ref" }
    $aviso = if ($redirigir) {
      '<p style="background:#fff4e0;border-left:4px solid #d97706;padding:8px 12px"><b>&#9888; CORREO DE PRUEBA &ndash; DATOS FICTICIOS.</b> ' +
      'Demostraci&oacute;n de la app &quot;Parque Solar Valle Aurora &middot; Sem&aacute;foro de cumplimiento&quot;. ' +
      'No corresponde a ning&uacute;n proyecto ni obligaci&oacute;n real. Destinatario original: ' + (Html $c.para) +
      $(if ($c.cc) { ' (CC ' + (Html $c.cc) + ')' } else { '' }) + '.</p><hr>'
    } else { '' }

    if ($Simular) { Log "SIMULACIÓN → $para | $asunto"; continue }

    $m = $outlook.CreateItem(0)
    $m.To = $para
    if ($cc) { $m.CC = $cc }
    $m.Subject = $asunto
    $pie = '<p style="color:#5a6680;font-size:12px">Para enviar información o evidencia sobre esta obligación, <b>responda a este correo</b> (con archivos adjuntos si aplica). Su respuesta se integra automáticamente al expediente del proyecto.</p>'
    $m.HTMLBody = '<div style="font-family:Segoe UI,Arial,sans-serif;font-size:14px;color:#1D2945">' + $aviso + '<p>' + (Html $c.cuerpo) + '</p>' + $pie + '</div>'
    $m.Send()
    $enviados += $c.id
    Log "Enviado → $para | $asunto"
  }

  # 4. Marcar como enviados en la app
  if ($enviados.Count -gt 0) {
    $cuerpo = @{ p_ids = $enviados; p_token = $token; p_nota = $(if ($DestinoPruebas) { 'Enviado desde Outlook de escritorio (modo prueba, redirigido)' } else { 'Enviado desde Outlook de escritorio' }) } | ConvertTo-Json
    $n = Invoke-RestMethod -Method Post -Uri "$SupabaseUrl/rest/v1/rpc/marcar_correos_enviados" -Headers $cab -ContentType $json -Body ([Text.Encoding]::UTF8.GetBytes($cuerpo))
    Log "Marcados como enviados en la app: $n"
  }
} catch {
  Log "ERROR: $($_.Exception.Message)"
  exit 1
}
