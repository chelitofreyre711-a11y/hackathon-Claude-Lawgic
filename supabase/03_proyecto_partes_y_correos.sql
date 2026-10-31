-- Parque Solar Valle Aurora · Proyecto/partes ficticias, áreas responsables y correos (se aplica después de 01 y 02)

-- Áreas responsables y Dirección General
create table public.areas (
  id uuid primary key default gen_random_uuid(),
  nombre text not null unique,
  titular text,
  correo text not null,
  es_direccion_general boolean not null default false
);
alter table public.areas enable row level security;
create policy "lectura areas" on public.areas for select to anon, authenticated using (true);

alter table public.obligaciones add column area_id uuid references public.areas(id);
create index on public.obligaciones (area_id);

alter table public.contratos
  add column proyecto text, add column objeto text, add column partes jsonb not null default '[]'::jsonb,
  add column monto numeric, add column moneda text, add column plazo text, add column fecha_vencimiento date,
  add column garantias text, add column ley_jurisdiccion text;

-- Áreas ficticias (dominio reservado .example)
insert into public.areas (nombre, titular, correo, es_direccion_general) values
 ('Tesorería',          'Mariana Solís (ficticia)',     'tesoreria@aurora-energia.example', false),
 ('Finanzas',           'Ricardo Peña (ficticio)',      'finanzas@aurora-energia.example',  false),
 ('Jurídico',           'Lucía Aranda (ficticia)',      'juridico@aurora-energia.example',  false),
 ('Operaciones',        'Tomás Ibarra (ficticio)',      'operaciones@aurora-energia.example', false),
 ('Dirección General',  'Andrés Villaseñor (ficticio)', 'direccion@aurora-energia.example', true);

update public.obligaciones o set area_id = a.id
from public.areas a
where a.nombre = case
  when o.responsable like 'Jurídico%' then 'Jurídico'
  when o.responsable like 'Dirección%' then 'Dirección General'
  else o.responsable end;
update public.obligaciones o set responsable = a.nombre from public.areas a where a.id = o.area_id;

-- Proyecto y partes ficticias
update public.contratos set
  nombre = 'Contrato de Crédito Simple', proyecto = 'Parque Solar Valle Aurora',
  contraparte = 'Banco de Fomento Horizonte, S.N.C.',
  objeto = 'Crédito de largo plazo para financiar la construcción, puesta en marcha y operación del Parque Solar Valle Aurora (120 MW).',
  partes = '[{"rol":"Acreditante","nombre":"Banco de Fomento Horizonte, S.N.C."},
             {"rol":"Acreditada","nombre":"Aurora Energía Renovable, S.A.P.I. de C.V."},
             {"rol":"Obligado solidario","nombre":"Grupo Inversor Cumbre Verde, S.A. de C.V."}]'::jsonb,
  monto = 85000000, moneda = 'USD', plazo = '15 años', fecha_vencimiento = (fecha_firma + interval '15 years')::date,
  garantias = 'Fideicomiso de garantía y fuente de pago F/1000; prenda sin transmisión de posesión sobre acciones de la acreditada; cesión de derechos de cobro de los contratos de venta de energía.',
  ley_jurisdiccion = 'Leyes federales de México; tribunales de la Ciudad de México.',
  resumen = 'Préstamo para construir y operar el parque solar. El dinero que genere la planta se usa primero para pagar al banco, a través del fideicomiso. DATOS FICTICIOS.'
where tipo = 'Crédito';

