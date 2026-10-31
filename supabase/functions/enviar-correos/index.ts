// Edge Function: genera la bandeja de correos y envía los pendientes desde Gmail (SMTP).
// Secretos (Supabase → Edge Functions → Secrets):
//   GMAIL_USER          cuenta de Gmail que envía, p. ej. tu.correo@gmail.com
//   GMAIL_APP_PASSWORD  contraseña de aplicación de 16 caracteres (Cuenta de Google → Seguridad → Contraseñas de aplicaciones)
//   CORREO_PRUEBAS      opcional: si se define, TODOS los correos se redirigen a esta dirección.
//                       Si no se define y el destinatario es ficticio (.example), se envían a GMAIL_USER.
import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient } from 'jsr:@supabase/supabase-js@2';
import nodemailer from 'npm:nodemailer@6.9.16';

const NOMBRE = 'Parque Solar Valle Aurora · Cumplimiento';
const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
const lista = (s: string | null) => (s ?? '').split(',').map((x) => x.trim()).filter(Boolean);
const esFicticio = (correo: string) => /\.example$/i.test(correo);

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'Método no permitido' }, 405);

  const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

  const gen = await sb.rpc('generar_correos');
  if (gen.error) return json({ error: gen.error.message }, 500);

  // Incluye los que fallaron antes (p. ej., por una contraseña mal capturada) para reintentarlos
  const { data: pendientes, error } = await sb.from('correos').select('*').in('estado', ['pendiente', 'error'])
    .order('tipo', { ascending: false }).order('fecha_objetivo').limit(50);
  if (error) return json({ error: error.message }, 500);

  const usuario = Deno.env.get('GMAIL_USER');
  const clave = Deno.env.get('GMAIL_APP_PASSWORD');
  if (!usuario || !clave) {
    return json({ configurado: false, proveedor: 'gmail', nuevos: gen.data, pendientes: pendientes.length });
  }

  // Puerto 465 (SSL): Supabase bloquea las salidas por 25 y 587.
  const smtp = nodemailer.createTransport({
    host: 'smtp.gmail.com', port: 465, secure: true,
    auth: { user: usuario, pass: clave.replace(/\s+/g, '') },
  });
  const pruebas = Deno.env.get('CORREO_PRUEBAS');
  let enviados = 0, errores = 0, ultimoError = '';

  for (const c of pendientes) {
    const para = lista(c.para), cc = lista(c.cc);
    const redirigir = pruebas || [...para, ...cc].some(esFicticio) ? (pruebas || usuario) : null;
    try {
      await smtp.sendMail({
        from: `"${NOMBRE}" <${usuario}>`,
        to: redirigir ? [redirigir] : para,
        cc: redirigir ? [] : cc,
        subject: redirigir ? `[PRUEBA → ${c.para}${c.cc ? ' · CC ' + c.cc : ''}] ${c.asunto}` : c.asunto,
        text: c.cuerpo,
      });
      enviados++;
      await sb.from('correos').update({ estado: 'enviado', enviado_at: new Date().toISOString(), error: redirigir ? `Prueba: enviado a ${redirigir}` : null }).eq('id', c.id);
    } catch (e) {
      errores++;
      ultimoError = String((e as Error).message ?? e).slice(0, 300);
      await sb.from('correos').update({ estado: 'error', error: ultimoError }).eq('id', c.id);
      // Si Gmail rechaza la autenticación, no tiene caso seguir intentando
      if (/auth|535|534|Invalid login/i.test(ultimoError)) break;
    }
  }
  smtp.close();
  return json({ configurado: true, proveedor: 'gmail', nuevos: gen.data, enviados, errores, ultimoError: ultimoError || undefined });
});
