-- Fase 7, sub-tarea: soporte para "la pagina de puntos Neggo".
-- Jhey definio que cada cliente tiene una "llave" para identificarse (ej.
-- jheison68 = primer nombre + ultimos 2 digitos de la cedula). Este es el
-- primer intento -- ver la migracion 20260821_llave_cliente_corrige_colision_codigo_publico.sql
-- para la correccion: aqui la llave se guardo por error en la columna
-- codigo_publico, que ya existia desde Fase 1 (20260817_ledger_base.sql) con
-- un proposito DISTINTO (codigo opaco derivado del id interno, para que un
-- comercio verifique la identidad del cliente sin exponer el documento -- ver
-- docs/sistema-puntos-unificado.md seccion 3). Se deja esta migracion tal
-- como se aplico -- nunca se edita una migracion ya aplicada, el error se
-- corrige hacia adelante en la siguiente.
--
-- Ademas extiende otorgar_puntos con un p_nombre opcional: nada llenaba
-- clientes_puntos.nombre hasta ahora, y sin nombre la llave nunca se puede
-- generar. Semantica "gana el primer nombre conocido": si el cliente ya
-- tiene nombre guardado, una compra posterior con otro nombre no lo pisa.

create or replace function public._normalizar_para_codigo(p_texto text)
returns text
language sql
immutable
set search_path = public
as $$
  select lower(regexp_replace(translate(coalesce(p_texto, ''), 'áéíóúÁÉÍÓÚñÑüÜ', 'aeiouAEIOUnNuU'), '[^a-zA-Z0-9]', '', 'g'));
$$;

create or replace function public._generar_codigo_publico(p_nombre text, p_numero_documento text, p_cliente_id text)
returns text
language plpgsql
stable
set search_path = public
as $$
declare
  v_nombre_norm text;
  v_solo_digitos text;
  v_sufijo_len integer;
  v_candidato text;
begin
  v_nombre_norm := public._normalizar_para_codigo(split_part(coalesce(p_nombre, ''), ' ', 1));
  if v_nombre_norm = '' then
    return null;
  end if;

  v_solo_digitos := regexp_replace(coalesce(p_numero_documento, ''), '[^0-9]', '', 'g');
  if length(v_solo_digitos) = 0 then
    return null;
  end if;

  v_sufijo_len := 2;
  loop
    if v_sufijo_len <= length(v_solo_digitos) then
      v_candidato := v_nombre_norm || right(v_solo_digitos, v_sufijo_len);
    else
      v_candidato := v_nombre_norm || v_solo_digitos || (v_sufijo_len - length(v_solo_digitos))::text;
    end if;

    exit when not exists (
      select 1 from public.clientes_puntos cp
      where cp.codigo_publico = v_candidato and cp.id <> p_cliente_id
    );

    v_sufijo_len := v_sufijo_len + 1;
    exit when v_sufijo_len > length(v_solo_digitos) + 20;
  end loop;

  return v_candidato;
end;
$$;

create or replace function public._trigger_generar_codigo_publico()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.nombre is not null and new.nombre <> '' and new.codigo_publico is null then
    new.codigo_publico := public._generar_codigo_publico(new.nombre, new.numero_documento, new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_generar_codigo_publico on public.clientes_puntos;
create trigger trg_generar_codigo_publico
before insert or update of nombre on public.clientes_puntos
for each row execute function public._trigger_generar_codigo_publico();

create or replace function public.otorgar_puntos(p_tipo_documento text, p_numero_documento text, p_valor_compra numeric, p_comercio_id text, p_origen_producto text, p_referencia_externa text DEFAULT NULL::text, p_motivo text DEFAULT NULL::text, p_nombre text DEFAULT NULL::text)
RETURNS TABLE(cliente_id text, puntos_otorgados integer, multiplicador integer, saldo_nuevo integer, ya_procesado boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_cliente_id text;
  v_estado text;
  v_puntos_base integer;
  v_multiplicador integer := 1;
  v_puntos integer;
  v_saldo_nuevo integer;
  v_es_cliente_nuevo boolean;
  v_movimiento_existente record;
begin
  if p_tipo_documento is null or p_numero_documento is null then
    raise exception 'tipo_documento y numero_documento son obligatorios';
  end if;
  if p_valor_compra is null or p_valor_compra <= 0 then
    raise exception 'valor_compra debe ser mayor a cero';
  end if;
  if p_comercio_id is null or p_origen_producto is null then
    raise exception 'comercio_id y origen_producto son obligatorios';
  end if;

  insert into public.clientes_puntos (tipo_documento, numero_documento, nombre)
  values (p_tipo_documento, p_numero_documento, p_nombre)
  on conflict (tipo_documento, numero_documento) do update
    set nombre = excluded.nombre
    where public.clientes_puntos.nombre is null and excluded.nombre is not null;

  select cp.id, cp.estado into v_cliente_id, v_estado
  from public.clientes_puntos cp
  where cp.tipo_documento = p_tipo_documento and cp.numero_documento = p_numero_documento;

  if v_estado = 'congelado' then
    raise exception 'Cliente congelado (posible fraude) -- no se pueden otorgar puntos hasta descongelar la cuenta';
  end if;

  if p_referencia_externa is not null then
    select pm.puntos, pm.multiplicador into v_movimiento_existente
    from public.puntos_movimientos pm
    where pm.origen_producto = p_origen_producto
      and pm.referencia_externa = p_referencia_externa
      and pm.tipo = 'ganado';

    if found then
      select cp.saldo into v_saldo_nuevo from public.clientes_puntos cp where cp.id = v_cliente_id;
      return query select v_cliente_id, v_movimiento_existente.puntos, v_movimiento_existente.multiplicador, v_saldo_nuevo, true;
      return;
    end if;
  end if;

  select not exists (
    select 1 from public.puntos_movimientos pm
    where pm.cliente_id = v_cliente_id and pm.tipo = 'ganado' and pm.comercio_origen_id = p_comercio_id
  ) into v_es_cliente_nuevo;

  if v_es_cliente_nuevo then
    v_multiplicador := 2;
  end if;

  v_puntos_base := floor(p_valor_compra / 800);
  v_puntos := v_puntos_base * v_multiplicador;

  if v_puntos <= 0 then
    select cp.saldo into v_saldo_nuevo from public.clientes_puntos cp where cp.id = v_cliente_id;
    return query select v_cliente_id, 0, v_multiplicador, v_saldo_nuevo, false;
    return;
  end if;

  insert into public.puntos_movimientos (cliente_id, tipo, puntos, valor_compra, multiplicador, comercio_origen_id, origen_producto, referencia_externa, motivo, fecha_vencimiento)
  values (v_cliente_id, 'ganado', v_puntos, p_valor_compra, v_multiplicador, p_comercio_id, p_origen_producto, p_referencia_externa, p_motivo, (now() + interval '12 months')::date);

  update public.clientes_puntos
  set saldo = saldo + v_puntos
  where id = v_cliente_id
  returning saldo into v_saldo_nuevo;

  if not found then
    raise exception 'No se pudo actualizar el saldo del cliente %', v_cliente_id;
  end if;

  perform public._log_audit('puntos.otorgado', p_origen_producto, v_cliente_id,
    jsonb_build_object('puntos', v_puntos, 'multiplicador', v_multiplicador, 'comercioId', p_comercio_id, 'referenciaExterna', p_referencia_externa));

  return query select v_cliente_id, v_puntos, v_multiplicador, v_saldo_nuevo, false;
end;
$function$;

revoke execute on function public.otorgar_puntos(text, text, numeric, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.otorgar_puntos(text, text, numeric, text, text, text, text, text) to service_role;
