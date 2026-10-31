# Parque Solar Valle Aurora · Semáforo de cumplimiento

App web del proyecto (ficticio) **Parque Solar Valle Aurora** que muestra **de un vistazo** si se están cumpliendo las obligaciones de un **contrato de crédito** y de su **fideicomiso de garantía y fuente de pago**. Avisa **antes** de que algo venza.

Está pensada para cualquier persona del equipo, no solo para abogados. Cada obligación se explica en palabras simples, dice qué pasa si no se cumple y quién es responsable.

> ⚠️ Esta versión usa **datos ficticios** de demostración: proyecto **Parque Solar Valle Aurora**, acreditada **Aurora Energía Renovable, S.A.P.I. de C.V.**, acreditante **Banco de Fomento Horizonte, S.N.C.**, fiduciario **Fiduciaria Puente Alto, S.A.** y obligado solidario **Grupo Inversor Cumbre Verde, S.A. de C.V.**
>
> La paleta toma los colores del logo de CEM: azul marino `#1D2945`, azul petróleo `#00A0AF`, turquesa `#2AD2C5` y verde lima `#93D50A`.

## Qué hace

| Función | Cómo se ve |
|---|---|
| **Semáforo** | 🔴 Atrasada · 🟠 Vence pronto · 🟢 Al día · 🔵 Vigilar siempre · ⚪ Cumplida |
| **Resumen en lenguaje claro** | "Hay 2 obligaciones atrasadas y 6 que vencen pronto" y un porcentaje de obligaciones al corriente |
| **Próximos 60 días** | Línea de tiempo con las fechas en orden |
| **Detalle de cada obligación** | Qué hay que hacer, qué pasa si no se cumple, cláusula, responsable e historial |
| **Registrar cumplimiento** | Un botón: "Ya se cumplió". Se anota qué se hizo y la evidencia, y la próxima fecha se recorre sola (mensual, trimestral, semestral o anual) |
| **Alertas automáticas** | Cada día a las 8:00 (Ciudad de México) la base de datos genera avisos 30, 15, 7 y 1 día antes de cada fecha, y un aviso si la fecha ya pasó |
| **Campana de avisos** | Muestra los avisos sin leer, los más urgentes primero |
| **Avisos en el equipo** | Notificaciones del navegador al abrir la app |
| **Botones de contrato** | "Contrato de crédito" y "Fideicomiso" abren el detalle: partes, objeto, monto, plazo, garantías, ley aplicable y sus obligaciones |
| **Recordatorios por correo** | **45 días (mes y medio) antes**, un correo al área responsable. **Si la fecha vence sin atenderse**, un aviso de incumplimiento a **Dirección General** con copia al área. Al registrar "Ya se cumplió", los correos pendientes se cancelan. Se envían solos cada día a las 8:05 o con el botón "Enviar recordatorios por correo" |
| **Agregar a mi calendario** | Descarga un archivo `.ics` con todas las fechas y sus recordatorios para Outlook o Google Calendar |

## Cómo funciona

```
Navegador (index.html + app.js)  ──►  Supabase (PostgreSQL)
                                        ├─ contratos, obligaciones, cumplimientos, alertas
                                        ├─ vista v_obligaciones → calcula el semáforo
                                        ├─ registrar_cumplimiento() → guarda y recorre la fecha
                                        └─ pg_cron diario → generar_alertas()
```

- No requiere compilación: HTML, CSS y JavaScript con `@supabase/supabase-js` desde CDN.
- El SQL para reproducir la base va en orden: `supabase/01_esquema.sql`, `02_datos_demo.sql`, `03_proyecto_partes_y_correos.sql` y `04_outlook_y_respuestas.sql`.

## Envío automático desde Outlook de escritorio (activo)

Se usa cuando la cuenta corporativa no permite que servicios externos envíen correo.

- **Qué hace:** de lunes a viernes a las 9:00, una tarea programada de Windows ("Valle Aurora - Recordatorios por correo") ejecuta `automatizacion/enviar-correos-outlook.ps1`. El script:
  1. pide a la app que genere los correos del día;
  2. los envía con el **Outlook de escritorio** de la sesión actual, sin contraseñas;
  3. los marca como enviados en la app.
- **Modo prueba:** si los destinatarios son ficticios (`.example`), todo se redirige a la dirección de prueba configurada en `%LOCALAPPDATA%\ValleAurora\config.json` (`destino_pruebas`), con `[PRUEBA → destinatario original]` en el asunto y un aviso de datos ficticios.
- **Seguridad:** marcar correos como enviados requiere una llave privada guardada solo en `%LOCALAPPDATA%\ValleAurora\token.txt`. No está en el repositorio ni se puede leer desde la API.
- **Bitácora:** `%LOCALAPPDATA%\ValleAurora\envios.log`.
- **Requisitos:** la computadora encendida, con la sesión iniciada y Outlook configurado. Si a las 9:00 está apagada, la tarea corre al encenderla.
- **Probar sin enviar:**
  ```bash
  powershell -NoProfile -ExecutionPolicy Bypass -File automatizacion/enviar-correos-outlook.ps1 -Simular
  ```

