export interface TemplateSendInput {
  to: string;
  templateName: string;
  languageCode: string;
}

export interface TextSendInput {
  to: string;
  body: string;
}

export interface GraphApiCredentials {
  phoneNumberId: string;
  systemToken: string;
  apiVersion: string;
}

export interface GraphApiResult {
  ok: boolean;
  wamid?: string;
  status: number;
  error?: { code?: number; message?: string; subcode?: number; details?: unknown };
}

function normalizePhone(to: string): string {
  return to.startsWith('+') ? to.slice(1) : to;
}

export function buildTemplatePayload(input: TemplateSendInput) {
  return {
    messaging_product: 'whatsapp',
    to: normalizePhone(input.to),
    type: 'template',
    template: { name: input.templateName, language: { code: input.languageCode } },
  };
}

export function buildTextPayload(input: TextSendInput) {
  return {
    messaging_product: 'whatsapp',
    to: normalizePhone(input.to),
    type: 'text',
    text: { body: input.body },
  };
}

export async function sendToGraphApi(
  creds: GraphApiCredentials,
  payload: Record<string, unknown>,
): Promise<GraphApiResult> {
  const url = `https://graph.facebook.com/${creds.apiVersion}/${creds.phoneNumberId}/messages`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${creds.systemToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) {
    return {
      ok: false,
      status: res.status,
      error: {
        code: body?.error?.code,
        message: body?.error?.message,
        subcode: body?.error?.error_subcode,
        details: body?.error,
      },
    };
  }
  const wamid = body?.messages?.[0]?.id;
  return { ok: true, status: res.status, wamid };
}
