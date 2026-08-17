-- Fase 6.1: vencimiento por lote (barrido de puntos vencidos)
--
-- Diseño: el ledger es append-only y solicitar_canje solo resta del saldo total,
-- no rastrea contra qué lote "ganado" específico se aplicó cada canje. Para saber
-- cuánto de un lote sigue sin consumir cuando llega su fecha_vencimiento, este
-- barrido recalcula el consumo en orden FIFO (el lote más antiguo se consume
-- primero) cada vez que corre. No arrastra estado propio aparte del ledger mismo,
-- así que correrlo más de una vez es seguro (idempotente): lo que ya venció en una
-- corrida anterior queda como movimiento 'vencido', y esa misma consulta lo cuenta
-- como consumo en la siguiente corrida -- no se vuelve a descontar.
--
-- Decisión técnica (no de negocio, no inventa nada de modelo-economico-v1.md):
-- orden de consumo FIFO -- estándar de la industria para puntos con vencimiento;
-- ni sistema-puntos-unificado.md ni modelo-economico-v1.md especifican el orden,
-- así que queda documentado acá como la elección por defecto.
--
-- Fuera de alcance de esta migración (sub-tareas aparte de Fase 6, no se inventan
-- ahora): transferencia punto a punto (cuando exista, 'transferido_salida' ya
-- cuenta como consumo en el cálculo de abajo, y 'transferido_entrada' va a
-- necesitar sumarse como lote -- hoy no hay filas de ese tipo) y notificación de
-- vencimiento próximo.

alter table public.puntos_movimientos
  add column lote_origen_id text references public.puntos_movimientos(id);

comment on column public.puntos_movimientos.lote_origen_id is 'Solo para movimientos tipo vencido: referencia al movimiento tipo ganado (lote) del que salieron estos puntos vencidos.';

create or replace function public._pendiente_por_lote(p_cliente_id text)
returns table(movimiento_id text, puntos_lote integer, fecha_vencimiento date, puntos_restantes integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total_consumido numeric;
  v_restante_a_consumir numeric;
  r record;
  v_consumido_de_este_lote numeric;
begin
  select coalesce(sum(-pm.puntos), 0) into v_total_consumido
  from public.puntos_movimientos pm
  where pm.cliente_id = p_cliente_id
    and pm.tipo in ('canjeado', 'transferido_salida', 'vencido');

  v_restante_a_consumir := v_total_consumido;

  for r in
    select pm.id, pm.puntos, pm.fecha_vencimiento
    from public.puntos_movimientos pm
    where pm.cliente_id = p_cliente_id and pm.tipo = 'ganado'
    order by pm.fecha_vencimiento asc, pm.created_at asc
  loop
    v_consumido_de_este_lote := least(r.puntos::numeric, v_restante_a_consumir);
    v_restante_a_consumir := v_restante_a_consumir - v_consumido_de_este_lote;

    movimiento_id := r.id;
    puntos_lote := r.puntos;
    fecha_vencimiento := r.fecha_vencimiento;
    puntos_restantes := (r.puntos - v_consumido_de_este_lote)::integer;
    return next;
  end loop;
end;
$$;

revoke execute on function public._pendiente_por_lote(text) from public, anon, authenticated;

create or replace function public.ejecutar_barrido_vencimientos()
returns table(clientes_afectados integer, puntos_vencidos bigint)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cliente record;
  v_lote record;
  v_clientes_afectados integer := 0;
  v_puntos_vencidos bigint := 0;
  v_afecto_este_cliente boolean;
begin
  for v_cliente in
    select cp.id from public.clientes_puntos cp where cp.saldo > 0
  loop
    v_afecto_este_cliente := false;

    for v_lote in
      select * from public._pendiente_por_lote(v_cliente.id) pl
      where pl.fecha_vencimiento < current_date and pl.puntos_restantes > 0
    loop
      insert into public.puntos_movimientos (cliente_id, tipo, puntos, lote_origen_id, motivo, fecha_vencimiento)
      values (v_cliente.id, 'vencido', -v_lote.puntos_restantes, v_lote.movimiento_id, 'Vencimiento automático de lote', null);

      update public.clientes_puntos
      set saldo = saldo - v_lote.puntos_restantes
      where id = v_cliente.id;

      perform public._log_audit('puntos.vencido', 'sistema', v_cliente.id,
        jsonb_build_object('puntos', v_lote.puntos_restantes, 'loteOrigenId', v_lote.movimiento_id, 'fechaVencimiento', v_lote.fecha_vencimiento));

      v_puntos_vencidos := v_puntos_vencidos + v_lote.puntos_restantes;
      v_afecto_este_cliente := true;
    end loop;

    if v_afecto_este_cliente then
      v_clientes_afectados := v_clientes_afectados + 1;
    end if;
  end loop;

  return query select v_clientes_afectados, v_puntos_vencidos;
end;
$$;

revoke execute on function public.ejecutar_barrido_vencimientos() from public, anon, authenticated;

-- Corre solo una vez al día -- el vencimiento es a nivel de día (fecha_vencimiento
-- es date, no timestamp), no hace falta más frecuencia. 06:00 UTC = 01:00 Bogotá
-- (Colombia no tiene horario de verano, UTC-5 todo el año) -- horario de bajo tráfico.
create extension if not exists pg_cron with schema extensions;

select cron.schedule(
  'puntos-neggo-barrido-vencimientos',
  '0 6 * * *',
  $$select public.ejecutar_barrido_vencimientos();$$
);
