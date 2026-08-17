-- Fase 6, sub-tarea 3: notificación de vencimiento próximo por lote
-- (modelo-economico-v1.md sección 6: "La app debe avisar antes de que un lote venza").
--
-- Puntos Neggo no envía notificaciones -- no tiene canal de email/push propio, y no es
-- su responsabilidad (esa vive en Neggo/Talleres, que sí conocen al usuario). Lo que
-- expone es la data: "¿este cliente tiene puntos por vencer pronto?", vía la misma
-- Edge Function server-a-servidor que ya usan otorgar-puntos/solicitar-canje. Quien
-- decide cuándo y cómo avisar (push, email, banner in-app) es el producto que consume
-- esto.
--
-- Decisión pendiente de Jhey, NO inventada acá (ya estaba abierta en
-- modelo-economico-v1.md sección 11): la ventana exacta de aviso (¿15 días? ¿30?).
-- Se implementa como parámetro con default 15 -- es el número que el propio Jhey puso
-- como ejemplo en la sección 6 ("ej. 15 días"), no un número inventado nuevo, pero
-- sigue siendo un default configurable por cada llamada, no una decisión final
-- hardcodeada sin retorno.
--
-- Reutiliza _pendiente_por_lote (ya construida y verificada para el barrido de
-- vencimientos) -- mismo cálculo FIFO, solo cambia el filtro: acá busca lotes que
-- TODAVÍA no vencieron pero vencen dentro de la ventana, en vez de lotes ya vencidos.

create or replace function public.puntos_por_vencer_cliente(
  p_tipo_documento text,
  p_numero_documento text,
  p_dias integer default 15
)
returns table(movimiento_id text, puntos_restantes integer, fecha_vencimiento date, dias_restantes integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cliente_id text;
begin
  if p_dias is null or p_dias <= 0 then
    raise exception 'dias debe ser mayor a cero';
  end if;

  select cp.id into v_cliente_id
  from public.clientes_puntos cp
  where cp.tipo_documento = p_tipo_documento and cp.numero_documento = p_numero_documento;

  if v_cliente_id is null then
    return;
  end if;

  return query
  select pl.movimiento_id, pl.puntos_restantes, pl.fecha_vencimiento,
    (pl.fecha_vencimiento - current_date)::integer as dias_restantes
  from public._pendiente_por_lote(v_cliente_id) pl
  where pl.puntos_restantes > 0
    and pl.fecha_vencimiento >= current_date
    and pl.fecha_vencimiento <= current_date + p_dias
  order by pl.fecha_vencimiento asc;
end;
$$;

revoke execute on function public.puntos_por_vencer_cliente(text, text, integer) from public, anon, authenticated;
grant execute on function public.puntos_por_vencer_cliente(text, text, integer) to service_role;
