import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
import { buildTemplatePayload, buildTextPayload, sendToGraphApi, type GraphApiCredentials } from './graph-api.ts';

export type DispatchKind = 'template_24h' | 'nudge_4h';

export interface DispatchInput {
  organizationId: string;
  leadId: string;
  stageEntryId: string;
  phone: string;
  kind: DispatchKind;
  templateName?: string;
  nudgeBody?: string;
}

export interface DispatchOutcome {
  kind: 'skipped_duplicate' | 'sent' | 'failed';
  wamid?: string;
  error?: unknown;
}

export async function dispatchFollowUp(
  db: SupabaseClient,
  creds: GraphApiCredentials,
  input: DispatchInput,
): Promise<DispatchOutcome> {
  const { data: inserted, error: insErr } = await db
    .from('follow_up_dispatches')
    .insert({
      organization_id: input.organizationId,
      lead_id: input.leadId,
      stage_entry_id: input.stageEntryId,
      kind: input.kind,
      status: 'pending',
    })
    .select('id')
    .maybeSingle();

  if (insErr) {
    if ((insErr as { code?: string }).code === '23505') {
      return { kind: 'skipped_duplicate' };
    }
    throw insErr;
  }
  if (!inserted) return { kind: 'skipped_duplicate' };

  const dispatchId = inserted.id;

  const payload =
    input.kind === 'template_24h'
      ? buildTemplatePayload({ to: input.phone, templateName: input.templateName!, languageCode: 'pt_BR' })
      : buildTextPayload({ to: input.phone, body: input.nudgeBody! });

  const result = await sendToGraphApi(creds, payload);

  await db
    .from('follow_up_dispatches')
    .update({
      status: result.ok ? 'sent' : 'failed',
      wamid: result.wamid ?? null,
      error: result.ok ? null : result.error ?? null,
    })
    .eq('id', dispatchId);

  if (!result.ok) return { kind: 'failed', error: result.error };

  await db.from('lead_activities').insert({
    organization_id: input.organizationId,
    lead_id: input.leadId,
    type: 'whatsapp',
    content: input.kind === 'template_24h'
      ? `[template] ${input.templateName}`
      : input.nudgeBody,
    metadata: {
      source: 'automation',
      direction: 'outbound',
      kind: input.kind,
      template_name: input.templateName ?? null,
      stage_entry_id: input.stageEntryId,
      wamid: result.wamid,
    },
  });

  return { kind: 'sent', wamid: result.wamid };
}