update public.contratos set
  nombre = 'Fideicomiso de Garantía y Fuente de Pago F/1000', proyecto = 'Parque Solar Valle Aurora',
  contraparte = 'Fiduciaria Puente Alto, S.A.',
  objeto = 'Concentrar todos los ingresos del Parque Solar Valle Aurora y aplicarlos, en el orden pactado, al pago del crédito, la operación del proyecto y, al final, a los socios.',
  partes = '[{"rol":"Fiduciario","nombre":"Fiduciaria Puente Alto, S.A."},
             {"rol":"Fideicomitente y fideicomisario en segundo lugar","nombre":"Aurora Energía Renovable, S.A.P.I. de C.V."},
             {"rol":"Fideicomisario en primer lugar","nombre":"Banco de Fomento Horizonte, S.N.C."}]'::jsonb,
  monto = null, moneda = null, plazo = 'Mientras exista saldo del crédito', fecha_vencimiento = null,
  garantias = 'Patrimonio: derechos de cobro de los contratos de venta de energía, cuentas del fideicomiso y la cuenta de reserva del servicio de deuda.',
  ley_jurisdiccion = 'Leyes federales de México; tribunales de la Ciudad de México.',
  resumen = 'El fideicomiso recibe el dinero que pagan los clientes de la planta y lo reparte en orden: primero gastos y banco, después reservas y al final los socios. DATOS FICTICIOS.'
where tipo = 'Fideicomiso';

-- Vista con área, titular y correo
drop view public.v_obligaciones;
create view public.v_obligaciones with (security_invoker = true) as
select o.*, c.nombre as contrato_nombre, c.tipo as contrato_tipo, c.contraparte, c.proyecto,
  a.nombre as area_nombre, a.titular as area_titular, a.correo as area_correo,
  case when o.proxima_fecha is null then null else o.proxima_fecha - public.hoy_mx() end as dias_restantes,
  uc.ultima_fecha_cumplimiento,
  case
    when o.proxima_fecha is null and uc.ultima_fecha_cumplimiento is not null and o.periodicidad = 'Única' then 'Cumplida'
    when o.proxima_fecha is null then 'Permanente'
    when o.proxima_fecha < public.hoy_mx() then 'Vencida'
    when o.proxima_fecha - public.hoy_mx() <= (select max(d) from unnest(o.dias_aviso) d) then 'Por vencer'
    else 'En tiempo'
  end as estado
from public.obligaciones o
join public.contratos c on c.id = o.contrato_id
left join public.areas a on a.id = o.area_id
left join lateral (select max(fecha_cumplimiento) as ultima_fecha_cumplimiento from public.cumplimientos cu where cu.obligacion_id = o.id) uc on true
where o.activa;

-- Bandeja de correos
create table public.correos (
  id uuid primary key default gen_random_uuid(),
  obligacion_id uuid not null references public.obligaciones(id) on delete cascade,
  tipo text not null check (tipo in ('recordatorio','incumplimiento')),
  fecha_objetivo date not null,
  para text not null, cc text, asunto text not null, cuerpo text not null,
  estado text not null default 'pendiente' check (estado in ('pendiente','enviado','error','cancelado')),
  error text, enviado_at timestamptz, created_at timestamptz not null default now(),
  unique (obligacion_id, tipo, fecha_objetivo)
);
create index on public.correos (estado);
create index on public.correos (obligacion_id);
alter table public.correos enable row level security;
create policy "lectura correos" on public.correos for select to anon, authenticated using (true);

