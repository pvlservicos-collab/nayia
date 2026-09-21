import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

interface AcceptInvitePayload {
  organization_id: string;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Missing authorization header" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  let payload: AcceptInvitePayload;
  try {
    payload = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON body" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const { organization_id } = payload;
  if (!organization_id) {
    return new Response(JSON.stringify({ error: "organization_id is required" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Cliente admin para operações privilegiadas
  const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  // Cliente com JWT do usuário para verificar identidade
  const supabaseUser = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } }
  );

  // Verifica identidade do usuário autenticado
  const { data: { user }, error: userError } = await supabaseUser.auth.getUser();
  if (userError || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Busca o registro de membro do usuário nessa org
  const { data: member, error: memberError } = await supabaseAdmin
    .from("organization_members")
    .select("id, status")
    .eq("organization_id", organization_id)
    .eq("user_id", user.id)
    .is("deleted_at", null)
    .maybeSingle();

  if (memberError || !member) {
    return new Response(
      JSON.stringify({ error: "No pending invitation found for this organization" }),
      { status: 404, headers: { "Content-Type": "application/json" } }
    );
  }

  // Já está ativo
  if (member.status === "active") {
    return new Response(
      JSON.stringify({ member_id: member.id, status: "active", already_active: true }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  }

  // Conta desabilitada
  if (member.status !== "invited") {
    return new Response(
      JSON.stringify({ error: "Member account is disabled and cannot accept invitations" }),
      { status: 403, headers: { "Content-Type": "application/json" } }
    );
  }

  // Ativa o membro
  const { data: updatedMember, error: updateError } = await supabaseAdmin
    .from("organization_members")
    .update({ status: "active" })
    .eq("id", member.id)
    .select("id, status, updated_at")
    .single();

  if (updateError || !updatedMember) {
    return new Response(
      JSON.stringify({ error: "Failed to activate membership", detail: updateError?.message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  // Cria configurações de notificação padrão (upsert seguro)
  await supabaseAdmin
    .from("user_notification_settings")
    .upsert(
      {
        member_id: member.id,
        new_lead_alert: true,
        last_stage_alert: true,
        no_response_24h_alert: true,
      },
      { onConflict: "member_id" }
    );

  return new Response(
    JSON.stringify({
      member_id: updatedMember.id,
      status: updatedMember.status,
      accepted: true,
      updated_at: updatedMember.updated_at,
    }),
    { status: 200, headers: { "Content-Type": "application/json" } }
  );
});
