-- Corrige ambigüedad de nombre: el parámetro de salida confirmado_comercio_at
-- (de RETURNS TABLE) colisionaba con la columna del mismo nombre en el UPDATE.
-- Se soluciona calificando la tabla con alias y el RETURNING con ese alias.
-- Mismo patrón de bug que ya había mordido el proyecto en Fase 1 -- se corrige
-- con una migración nueva, nunca se toca la migración original ya aplicada.

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
