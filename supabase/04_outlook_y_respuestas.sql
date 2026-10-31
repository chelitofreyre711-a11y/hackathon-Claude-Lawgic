-- Parque Solar Valle Aurora · Envío desde Outlook de escritorio y respuestas de las áreas (después de 01–03)

-- Ajustes privados: RLS sin políticas → no se pueden leer desde la API
create table public.ajustes_privados (clave text primary key, valor text not null);
alter table public.ajustes_privados enable row level security;
insert into public.ajustes_privados (clave, valor)
values ('token_envio_outlook', encode(extensions.gen_random_bytes(24), 'hex'));
-- El token se copia a %LOCALAPPDATA%\ValleAurora\token.txt en la computadora que ejecuta los scripts.

-- El script de Outlook marca como enviados los correos que despachó
create or replace function public.marcar_correos_enviados(p_ids uuid[], p_token text, p_nota text default null)
returns int language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  if p_token is null or p_token <> (select valor from public.ajustes_privados where clave = 'token_envio_outlook') then
    raise exception 'No autorizado';
  end if;
  update public.correos
     set estado = 'enviado', enviado_at = now(), error = left(nullif(trim(p_nota), ''), 300)
   where id = any(p_ids) and estado in ('pendiente', 'error');
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function public.marcar_correos_enviados(uuid[], text, text) from public, anon, authenticated;
grant execute on function public.marcar_correos_enviados(uuid[], text, text) to anon;

-- Respuestas de las áreas (texto + archivos guardados en OneDrive)
create table public.respuestas (
  id uuid primary key default gen_random_uuid(),
  obligacion_id uuid not null references public.obligaciones(id) on delete cascade,
  correo_id uuid references public.correos(id) on delete set null,
  mensaje_id text not null unique,
  remitente text not null,
  asunto text,
  texto text,
  recibido_at timestamptz not null,
  archivos jsonb not null default '[]'::jsonb,   -- [{nombre, url, tamano}]
  carpeta_url text,
  revisada boolean not null default false,
  created_at timestamptz not null default now()
);
create index on public.respuestas (obligacion_id);
alter table public.respuestas enable row level security;
create policy "lectura respuestas" on public.respuestas for select to anon, authenticated using (true);

create or replace function public.registrar_respuesta(
  p_token text, p_obligacion uuid, p_correo uuid, p_mensaje_id text, p_remitente text,
  p_asunto text, p_texto text, p_recibido timestamptz, p_archivos jsonb, p_carpeta_url text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if p_token is null or p_token <> (select valor from public.ajustes_privados where clave = 'token_envio_outlook') then
    raise exception 'No autorizado';
  end if;
  insert into public.respuestas (obligacion_id, correo_id, mensaje_id, remitente, asunto, texto, recibido_at, archivos, carpeta_url)
  values (p_obligacion, p_correo, left(p_mensaje_id, 500), left(p_remitente, 200), left(p_asunto, 300),
          left(p_texto, 4000), p_recibido, coalesce(p_archivos, '[]'::jsonb), left(p_carpeta_url, 1000))
  on conflict (mensaje_id) do nothing
  returning id into v_id;
  return v_id;
end $$;
revoke execute on function public.registrar_respuesta(text, uuid, uuid, text, text, text, text, timestamptz, jsonb, text) from public, anon, authenticated;
grant execute on function public.registrar_respuesta(text, uuid, uuid, text, text, text, text, timestamptz, jsonb, text) to anon;

create or replace function public.marcar_respuesta_revisada(p_id uuid) returns void
language sql security definer set search_path = '' as $$
  update public.respuestas set revisada = true where id = p_id;
$$;
revoke execute on function public.marcar_respuesta_revisada(uuid) from public, anon, authenticated;
grant execute on function public.marcar_respuesta_revisada(uuid) to anon, authenticated;