## Respuestas de las áreas → app + OneDrive (activo)

Cuando una persona **responde** a un recordatorio o a un aviso de incumplimiento, su respuesta se integra sola a la app.

- **Cuándo:** cada hora, de lunes a viernes de 8:00 a 20:00. Lo hace la tarea de Windows "Valle Aurora - Integrar respuestas por correo", que ejecuta `automatizacion/procesar-respuestas-outlook.ps1`.
- **Cómo la reconoce:** cada correo enviado lleva un código `[VA-xxxxxxxx]` en el asunto. Para los correos anteriores al código, se usa el título de la obligación entre comillas en un asunto "RE:".
- **Qué guarda:** en **OneDrive › Parque Solar Valle Aurora › Respuestas de áreas › ‹obligación› › ‹fecha – remitente›** quedan:
  - `Mensaje.txt`, con el texto de la respuesta sin el historial citado;
  - `Correo original.msg`;
  - todos los adjuntos, excepto las imágenes de la firma.
- **En la app:** la obligación muestra "📨 N respuestas · sin revisar". En su detalle aparecen el texto, las ligas a cada archivo y a la carpeta en OneDrive, y los botones **"Usar como evidencia"** (prellena el registro de cumplimiento) y **"Marcar revisada"**.
- **Bitácora:** `%LOCALAPPDATA%\ValleAurora\respuestas.log`.
- **Probar sin correos reales:**
  ```bash
  powershell -NoProfile -ExecutionPolicy Bypass -File automatizacion/procesar-respuestas-outlook.ps1 -Prueba
  ```
  Crea una respuesta de prueba en memoria, sin enviar nada.
- **Simular sobre la bandeja real:**
  ```bash
  powershell -NoProfile -ExecutionPolicy Bypass -File automatizacion/procesar-respuestas-outlook.ps1 -Simular
  ```

> ⚠️ **Privacidad:** el texto de las respuestas y los nombres de archivo quedan en Supabase y, sin inicio de sesión, cualquiera con la app puede leerlos. Los archivos se quedan en OneDrive con sus permisos de CEM. **No usar con información real** hasta agregar autenticación.

## Alternativa: envío desde Gmail

La bandeja y las reglas ya funcionan. Los correos salen desde una cuenta de **Gmail** por SMTP seguro (puerto 465), usando una *contraseña de aplicación*: nunca la contraseña normal de la cuenta. Mientras no se configure, cada correo se puede mandar desde la bandeja con **"Abrir en mi correo"**.

1. **Activa la verificación en dos pasos** de tu cuenta de Google: myaccount.google.com → Seguridad.
2. **Crea una contraseña de aplicación** en myaccount.google.com/apppasswords. Ponle de nombre, por ejemplo, "Valle Aurora" y copia los 16 caracteres que te da Google.
3. En **Supabase → Edge Functions → Secrets**, agrega:
   - `GMAIL_USER`: tu cuenta de Gmail.
   - `GMAIL_APP_PASSWORD`: los 16 caracteres; los espacios se ignoran.
   - `CORREO_PRUEBAS` (opcional): otra dirección a la que redirigir todo.
4. En la app, pulsa **"Enviar recordatorios por correo"**.

**Modo prueba automático:** las áreas del demo tienen correos ficticios (`.example`), así que todos los avisos llegan **a la misma cuenta de Gmail**. El asunto indica a quién iban dirigidos, por ejemplo `[PRUEBA → direccion@aurora-energia.example] INCUMPLIMIENTO: …`. Con correos reales, se envían a sus destinatarios.

**Límites de Gmail:** una cuenta personal envía alrededor de 500 correos al día. Para producción conviene un dominio propio o un servicio transaccional.

La función está en `supabase/functions/enviar-correos/index.ts`.

## Probarla en tu computadora

```bash
node servidor.mjs
```

Abre http://localhost:5173. Hace falta un servidor porque la app usa módulos de JavaScript; si abres `index.html` con doble clic no carga.

## Seguridad

- Row Level Security activo en todas las tablas.
- Cualquier persona con la app puede **leer**. Las únicas escrituras permitidas pasan por dos funciones controladas y validadas:
  - `registrar_cumplimiento`
  - `marcar_alertas_leidas`
- Insertar, editar o borrar directamente está bloqueado (probado).
- La llave de `config.js` es la llave *publishable* de Supabase, diseñada para usarse en el navegador.

**Antes de usarla con contratos reales:**
1. Agregar inicio de sesión (Supabase Auth) y limitar la lectura y escritura a usuarios autorizados.
2. Volver privado el repositorio.
3. Revisar la política de protección de datos: la base está en EE. UU. (us-west-2).

## Siguientes pasos sugeridos

- Alertas por **Telegram** o WhatsApp, además del correo.
- Captura de nuevas obligaciones desde la app.
- Carga de evidencias (PDF) a Supabase Storage.
- Extracción automática de obligaciones desde el PDF del contrato con IA.
