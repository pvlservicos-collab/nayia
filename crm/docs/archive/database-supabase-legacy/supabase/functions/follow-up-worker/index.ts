import { serve } from 'https://deno.land/std@0.208.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
import { isWithinBusinessHours } from './business-hours.ts';
import { selectTemplate24hEligible, selectNudge4hEligible } from './queries.ts';
import { dispatchFollowUp } from './dispatch.ts';
import type { GraphApiCredentials } from './graph-api.ts';

interface IntegrationConfig {
  waba_id: string;
  phone_number_id: string;
  graph_api_version: string;
  templates: Record<string, string>;
}

const FOLLOWUP_STAGE = 'd3d3031f-bc4b-44df-bd83-b1f07d7fbf85';
const ABOUT_TO_PAY_STAGE = '0a58795e-31c1-4cdd-9cfa-408412d5ce7a';
const NUDGE_BODY = 'Oi, podemos continuar?';

serve(async (req) => {
  const secret = Deno.env.get('FOLLOW_UP_CRON_SECRET');
  if (!secret) return new Response('server misconfigured', { status: 500 });
  if (req.headers.get('x-cron-secret') !== secret) {
    return new Response('unauthorized', { status: 401 });
  }

  const db = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const { data: integrations, error: intErr } = await db
    .from('integrations')
    .select('id, organization_id, config')
    .eq('type', 'whatsapp_cloud_official')
    .eq('status', 'active')
    .is('deleted_at', null);

  if (intErr) {
    console.error(JSON.stringify({ level: 'error', stage: 'load_integrations', error: intErr.message }));
    return new Response('db error', { status: 500 });
  }

  const summary = { orgs: 0, sent: 0, failed: 0, skipped: 0 };

  for (const integ of integrations ?? []) {
    const cfg = integ.config as IntegrationConfig;
    const orgId = integ.organization_id as string;

    const { data: hoursRow } = await db
      .from('automation_settings')
      .select('variables, is_enabled')
      .eq('organization_id', orgId)
      .eq('key', 'follow_up_business_hours')
      .maybeSingle();

    const hours = (hoursRow?.variables as { start_hour: number; end_hour: number; tz: string } | undefined) ??
      { start_hour: 8, end_hour: 18, tz: 'America/Manaus' };

    if (hoursRow && hoursRow.is_enabled === false) continue;
    if (!isWithinBusinessHours(new Date(), hours)) continue;

    summary.orgs++;

    const { data: tokenRaw, error: tokErr } = await db.rpc('get_integration_secret_service', {
      p_integration_id: integ.id,
      p_org_id: orgId,
    });
    if (tokErr || !tokenRaw) {
      console.error(JSON.stringify({ level: 'error', stage: 'vault', org: orgId, error: tokErr?.message }));
      continue;
    }

    // Vault stores the secret as JSON `{"system_token":"..."}` (see setup script).
    let systemToken: string;
    try {
      const parsed = JSON.parse(tokenRaw as string);
      systemToken = parsed.system_token;
      if (!systemToken) throw new Error('system_token field missing');
    } catch (e) {
      console.error(JSON.stringify({ level: 'error', stage: 'vault_parse', org: orgId, error: (e as Error).message }));
      continue;
    }

    const creds: GraphApiCredentials = {
      phoneNumberId: cfg.phone_number_id,
      systemToken,
      apiVersion: cfg.graph_api_version,
    };

    const t24 = await selectTemplate24hEligible(db, orgId, {
      followupStageId: FOLLOWUP_STAGE,
      aboutToPayStageId: ABOUT_TO_PAY_STAGE,
      followupTemplateName: cfg.templates[FOLLOWUP_STAGE],
      aboutToPayTemplateName: cfg.templates[ABOUT_TO_PAY_STAGE],
    });
    for (const lead of t24) {
      const out = await dispatchFollowUp(db, creds, {
        organizationId: orgId,
        leadId: lead.lead_id,
        stageEntryId: lead.stage_entry_id,
        phone: lead.phone,
        kind: 'template_24h',
        templateName: lead.template_name,
      });
      summary[out.kind === 'sent' ? 'sent' : out.kind === 'failed' ? 'failed' : 'skipped']++;
      await new Promise((r) => setTimeout(r, 250));
    }

    const n4 = await selectNudge4hEligible(db, orgId, {
      followupStageId: FOLLOWUP_STAGE,
      aboutToPayStageId: ABOUT_TO_PAY_STAGE,
      followupTemplateName: cfg.templates[FOLLOWUP_STAGE],
      aboutToPayTemplateName: cfg.templates[ABOUT_TO_PAY_STAGE],
    });
    for (const lead of n4) {
      const out = await dispatchFollowUp(db, creds, {
        organizationId: orgId,
        leadId: lead.lead_id,
        stageEntryId: lead.stage_entry_id,
        phone: lead.phone,
        kind: 'nudge_4h',
        nudgeBody: NUDGE_BODY,
      });
      summary[out.kind === 'sent' ? 'sent' : out.kind === 'failed' ? 'failed' : 'skipped']++;
      await new Promise((r) => setTimeout(r, 250));
    }
  }

  console.log(JSON.stringify({ level: 'info', stage: 'tick_done', ...summary }));
  return new Response(JSON.stringify(summary), { status: 200, headers: { 'content-type': 'application/json' } });
});
