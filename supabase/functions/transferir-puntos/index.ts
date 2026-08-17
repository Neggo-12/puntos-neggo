import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// Endpoint servidor-a-servidor. Nunca se llama desde el navegador de un cliente.
// Autenticacion por header x-internal-secret (no JWT) -- por eso verify_jwt=false,
// segun la excepcion documentada por la propia herramienta de deploy.
//
// La "confirmacion adicional" que pide modelo-economico-v1.md seccion 5 es
// responsabilidad de la UX del producto que llama esto (Neggo/Talleres) -- este
// endpoint asume que ya se confirmo con el usuario antes de llamarlo.
const INTERNAL_SECRET = Deno.env.get("INTERNAL_SECRET");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  if (!INTERNAL_SECRET) {
    console.error("INTERNAL_SECRET no configurado en el proyecto");
    return json({ error: "server_misconfigured" }, 500);
  }

  if (req.headers.get("x-internal-secret") !== INTERNAL_SECRET) {
    return json({ error: "unauthorized" }, 401);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json_body" }, 400);
  }

  const {
    tipoDocumentoOrigen, numeroDocumentoOrigen,
    tipoDocumentoDestino, numeroDocumentoDestino,
    puntos, origenProducto, referenciaExterna, motivo,
  } = body;

  if (
    typeof tipoDocumentoOrigen !== "string" || !tipoDocumentoOrigen ||
    typeof numeroDocumentoOrigen !== "string" || !numeroDocumentoOrigen ||
    typeof tipoDocumentoDestino !== "string" || !tipoDocumentoDestino ||
    typeof numeroDocumentoDestino !== "string" || !numeroDocumentoDestino ||
    typeof origenProducto !== "string" || !origenProducto ||
    typeof puntos !== "number" || !(puntos > 0)
  ) {
    return json({
      error: "campos_invalidos",
      detalle: "tipoDocumentoOrigen, numeroDocumentoOrigen, tipoDocumentoDestino, numeroDocumentoDestino, origenProducto (string) y puntos (number > 0) son obligatorios",
    }, 400);
  }

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const { data, error } = await supabase.rpc("transferir_puntos", {
    p_tipo_documento_origen: tipoDocumentoOrigen,
    p_numero_documento_origen: numeroDocumentoOrigen,
    p_tipo_documento_destino: tipoDocumentoDestino,
    p_numero_documento_destino: numeroDocumentoDestino,
    p_puntos: puntos,
    p_origen_producto: origenProducto,
    p_referencia_externa: typeof referenciaExterna === "string" ? referenciaExterna : null,
    p_motivo: typeof motivo === "string" ? motivo : null,
  });

  if (error) {
    console.error("transferir_puntos error", error);
    return json({ error: "operacion_rechazada", detalle: error.message }, 400);
  }

  const resultado = Array.isArray(data) ? data[0] : data;
  return json(resultado, 200);
});
