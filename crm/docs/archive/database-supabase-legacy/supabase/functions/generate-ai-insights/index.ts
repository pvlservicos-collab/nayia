import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import Anthropic from "npm:@anthropic-ai/sdk";

interface InsightPayload {
  lead_id: string;
  organization_id: string;
}

interface AiResponse {
  summary: string;
  interest_level: string;
  next_action: string;
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

  let payload: InsightPayload;
  try {
    payload = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON body" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const { lead_id, organization_id } = payload;
  if (!lead_id || !organization_id) {
    return new Response(
      JSON.stringify({ error: "lead_id and organization_id are required" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  // Verifica que caller é membro ativo via RLS
  const supabaseUser = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } }
  );

  const { data: callerMember } = await supabaseUser
    .from("organization_members")
    .select("id")
    .eq("organization_id", organization_id)
    .eq("status", "active")
    .is("deleted_at", null)
    .maybeSingle();

  if (!callerMember) {
    return new Response(
      JSON.stringify({ error: "You are not an active member of this organization" }),
      { status: 403, headers: { "Content-Type": "application/json" } }
    );
  }

  // Busca dados do lead
  const { data: lead, error: leadError } = await supabaseAdmin
    .from("leads")
    .select("id, title, email, phone, custom_attributes, stage_id, owner_member_id, created_at")
    .eq("id", lead_id)
    .eq("organization_id", organization_id)
    .is("deleted_at", null)
    .single();

  if (leadError || !lead) {
    return new Response(
      JSON.stringify({ error: "Lead not found" }),
      { status: 404, headers: { "Content-Type": "application/json" } }
    );
  }

  // Busca atividades recentes
  const { data: activities } = await supabaseAdmin
    .from("lead_activities")
    .select("type, content, created_at")
    .eq("lead_id", lead_id)
    .eq("organization_id", organization_id)
    .order("created_at", { ascending: false })
    .limit(10);

  // Monta contexto para a IA
  const contextLines: string[] = [
    `Lead: ${lead.title}`,
    lead.email ? `Email: ${lead.email}` : "",
    lead.phone ? `Telefone: ${lead.phone}` : "",
    Object.keys(lead.custom_attributes || {}).length > 0
      ? `Atributos customizados: ${JSON.stringify(lead.custom_attributes)}`
      : "",
    activities && activities.length > 0
      ? `Atividades recentes:\n${activities
          .map((a) => `  - [${a.type}] ${a.content ?? "(sem conteúdo)"}`)
          .join("\n")}`
      : "Sem atividades registradas.",
  ];

  const leadContext = contextLines.filter(Boolean).join("\n");

  // Chama a API da Anthropic
  const anthropic = new Anthropic({
    apiKey: Deno.env.get("ANTHROPIC_API_KEY")!,
  });

  let aiResponse: AiResponse;
  try {
    const message = await anthropic.messages.create({
      model: "claude-haiku-4-5-20251001",
      max_tokens: 512,
      messages: [
        {
          role: "user",
          content: `Analise este lead de CRM e retorne um JSON com exatamente 3 campos:
- "summary": resumo em 2-3 frases do perfil e situação atual do lead
- "interest_level": nível de interesse ("high", "medium" ou "low")
- "next_action": próxima ação recomendada em até 10 palavras

Retorne APENAS o JSON, sem texto adicional, sem markdown, sem explicações.

Dados do lead:
${leadContext}`,
        },
      ],
    });

    const text = message.content[0].type === "text" ? message.content[0].text.trim() : "{}";
    aiResponse = JSON.parse(text) as AiResponse;
  } catch (err) {
    return new Response(
      JSON.stringify({ error: "AI generation failed", detail: String(err) }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  // Atualiza os flags de IA na tabela leads
  await supabaseAdmin
    .from("leads")
    .update({
      ai_interest_level: aiResponse.interest_level,
      ai_next_action_short: aiResponse.next_action,
    })
    .eq("id", lead_id)
    .eq("organization_id", organization_id);

  // Upsert em lead_ai_insights
  const { data: insight, error: insightError } = await supabaseAdmin
    .from("lead_ai_insights")
    .upsert(
      {
        organization_id,
        lead_id,
        ai_summary: aiResponse.summary,
        ai_metadata: {
          model: "claude-haiku-4-5-20251001",
          generated_at: new Date().toISOString(),
          interest_level: aiResponse.interest_level,
          next_action: aiResponse.next_action,
        },
        updated_at: new Date().toISOString(),
      },
      { onConflict: "organization_id,lead_id" }
    )
    .select("id, ai_summary, updated_at")
    .single();

  if (insightError) {
    return new Response(
      JSON.stringify({ error: "Failed to save insights", detail: insightError.message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  return new Response(
    JSON.stringify({
      lead_id,
      insight_id: insight?.id,
      ai_summary: aiResponse.summary,
      ai_interest_level: aiResponse.interest_level,
      ai_next_action_short: aiResponse.next_action,
      updated_at: insight?.updated_at,
    }),
    { status: 200, headers: { "Content-Type": "application/json" } }
  );
});
