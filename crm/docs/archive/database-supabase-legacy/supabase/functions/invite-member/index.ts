import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

interface InvitePayload {
  organization_id: string;
  email: string;
  role_id: string;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Obtém o JWT do header para identificar o usuário que está convidando
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Missing authorization header" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  let payload: InvitePayload;
  try {
    payload = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON body" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const { organization_id, email, role_id } = payload;

  if (!organization_id || !email || !role_id) {
    return new Response(
      JSON.stringify({ error: "organization_id, email, and role_id are required" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Cliente com a service_role key para operações privilegiadas
  const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  // Cliente com o JWT do usuário para validar permissões via RLS
  const supabaseUser = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } }
  );

  // 1. Verifica que o caller é membro ativo da org
  const { data: callerMember, error: callerError } = await supabaseUser
    .from("organization_members")
    .select("id")
    .eq("organization_id", organization_id)
    .in("status", ["active"])
    .is("deleted_at", null)
    .maybeSingle();

  if (callerError || !callerMember) {
    return new Response(
      JSON.stringify({ error: "You are not an active member of this organization" }),
      { status: 403, headers: { "Content-Type": "application/json" } }
    );
  }

  // 1b. Verifica permissão RBAC: invite_members
  const { data: canInvite, error: permError } = await supabaseUser.rpc("has_permission", {
    p_org_id: organization_id,
    p_permission: "invite_members",
  });

  if (permError || !canInvite) {
    return new Response(
      JSON.stringify({ error: "You do not have permission to invite members to this organization" }),
      { status: 403, headers: { "Content-Type": "application/json" } }
    );
  }

  // 2. Valida que o role_id pertence à org
  const { data: role, error: roleError } = await supabaseAdmin
    .from("organization_roles")
    .select("id")
    .eq("id", role_id)
    .eq("organization_id", organization_id)
    .maybeSingle();

  if (roleError || !role) {
    return new Response(
      JSON.stringify({ error: "Role not found or does not belong to this organization" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // 3. Verifica se já existe um usuário com esse email
  const { data: existingUsers } = await supabaseAdmin.auth.admin.listUsers();
  const existingUser = existingUsers?.users?.find((u) => u.email === email);

  // 4. Verifica se já é membro (ativo ou convidado) desta org
  if (existingUser) {
    const { data: existingMember } = await supabaseAdmin
      .from("organization_members")
      .select("id, status")
      .eq("organization_id", organization_id)
      .eq("user_id", existingUser.id)
      .is("deleted_at", null)
      .maybeSingle();

    if (existingMember) {
      return new Response(
        JSON.stringify({
          error: "User is already a member of this organization",
          status: existingMember.status,
        }),
        { status: 409, headers: { "Content-Type": "application/json" } }
      );
    }
  }

  // 5. Se o usuário já existe no Auth, cria o membro diretamente
  //    Se não existe, cria um usuário placeholder com email e status=invited
  let targetUserId: string;

  if (existingUser) {
    targetUserId = existingUser.id;
  } else {
    // Cria o usuário no Auth sem senha (ele precisará definir via email depois)
    const { data: newUser, error: createUserError } = await supabaseAdmin.auth.admin.createUser({
      email,
      email_confirm: false,
      user_metadata: { invited_to_org: organization_id },
    });

    if (createUserError || !newUser.user) {
      return new Response(
        JSON.stringify({ error: "Failed to create user account", detail: createUserError?.message }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    targetUserId = newUser.user.id;
  }

  // 6. Cria o registro de membro com status = 'invited'
  const { data: newMember, error: memberError } = await supabaseAdmin
    .from("organization_members")
    .insert({
      organization_id,
      user_id: targetUserId,
      role_id,
      status: "invited",
    })
    .select("id, status, created_at")
    .single();

  if (memberError || !newMember) {
    return new Response(
      JSON.stringify({ error: "Failed to create member record", detail: memberError?.message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  return new Response(
    JSON.stringify({
      member_id: newMember.id,
      invited: true,
      status: newMember.status,
      created_at: newMember.created_at,
    }),
    { status: 201, headers: { "Content-Type": "application/json" } }
  );
});
