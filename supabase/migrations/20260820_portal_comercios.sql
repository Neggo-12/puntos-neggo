-- Fase 7, sub-tarea: portal propio para comercios (login independiente del admin).
-- Decisión ya confirmada por Jhey: comercios tienen su propio portal, no dependen
-- de que el admin coordine todo por fuera del sistema.
--
-- Diseño de seguridad clave: el código de verificación NUNCA se expone al
-- comercio por SELECT -- se excluye explícitamente en la capa de aplicación
-- (el portal no lo pide via select *). El comercio solo puede confirmarlo
-- escribiéndolo, y el servidor lo compara -- así la confirmación exige que el
-- cliente se lo haya dado en persona, igual que en el flujo que describió Jhey.
--
-- No se reutiliza marcar_canje_pagado ni se cambia el significado de
-- canjes.estado='pagado' (que sigue significando "Neggo ya le reembolsó al
-- comercio"). "El comercio confirmó el código" es un hecho distinto y anterior
-- a eso, por lo que se guarda en una columna nueva (confirmado_comercio_at),
-- no en el estado -- evita romper obtener_pasivo_por_comercio() y cualquier
-- filtro existente por estado.

alter table public.comercios_solo_canje
  add column user_id uuid references auth.users(id);

create unique index idx_comercios_solo_canje_user_id
  on public.comercios_solo_canje(user_id)
  where user_id is not null;

alter table public.canjes
  add column confirmado_comercio_at timestamptz;

create or replace function public.mi_comercio_id()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select id from public.comercios_solo_canje where user_id = auth.uid() limit 1;
$$;

revoke execute on function public.mi_comercio_id() from public, anon;
grant execute on function public.mi_comercio_id() to authenticated;

-- RLS: el comercio ve su propia fila (nombre, datos de pago, etc.), nunca las de otros.
create policy comercio_select_propio on public.comercios_solo_canje
  for select to authenticated
  using (user_id = auth.uid());

-- RLS: el comercio ve solo sus propios canjes -- esto además hace que
-- obtener_pasivo_por_comercio() (Fase 7 anterior, no es SECURITY DEFINER)
-- funcione automáticamente para el comercio sin duplicar lógica: la RLS ya
-- filtra las filas de canjes antes de que la función las agrupe.
create policy comercio_select_propios_canjes on public.canjes
  for select to authenticated
  using (comercio_id = public.mi_comercio_id());

create or replace function public.confirmar_canje_comercio(p_canje_id text, p_codigo text)
returns table(canje_id text, confirmado_comercio_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mi_comercio_id text;
  v_canje record;
  v_confirmado_at timestamptz;
begin
  v_mi_comercio_id := public.mi_comercio_id();
  if v_mi_comercio_id is null then
    raise exception 'No autorizado';
  end if;

  select c.id, c.comercio_id, c.estado, c.codigo_verificacion, c.confirmado_comercio_at
  into v_canje
  from public.canjes c
  where c.id = p_canje_id
  for update;

  if v_canje.id is null or v_canje.comercio_id <> v_mi_comercio_id then
    raise exception 'No autorizado';
  end if;

  if v_canje.estado <> 'pendiente_pago' then
    raise exception 'El canje no está pendiente de pago (estado actual: %)', v_canje.estado;
  end if;

  if v_canje.confirmado_comercio_at is not null then
    raise exception 'Este canje ya fue confirmado';
  end if;

  if v_canje.codigo_verificacion is null or upper(btrim(v_canje.codigo_verificacion)) <> upper(btrim(p_codigo)) then
    raise exception 'Código de verificación incorrecto';
  end if;

  update public.canjes as c
  set confirmado_comercio_at = now()
  where c.id = p_canje_id and c.confirmado_comercio_at is null
  returning c.confirmado_comercio_at into v_confirmado_at;

  if not found then
    raise exception 'No se pudo confirmar el canje % (posible carrera con otra actualización)', p_canje_id;
  end if;

  perform public._log_audit('canje.confirmado_comercio', v_mi_comercio_id, p_canje_id, jsonb_build_object());

  return query select p_canje_id, v_confirmado_at;
end;
$$;

revoke execute on function public.confirmar_canje_comercio(text, text) from public, anon;
grant execute on function public.confirmar_canje_comercio(text, text) to authenticated;