-- Reglas: recordatorio al área a 45 días o menos; si vence sin atenderse, aviso a Dirección General (CC al área)
create or replace function public.generar_correos() returns int
language plpgsql security definer set search_path = '' as $$
declare n1 int; n2 int; dg public.areas;
begin
  select * into dg from public.areas where es_direccion_general limit 1;

  insert into public.correos (obligacion_id, tipo, fecha_objetivo, para, asunto, cuerpo)
  select v.id, 'recordatorio', v.proxima_fecha, v.area_correo,
    'Recordatorio: "' || v.titulo || '" vence el ' || to_char(v.proxima_fecha,'DD/MM/YYYY'),
    'Hola, equipo de ' || v.area_nombre || ':' || E'\n\n' ||
    'Les recordamos que ' || case when v.dias_restantes = 0 then 'HOY' else 'en ' || v.dias_restantes || ' días (' || to_char(v.proxima_fecha,'DD/MM/YYYY') || ')' end ||
    ' vence esta obligación del ' || v.contrato_nombre || ' – ' || coalesce(v.proyecto,'') || ':' || E'\n\n' ||
    '• Qué hay que hacer: ' || v.titulo || '. ' || v.explicacion_simple || E'\n' ||
    '• Dónde lo dice: ' || coalesce(v.clausula,'—') || E'\n' ||
    '• Si no se cumple: ' || coalesce(v.consecuencia,'—') || E'\n\n' ||
    'Cuando quede atendida, regístrenla en la app del Parque Solar Valle Aurora con el botón "Ya se cumplió" para detener los avisos.' || E'\n' ||
    'Si la fecha pasa sin registrarse, se avisará a Dirección General.' || E'\n\n' ||
    'Parque Solar Valle Aurora · Semáforo de cumplimiento'
  from public.v_obligaciones v
  where v.proxima_fecha is not null and v.dias_restantes between 0 and 45 and v.area_correo is not null
  on conflict do nothing;
  get diagnostics n1 = row_count;

  update public.correos c set estado = 'cancelado', error = 'La fecha ya pasó; se escaló a Dirección General.'
  from public.v_obligaciones v
  where c.obligacion_id = v.id and c.tipo = 'recordatorio' and c.estado = 'pendiente' and v.dias_restantes < 0;

  if dg.id is not null then
    insert into public.correos (obligacion_id, tipo, fecha_objetivo, para, cc, asunto, cuerpo)
    select v.id, 'incumplimiento', v.proxima_fecha, dg.correo, nullif(v.area_correo, dg.correo),
      'INCUMPLIMIENTO: "' || v.titulo || '" venció el ' || to_char(v.proxima_fecha,'DD/MM/YYYY'),
      coalesce(dg.titular, 'Dirección General') || ':' || E'\n\n' ||
      'La siguiente obligación venció hace ' || (-v.dias_restantes) || ' día(s) y no se ha registrado como cumplida:' || E'\n\n' ||
      '• Obligación: ' || v.titulo || E'\n' ||
      '• Contrato: ' || v.contrato_nombre || ' – ' || coalesce(v.proyecto,'') || ' (' || v.contraparte || ')' || E'\n' ||
      '• Fecha límite: ' || to_char(v.proxima_fecha,'DD/MM/YYYY') || E'\n' ||
      '• Área responsable: ' || coalesce(v.area_nombre,'—') || coalesce(' (' || v.area_titular || ')','') || E'\n' ||
      '• Riesgo: ' || coalesce(v.consecuencia,'—') || E'\n\n' ||
      'Acción sugerida: confirmar con el área si ya se cumplió y registrarlo; si no, cumplir de inmediato y, si el contrato lo permite, pedir a la contraparte una prórroga o dispensa por escrito antes de que se convierta en causa de vencimiento anticipado.' || E'\n\n' ||
      'Parque Solar Valle Aurora · Semáforo de cumplimiento'
    from public.v_obligaciones v
    where v.estado = 'Vencida'
    on conflict do nothing;
  end if;
  get diagnostics n2 = row_count;
  return n1 + n2;
end $$;
-- Solo la ejecutan la Edge Function (service role) y pg_cron
revoke execute on function public.generar_correos() from public, anon, authenticated;

-- Al registrar un cumplimiento se cancelan los correos pendientes de ese periodo
create or replace function public.cancelar_correos_cumplidos() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public.correos set estado = 'cancelado', error = 'Cumplida antes del envío.'
  where obligacion_id = new.obligacion_id and estado = 'pendiente'
    and (new.periodo_fecha is null or fecha_objetivo = new.periodo_fecha);
  return new;
end $$;
create trigger cumplimiento_cancela_correos after insert on public.cumplimientos
for each row execute function public.cancelar_correos_cumplidos();
revoke execute on function public.cancelar_correos_cumplidos() from public, anon, authenticated;

-- Envío diario: 14:05 UTC = 08:05 Ciudad de México (llama a la Edge Function enviar-correos)
create extension if not exists pg_net with schema extensions;
select cron.schedule('correos-diarios', '5 14 * * *', $$
  select net.http_post(
    url := 'https://dndeinbqjpvdakufkofy.supabase.co/functions/v1/enviar-correos',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', 'sb_publishable_KD3lrsm4ioaa_AdRXUkW1A_-CAoRs6T',
      'Authorization', 'Bearer sb_publishable_KD3lrsm4ioaa_AdRXUkW1A_-CAoRs6T'),
    body := '{}'::jsonb)
$$);
