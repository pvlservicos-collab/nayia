import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

interface ManageMemberPayload {
    action: 'create' | 'update' | 'delete';
    organization_id: string;
    member_id?: string;
    user_id?: string;
    name: string;
    email: string;
    password?: string;
    role_id: string;
}

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req: Request) => {
    // CORS preflight
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders });
    }

    if (req.method !== "POST") {
        return new Response(JSON.stringify({ error: "Method not allowed" }), {
            status: 405,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
        return new Response(JSON.stringify({ error: "Missing authorization header" }), {
            status: 401,
            headers: { "Content-Type": "application/json", ...corsHeaders },
        });
    }

    let payload: ManageMemberPayload;
    try {
        payload = await req.json();
    } catch {
        return new Response(JSON.stringify({ error: "Invalid JSON body" }), {
            status: 400,
            headers: { "Content-Type": "application/json", ...corsHeaders },
        });
    }

    const { action, organization_id, member_id, user_id, name, email, password, role_id } = payload;

    if (!action || !organization_id) {
        return new Response(
            JSON.stringify({ error: "Missing required fields" }),
            { status: 400, headers: { "Content-Type": "application/json", ...corsHeaders } }
        );
    }

    if (action !== 'delete' && (!name || !email || !role_id)) {
        return new Response(
            JSON.stringify({ error: "Missing required fields for create/update" }),
            { status: 400, headers: { "Content-Type": "application/json", ...corsHeaders } }
        );
    }

    const supabaseAdmin = createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Get caller user_id securely using Supabase Auth
    const supabaseClient = createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_ANON_KEY")!,
        { global: { headers: { Authorization: authHeader } } }
    );

    const { data: { user: callerUser }, error: userError } = await supabaseClient.auth.getUser();

    if (userError || !callerUser) {
        return new Response(
            JSON.stringify({ error: "Invalid token or user not found", detail: userError?.message }),
            { status: 401, headers: { "Content-Type": "application/json", ...corsHeaders } }
        );
    }
    const callerUserId = callerUser.id;

    // 1. Evaluate Caller Permissions (using admin to bypass RLS)
    const { data: callerProfile } = await supabaseAdmin
        .from("profiles")
        .select("is_superadmin")
        .eq("id", callerUserId)
        .single();

    const { data: callerMember } = await supabaseAdmin
        .from("organization_members")
        .select("role_id")
        .eq("organization_id", organization_id)
        .eq("user_id", callerUserId)
        .eq("status", "active")
        .is("deleted_at", null)
        .maybeSingle();

    if (!callerProfile?.is_superadmin) {
        if (!callerMember?.role_id) {
            return new Response(
                JSON.stringify({ error: "You are not an active member of this organization" }),
                { status: 403, headers: { "Content-Type": "application/json", ...corsHeaders } }
            );
        }

        const { data: callerRole } = await supabaseAdmin
            .from("organization_roles")
            .select("name, permissions")
            .eq("id", callerMember.role_id)
            .maybeSingle();

        const isFixedAdmin = callerRole?.name?.toLowerCase() === 'administrador';
        const canManage = isFixedAdmin || (callerRole?.permissions as any)?.settings?.manage_members === true;

        if (!canManage) {
            return new Response(
                JSON.stringify({ error: "You do not have permission to manage members" }),
                { status: 403, headers: { "Content-Type": "application/json", ...corsHeaders } }
            );
        }
    }

    // 2. Validate Role
    const { data: role, error: roleError } = await supabaseAdmin
        .from("organization_roles")
        .select("id")
        .eq("id", role_id)
        .eq("organization_id", organization_id)
        .maybeSingle();

    if (roleError || !role) {
        return new Response(
            JSON.stringify({ error: "Role not found or does not belong to this org" }),
            { status: 400, headers: { "Content-Type": "application/json", ...corsHeaders } }
        );
    }

    // 3. Action Execution
    if (action === "create") {
        if (!password) {
            return new Response(JSON.stringify({ error: "Password is required for user creation" }), { status: 400, headers: { "Content-Type": "application/json", ...corsHeaders } });
        }

        // Checking if user exists. We will try to create. 
        // If it fails due to existing email, we will catch it.
        const { data: newUser, error: createUserError } = await supabaseAdmin.auth.admin.createUser({
            email,
            password,
            email_confirm: true, // Auto-confirm email so they can log in immediately
            user_metadata: { full_name: name, invited_to_org: organization_id },
        });

        if (createUserError || !newUser.user) {
            return new Response(
                JSON.stringify({ error: "Failed to create user account", detail: createUserError?.message }),
                { status: 400, headers: { "Content-Type": "application/json", ...corsHeaders } }
            );
        }

        const newUserId = newUser.user.id;

        // Wait a brief moment to ensure trigger created profile, or manually upsert profile
        await supabaseAdmin.from("profiles").upsert({
            id: newUserId,
            full_name: name,
            email: email,
        }).eq("id", newUserId);

        // Create the active member record
        const { data: newMember, error: memberError } = await supabaseAdmin
            .from("organization_members")
            .insert({
                organization_id,
                user_id: newUserId,
                role_id,
                status: "active",
            })
            .select("id, status, created_at, user_id")
            .single();

        if (memberError || !newMember) {
            return new Response(
                JSON.stringify({ error: "Failed to create member record", detail: memberError?.message }),
                { status: 500, headers: { "Content-Type": "application/json", ...corsHeaders } }
            );
        }

        return new Response(
            JSON.stringify({ member: newMember }),
            { status: 201, headers: { "Content-Type": "application/json", ...corsHeaders } }
        );
    } else if (action === "update") {
        if (!user_id || !member_id) {
            return new Response(JSON.stringify({ error: "user_id and member_id are required for update" }), { status: 400, headers: { "Content-Type": "application/json", ...corsHeaders } });
        }

        // Update Auth User credentials
        const authPayload: any = { email, user_metadata: { full_name: name } };
        if (password && password.trim() !== '') {
            authPayload.password = password;
        }

        const { error: updateUserError } = await supabaseAdmin.auth.admin.updateUserById(user_id, authPayload);

        if (updateUserError) {
            return new Response(
                JSON.stringify({ error: "Failed to update user credentials", detail: updateUserError.message }),
                { status: 400, headers: { "Content-Type": "application/json", ...corsHeaders } }
            );
        }

        // Update Profile Name and Email
        await supabaseAdmin.from("profiles").update({ full_name: name, email: email }).eq("id", user_id);

        // Update Member Role
        const { error: updateMemberError } = await supabaseAdmin
            .from("organization_members")
            .update({ role_id })
            .eq("id", member_id)
            .eq("organization_id", organization_id);

        if (updateMemberError) {
            return new Response(JSON.stringify({ error: "Failed to update member role" }), { status: 500, headers: { "Content-Type": "application/json", ...corsHeaders } });
        }

        return new Response(
            JSON.stringify({ success: true }),
            { status: 200, headers: { "Content-Type": "application/json", ...corsHeaders } }
        );
    } else if (action === "delete") {
        if (!user_id || !member_id) {
            return new Response(JSON.stringify({ error: "user_id and member_id are required for delete" }), { status: 400, headers: { "Content-Type": "application/json", ...corsHeaders } });
        }

        // Prevent self-deletion
        if (user_id === callerUserId) {
            return new Response(
                JSON.stringify({ error: "Você não pode remover a si mesmo" }),
                { status: 400, headers: { "Content-Type": "application/json", ...corsHeaders } }
            );
        }

        // Role hierarchy: lower number = higher rank
        const ROLE_HIERARCHY: Record<string, number> = {
            'master': 0,
            'administrador': 1,
            'gerente': 2,
            'vendedor': 3,
            'visualizador': 4,
        };

        // Get target member's role
        const { data: targetMember } = await supabaseAdmin
            .from("organization_members")
            .select("role_id")
            .eq("id", member_id)
            .eq("organization_id", organization_id)
            .is("deleted_at", null)
            .single();

        if (!targetMember) {
            return new Response(
                JSON.stringify({ error: "Membro não encontrado" }),
                { status: 404, headers: { "Content-Type": "application/json", ...corsHeaders } }
            );
        }

        const { data: targetRole } = await supabaseAdmin
            .from("organization_roles")
            .select("name")
            .eq("id", targetMember.role_id)
            .single();

        const targetRoleName = (targetRole?.name || '').toLowerCase();

        // Block deletion of Master users
        if (targetRoleName === 'master') {
            return new Response(
                JSON.stringify({ error: "Não é possível remover um usuário Master" }),
                { status: 403, headers: { "Content-Type": "application/json", ...corsHeaders } }
            );
        }

        // Check caller's role hierarchy (superadmin bypasses)
        if (!callerProfile?.is_superadmin) {
            const { data: callerRoleData } = await supabaseAdmin
                .from("organization_roles")
                .select("name")
                .eq("id", callerMember!.role_id)
                .single();

            const callerRoleName = (callerRoleData?.name || '').toLowerCase();
            const callerRank = ROLE_HIERARCHY[callerRoleName] ?? 99;
            const targetRank = ROLE_HIERARCHY[targetRoleName] ?? 99;

            // Can only delete roles with a LOWER rank (higher number)
            if (targetRank <= callerRank) {
                return new Response(
                    JSON.stringify({ error: "Você só pode remover membros com cargo inferior ao seu" }),
                    { status: 403, headers: { "Content-Type": "application/json", ...corsHeaders } }
                );
            }
        }

        // Soft-delete the membership
        const { error: deleteError } = await supabaseAdmin
            .from("organization_members")
            .update({ deleted_at: new Date().toISOString(), status: 'disabled' })
            .eq("id", member_id)
            .eq("organization_id", organization_id);

        if (deleteError) {
            return new Response(JSON.stringify({ error: "Failed to remove member", detail: deleteError.message }), { status: 500, headers: { "Content-Type": "application/json", ...corsHeaders } });
        }

        return new Response(
            JSON.stringify({ success: true }),
            { status: 200, headers: { "Content-Type": "application/json", ...corsHeaders } }
        );
    }

    return new Response(JSON.stringify({ error: "Invalid Action" }), { status: 400, headers: { "Content-Type": "application/json", ...corsHeaders } });
});
