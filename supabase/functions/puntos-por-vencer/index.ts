import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// Endpoint servidor-a-servidor. Nunca se llama desde el navegador de un cliente.
// Autenticacion por header x-internal-secret (no JWT) -- por eso verify_jwt=false,
// segun la excepcion documentada por la propia herramienta de deploy.
//
// Puntos Neggo no envia notificaciones -- solo expone la data. Quien llama esto
// (Neggo/Talleres) decide como avisarle al cliente (push, email, banner in-app).
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

  const { tipoDocumento, numeroDocumento, dias } = body;

  if (
    typeof tipoDocumento !== "string" || !tipoDocumento ||
    typeof numeroDocumento !== "string" || !numeroDocumento
  ) {
    return json({
      error: "campos_invalidos",
      detalle: "tipoDocumento y numeroDocumento (string) son obligatorios; dias (number) es opcional, default 15",
    }, 400);
  }

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const { data, error } = await supabase.rpc("puntos_por_vencer_cliente", {
    p_tipo_documento: tipoDocumento,
    p_numero_documento: numeroDocumento,
    p_dias: typeof dias === "number" && dias > 0 ? dias : 15,
  });

  if (error) {
    console.error("puntos_por_vencer_cliente error", error);
    return json({ error: "operacion_rechazada", detalle: error.message }, 400);
  }

  return json({ lotes: data ?? [] }, 200);
});
