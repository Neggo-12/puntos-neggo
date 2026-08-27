-- CORRIGE un error de diseño de la migración anterior (codigo_publico_cliente):
-- `codigo_publico` YA EXISTÍA desde Fase 1 (20260817_ledger_base.sql) con un
-- propósito distinto y ya documentado en docs/sistema-puntos-unificado.md
-- sección 3: un código OPACO derivado del id interno ('PT-' + primeros 6 del id),
-- generado por trg_set_codigo_publico_cliente, para que un comercio pueda
-- verificar "sí es el cliente X" sin exponer el documento. Ese trigger sigue
-- corriendo en cada INSERT y, al ser alfabéticamente posterior
-- (trg_set_codigo_publico_cliente > trg_generar_codigo_publico), pisaba
-- silenciosamente el valor que mi trigger nuevo ponía. Se detectó al verificar
-- con datos reales -- nunca llegó a producción (0 clientes reales tenían
-- codigo_publico todavía, solo datos de prueba ya borrados).
--
-- La "llave" que pidió Jhey (nombre + últimos 2 dígitos de cédula, ej.
-- jheison68) es un concepto DIFERENTE: una llave memorable para que el cliente
-- se identifique a sí mismo en la página de Puntos Neggo (consulta de saldo,
-- transferencias). No debe compartir columna con codigo_publico. Se crea una
-- columna nueva, llave_cliente, y el trigger se re-apunta a ella.

-- 1) Deshacer lo que pisaba el codigo_publico existente.
drop trigger if exists trg_generar_codigo_publico on public.clientes_puntos;
drop function if exists public._trigger_generar_codigo_publico();
drop function if exists public._generar_codigo_publico(text, text, text);

-- 2) Columna nueva para la llave memorable del cliente.
alter table public.clientes_puntos add column llave_cliente text unique;

create or replace function public._generar_llave_cliente(p_nombre text, p_numero_documento text, p_cliente_id text)
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
      where cp.llave_cliente = v_candidato and cp.id <> p_cliente_id
    );

    v_sufijo_len := v_sufijo_len + 1;
    exit when v_sufijo_len > length(v_solo_digitos) + 20;
  end loop;

  return v_candidato;
end;
$$;

create or replace function public._trigger_generar_llave_cliente()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.nombre is not null and new.nombre <> '' and new.llave_cliente is null then
    new.llave_cliente := public._generar_llave_cliente(new.nombre, new.numero_documento, new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_generar_llave_cliente on public.clientes_puntos;
create trigger trg_generar_llave_cliente
before insert or update of nombre on public.clientes_puntos
for each row execute function public._trigger_generar_llave_cliente();
