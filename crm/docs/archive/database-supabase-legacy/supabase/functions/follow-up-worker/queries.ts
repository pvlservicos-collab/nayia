import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

export interface StageTargets {
  followupStageId: string;
  aboutToPayStageId: string;
  followupTemplateName: string;
  aboutToPayTemplateName: string;
}

export interface EligibleTemplate24h {
  lead_id: string;
  organization_id: string;
  phone: string;
  stage_id: string;
  stage_entry_id: string;
  template_name: string;
}

export interface EligibleNudge4h {
  lead_id: string;
  organization_id: string;
  phone: string;
  stage_id: string;
  stage_entry_id: string;
}

export async function selectTemplate24hEligible(
  db: SupabaseClient,
  orgId: string,
  targets: StageTargets,
): Promise<EligibleTemplate24h[]> {
  const { data, error } = await db.rpc('select_template_24h_eligible', {
    p_org_id: orgId,
    p_followup_stage: targets.followupStageId,
    p_about_to_pay_stage: targets.aboutToPayStageId,
    p_followup_template: targets.followupTemplateName,
    p_about_to_pay_template: targets.aboutToPayTemplateName,
  });
  if (error) throw error;
  return (data ?? []) as EligibleTemplate24h[];
}

export async function selectNudge4hEligible(
  db: SupabaseClient,
  orgId: string,
  targets: StageTargets,
): Promise<EligibleNudge4h[]> {
  const { data, error } = await db.rpc('select_nudge_4h_eligible', {
    p_org_id: orgId,
    p_followup_stage: targets.followupStageId,
    p_about_to_pay_stage: targets.aboutToPayStageId,
  });
  if (error) throw error;
  return (data ?? []) as EligibleNudge4h[];
}
