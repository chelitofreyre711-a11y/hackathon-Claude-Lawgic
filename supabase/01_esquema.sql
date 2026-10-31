-- Parque Solar Valle Aurora · Semáforo de cumplimiento — esquema completo (estado final aplicado en Supabase)

-- Fecha "de hoy" en horario de la Ciudad de México
create or replace function public.hoy_mx() returns date
language sql stable set search_path = '' as $$
  select (now() at time zone 'America/Mexico_City')::date
$$;

create table public.contratos (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  tipo text not null check (tipo in ('Crédito','Fideicomiso')),
  contraparte text not null,
  fecha_firma date,
  resumen text,
  created_at timestamptz not null default now()
);

create table public.obligaciones (
  id uuid primary key default gen_random_uuid(),
  contrato_id uuid not null references public.contratos(id) on delete cascade,
  titulo text not null,
  explicacion_simple text not null,
  clausula text,
  categoria text not null check (categoria in ('Pagar','Reportar','Mantener','Hacer','No hacer','Notificar')),
  periodicidad text not null check (periodicidad in ('Única','Mensual','Trimestral','Semestral','Anual','Continua','Por evento')),
  proxima_fecha date,
  dias_aviso int[] not null default '{30,15,7,1}',
  responsable text,
  consecuencia text,
  prioridad text not null default 'Media' check (prioridad in ('Alta','Media','Baja')),
  activa boolean not null default true,
  created_at timestamptz not null default now()
);
create index on public.obligaciones (contrato_id);
create index on public.obligaciones (proxima_fecha);

create table public.cumplimientos (
  id uuid primary key default gen_random_uuid(),
  obligacion_id uuid not null references public.obligaciones(id) on delete cascade,
  periodo_fecha date,
  fecha_cumplimiento date not null default public.hoy_mx(),
  nota text,
  evidencia_url text,
  registrado_por text,
  created_at timestamptz not null default now()
);
create index on public.cumplimientos (obligacion_id);

create table public.alertas (
  id uuid primary key default gen_random_uuid(),
  obligacion_id uuid not null references public.obligaciones(id) on delete cascade,
  tipo text not null check (tipo in ('por_vencer','vencida')),
  fecha_objetivo date not null,
  dias_restantes int not null,
  mensaje text not null,
  leida boolean not null default false,
  created_at timestamptz not null default now(),
  unique (obligacion_id, fecha_objetivo, tipo, dias_restantes)
);
create index on public.alertas (obligacion_id);
create index on public.alertas (leida);

-- Vista con el semáforo de cada obligación
create view public.v_obligaciones with (security_invoker = true) as
select
  o.*,
  c.nombre as contrato_nombre,
  c.tipo as contrato_tipo,
  c.contraparte,
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
left join lateral (
  select max(fecha_cumplimiento) as ultima_fecha_cumplimiento
  from public.cumplimientos cu where cu.obligacion_id = o.id
) uc on true
where o.activa;

-- Registrar un cumplimiento y recorrer la siguiente fecha según la periodicidad
create or replace function public.registrar_cumplimiento(
  p_obligacion uuid, p_nota text default null, p_evidencia text default null, p_registrado_por text default null
) returns public.obligaciones
language plpgsql security definer set search_path = '' as $$
declare
  o public.obligaciones;
  siguiente date;
begin
  if length(coalesce(trim(p_nota),'')) = 0 then raise exception 'Describe qué se hizo para cumplir.'; end if;
  if length(p_nota) > 2000 or length(coalesce(p_registrado_por,'')) > 120 or length(coalesce(p_evidencia,'')) > 1000 then
    raise exception 'El texto es demasiado largo.';
  end if;
  if nullif(trim(p_evidencia),'') is not null and trim(p_evidencia) !~* '^https?://' then
    raise exception 'La liga de evidencia debe empezar con http:// o https://';
  end if;

  select * into o from public.obligaciones where id = p_obligacion and activa for update;
  if not found then raise exception 'Obligación no encontrada'; end if;
  if o.proxima_fecha is null then raise exception 'Esta obligación no tiene una fecha pendiente.'; end if;

  insert into public.cumplimientos (obligacion_id, periodo_fecha, nota, evidencia_url, registrado_por)
  values (o.id, o.proxima_fecha, trim(p_nota), nullif(trim(p_evidencia),''), nullif(trim(p_registrado_por),''));

  siguiente := case o.periodicidad
    when 'Mensual' then (o.proxima_fecha + interval '1 month')::date
    when 'Trimestral' then (o.proxima_fecha + interval '3 months')::date
    when 'Semestral' then (o.proxima_fecha + interval '6 months')::date
    when 'Anual' then (o.proxima_fecha + interval '1 year')::date
    else null
  end;

  update public.obligaciones set proxima_fecha = siguiente where id = o.id returning * into o;
  update public.alertas set leida = true where obligacion_id = o.id and leida = false;
  return o;
end $$;

-- Marcar avisos como leídos
create or replace function public.marcar_alertas_leidas(p_ids uuid[] default null) returns int
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  update public.alertas set leida = true
  where leida = false and (p_ids is null or id = any(p_ids));
  get diagnostics n = row_count;
  return n;
end $$;

-- Generar alertas: avisos previos (según dias_aviso) y vencidas
create or replace function public.generar_alertas() returns int
language plpgsql security invoker set search_path = '' as $$
declare n int;
begin
  insert into public.alertas (obligacion_id, tipo, fecha_objetivo, dias_restantes, mensaje)
  select v.id,
         case when v.dias_restantes < 0 then 'vencida' else 'por_vencer' end,
         v.proxima_fecha,
         case when v.dias_restantes < 0 then -1
              else (select min(d) from unnest(v.dias_aviso) d where d >= v.dias_restantes) end,
         case when v.dias_restantes < 0
              then 'Atrasada: "' || v.titulo || '" debía cumplirse el ' || to_char(v.proxima_fecha,'DD/MM/YYYY') || '.'
              when v.dias_restantes = 0
              then 'Vence HOY: "' || v.titulo || '".'
              else 'Faltan ' || v.dias_restantes || ' días para "' || v.titulo || '" (' || to_char(v.proxima_fecha,'DD/MM/YYYY') || ').'
         end
  from public.v_obligaciones v
  where v.estado in ('Vencida','Por vencer')
  on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end $$;

-- Seguridad: lectura abierta (demo) y escrituras solo mediante las dos funciones controladas
alter table public.contratos enable row level security;
alter table public.obligaciones enable row level security;
alter table public.cumplimientos enable row level security;
alter table public.alertas enable row level security;

create policy "lectura contratos" on public.contratos for select to anon, authenticated using (true);
create policy "lectura obligaciones" on public.obligaciones for select to anon, authenticated using (true);
create policy "lectura cumplimientos" on public.cumplimientos for select to anon, authenticated using (true);
create policy "lectura alertas" on public.alertas for select to anon, authenticated using (true);

revoke execute on function public.registrar_cumplimiento(uuid, text, text, text) from public, anon, authenticated;
revoke execute on function public.marcar_alertas_leidas(uuid[]) from public, anon, authenticated;
revoke execute on function public.generar_alertas() from public, anon, authenticated;
grant execute on function public.registrar_cumplimiento(uuid, text, text, text) to anon, authenticated;
grant execute on function public.marcar_alertas_leidas(uuid[]) to anon, authenticated;

-- Alertas automáticas: todos los días a las 08:00 de la Ciudad de México (14:00 UTC)
create extension if not exists pg_cron;
select cron.schedule('alertas-diarias', '0 14 * * *', $$select public.generar_alertas()$$);
