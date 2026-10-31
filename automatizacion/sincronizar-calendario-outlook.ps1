<#
  Parque Solar Valle Aurora · Sincroniza las obligaciones con el calendario de Outlook

  - Crea un evento de día completo por cada obligación con fecha (categoría "Valle Aurora").
  - Si la fecha cambia (p. ej., se registró el cumplimiento y se recorrió al siguiente periodo), actualiza el evento.
  - Si la obligación ya no tiene fecha pendiente, elimina su evento.
  - Solo toca eventos creados por este script (marcados con la propiedad ValleAuroraId).
  - Los eventos se marcan como "Disponible" para no bloquear la agenda.

  Uso:
    powershell -NoProfile -ExecutionPolicy Bypass -File sincronizar-calendario-outlook.ps1             # sincroniza
    powershell -NoProfile -ExecutionPolicy Bypass -File sincronizar-calendario-outlook.ps1 -Simular    # solo muestra qué haría
#>
param(
  [switch]$Simular,
  [int]$AvisoDias = 7,
  [string]$UrlApp = 'https://chelitofreyre711-a11y.github.io/hackathon-Claude-Lawgic/'
)

$ErrorActionPreference = 'Stop'
$SupabaseUrl = 'https://dndeinbqjpvdakufkofy.supabase.co'
$Llave = 'sb_publishable_KD3lrsm4ioaa_AdRXUkW1A_-CAoRs6T'
$Categoria = 'Valle Aurora'
$Prefijo = '⚖️ [Valle Aurora]'
$Carpeta = Join-Path $env:LOCALAPPDATA 'ValleAurora'
$Bitacora = Join-Path $Carpeta 'calendario.log'
New-Item -ItemType Directory -Force $Carpeta | Out-Null

function Log($texto) {
  $linea = '{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $texto
  Write-Output $linea
  Add-Content -Path $Bitacora -Value $linea -Encoding UTF8
}

try {
  $cab = @{ apikey = $Llave; Authorization = "Bearer $Llave" }
  $campos = 'id,titulo,explicacion_simple,consecuencia,clausula,contrato_nombre,contraparte,proyecto,area_nombre,area_titular,periodicidad,proxima_fecha,estado,prioridad'
  $obs = @(Invoke-RestMethod -Uri "$SupabaseUrl/rest/v1/v_obligaciones?select=$campos" -Headers $cab | ForEach-Object { $_ })
  $conFecha = @{}
  foreach ($o in $obs) { if ($o.proxima_fecha) { $conFecha[$o.id] = $o } }

  $outlook = New-Object -ComObject Outlook.Application
  $ns = $outlook.Session
  $cal = $ns.GetDefaultFolder(9)

  # Categoría con color (verde azulado) para identificar los eventos
  if (-not $Simular -and -not ($ns.Categories | Where-Object { $_.Name -eq $Categoria })) {
    $ns.Categories.Add($Categoria, 9) | Out-Null   # 9 = olCategoryColorDarkTeal
  }

  # Eventos existentes creados por este script
  $existentes = @{}
  $items = $cal.Items.Restrict("@SQL=""urn:schemas-microsoft-com:office:office#Keywords"" LIKE '%$Categoria%'")
  foreach ($e in $items) {
    $p = $e.UserProperties.Find('ValleAuroraId')
    if ($p) { $existentes[[string]$p.Value] = $e }
  }

  $creados = 0; $actualizados = 0; $eliminados = 0; $sinCambio = 0
  foreach ($o in $conFecha.Values) {
    $inicio = [datetime]::ParseExact($o.proxima_fecha, 'yyyy-MM-dd', $null)
    $alerta = if ($o.estado -eq 'Vencida') { '🔴 ATRASADA · ' } else { '' }
    $asunto = "$Prefijo $alerta$($o.titulo)"
    $cuerpo = @"
DEMO HACKATHON · DATOS FICTICIOS

Qué hay que hacer: $($o.explicacion_simple)
Si no se cumple: $($o.consecuencia)

Contrato: $($o.contrato_nombre) – $($o.proyecto) ($($o.contraparte))
Dónde lo dice: $($o.clausula)
Área responsable: $($o.area_nombre)$(if ($o.area_titular) { " ($($o.area_titular))" })
Periodicidad: $($o.periodicidad) · Prioridad: $($o.prioridad)

Cuando se cumpla, regístralo en la app con "Ya se cumplió"; el evento se moverá solo al siguiente periodo.
$UrlApp
"@
    $e = $existentes[$o.id]
    if ($e) {
      $existentes.Remove($o.id)
      if ($e.Start.Date -eq $inicio.Date -and $e.Subject -eq $asunto) { $sinCambio++; continue }
      if ($Simular) { Log "SIMULACIÓN · actualizar · $($inicio.ToString('dd/MM/yyyy')) · $asunto"; $actualizados++; continue }
      $e.Start = $inicio; $e.End = $inicio.AddDays(1); $e.Subject = $asunto; $e.Body = $cuerpo; $e.Save()
      $actualizados++; Log "Actualizado · $($inicio.ToString('dd/MM/yyyy')) · $asunto"
    } else {
      if ($Simular) { Log "SIMULACIÓN · crear · $($inicio.ToString('dd/MM/yyyy')) · $asunto"; $creados++; continue }
      $e = $outlook.CreateItem(1)           # cita
      $e.AllDayEvent = $true
      $e.Start = $inicio; $e.End = $inicio.AddDays(1)
      $e.Subject = $asunto
      $e.Body = $cuerpo
      $e.Categories = $Categoria
      $e.BusyStatus = 0                      # Disponible: no bloquea la agenda
      $e.ReminderSet = $true
      $e.ReminderMinutesBeforeStart = $AvisoDias * 24 * 60
      $e.Importance = if ($o.prioridad -eq 'Alta') { 2 } else { 1 }
      $prop = $e.UserProperties.Add('ValleAuroraId', 1)   # 1 = olText
      $prop.Value = $o.id
      $e.Save()
      $creados++; Log "Creado · $($inicio.ToString('dd/MM/yyyy')) · $asunto"
    }
  }

  # Obligaciones que ya no tienen fecha pendiente → eliminar su evento
  foreach ($k in @($existentes.Keys)) {
    $e = $existentes[$k]
    if ($Simular) { Log "SIMULACIÓN · eliminar · $($e.Subject)"; $eliminados++; continue }
    $asunto = $e.Subject; $e.Delete(); $eliminados++; Log "Eliminado · $asunto"
  }

  Log "Resumen: $creados creados, $actualizados actualizados, $eliminados eliminados, $sinCambio sin cambio."
} catch {
  Log "ERROR: $($_.Exception.Message)"
  exit 1
}
