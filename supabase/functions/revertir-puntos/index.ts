import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// Endpoint servidor-a-servidor. Nunca se llama desde el navegador de un cliente.
// Autenticacion por header x-internal-secret (no JWT) -- por eso verify_jwt=false,
// segun la excepcion documentada por la propia herramienta de deploy.
//
// Lo llama Neggo/Talleres cuando cancelan o devuelven una compra que ya habia
// otorgado puntos (modelo-economico-v1.md seccion 9). Idempotente por
// origenProducto+referenciaExterna -- la misma referencia que se uso al otorgar.
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

  const { origenProducto, referenciaExterna, motivo } = body;

  if (
    typeof origenProducto !== "string" || !origenProducto ||
    typeof referenciaExterna !== "string" || !referenciaExterna
  ) {
    return json({
      error: "campos_invalidos",
      detalle: "origenProducto y referenciaExterna (string) son obligatorios -- deben coincidir con los usados al otorgar los puntos",
    }, 400);
  }

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const { data, error } = await supabase.rpc("revertir_puntos_otorgados", {
    p_origen_producto: origenProducto,
    p_referencia_externa: referenciaExterna,
    p_motivo: typeof motivo === "string" ? motivo : null,
  });

  if (error) {
    console.error("revertir_puntos_otorgados error", error);
    return json({ error: "operacion_rechazada", detalle: error.message }, 400);
  }

  const resultado = Array.isArray(data) ? data[0] : data;
  return json(resultado, 200);
});
