/**
 * Os templates da API oficial do WhatsApp (Meta), lidos e criados de dentro do
 * CRM.
 *
 * Tel, 26/09/2026: "coloca la no crm nas configurações os templates todos que
 * temos da api oficial para eu acompanhar status se ja aprovou e cadastrar
 * novos por la".
 *
 * A LISTA NÃO FICA NO NOSSO BANCO, de propósito. Quem decide se um template
 * está aprovado é a Meta, e ela muda isso sozinha (aprova, reprova, pausa por
 * qualidade). Uma cópia nossa envelheceria calada e mostraria "aprovado" para
 * algo que a Meta já derrubou. Então a tela lê da Graph API na hora.
 *
 * DE ONDE VEM A CREDENCIAL, na ordem:
 *   1. a integração `whatsapp_cloud_official` do CRM (config + integration_secrets)
 *      -- é onde a tela de Integrações grava, e é o lugar certo;
 *   2. as variáveis de ambiente META_TOKEN / META_WABA_ID, para o caso de a
 *      integração ainda não ter sido cadastrada.
 * Se nenhuma das duas existir, a tela diz o que falta em vez de dar erro seco.
 */
import { and, eq } from 'drizzle-orm'
import { db } from './db'
import { integrations, integrationSecrets } from './schema'

export interface CredencialMeta {
  token: string
  wabaId: string
  phoneNumberId: string | null
  versao: string
  /** de onde saiu — a tela mostra isso para quem for depurar */
  fonte: 'integração do CRM' | 'variável de ambiente'
}

export async function credencialMeta(organizationId: string): Promise<CredencialMeta | null> {
  const [linha] = await db
    .select({ config: integrations.config, secret: integrationSecrets.secret })
    .from(integrations)
    .leftJoin(integrationSecrets, eq(integrationSecrets.integrationId, integrations.id))
    .where(and(
      eq(integrations.organizationId, organizationId),
      eq(integrations.type, 'whatsapp_cloud_official'),
    ))
    .limit(1)

  const config = (linha?.config || {}) as Record<string, any>
  const secret = (linha?.secret || {}) as Record<string, any>
  const doBanco = secret.system_token && config.waba_id
  if (doBanco) {
    return {
      token: String(secret.system_token),
      wabaId: String(config.waba_id),
      phoneNumberId: config.phone_number_id ? String(config.phone_number_id) : null,
      versao: String(config.graph_api_version || 'v23.0'),
      fonte: 'integração do CRM',
    }
  }

  const token = process.env.META_TOKEN
  const wabaId = process.env.META_WABA_ID
  if (token && wabaId) {
    return {
      token,
      wabaId,
      phoneNumberId: process.env.META_PHONE_NUMBER_ID || config.phone_number_id || null,
      versao: process.env.META_GRAPH_VERSION || 'v23.0',
      fonte: 'variável de ambiente',
    }
  }
  return null
}

/** Uma chamada à Graph API. Devolve o corpo já em objeto, com o erro da Meta
 *  passado adiante como texto -- a mensagem dela é bem mais útil que um 500. */
export async function graph(
  cred: CredencialMeta,
  caminho: string,
  init?: { method?: string; body?: unknown },
): Promise<any> {
  const url = `https://graph.facebook.com/${cred.versao}/${caminho}`
  const res = await fetch(url, {
    method: init?.method || 'GET',
    headers: {
      Authorization: `Bearer ${cred.token}`,
      ...(init?.body ? { 'Content-Type': 'application/json' } : {}),
    },
    body: init?.body ? JSON.stringify(init.body) : undefined,
    cache: 'no-store',
  })
  const texto = await res.text()
  let corpo: any = null
  try { corpo = texto ? JSON.parse(texto) : null } catch { corpo = { raw: texto } }
  if (!res.ok) {
    const msg = corpo?.error?.error_user_msg || corpo?.error?.message || `Meta respondeu ${res.status}`
    throw { status: res.status, message: msg, detalhe: corpo?.error || null }
  }
  return corpo
}

/** O texto do corpo do template, para a tela mostrar sem o usuário abrir nada. */
export function corpoDoTemplate(componentes: any[]): string {
  const body = (componentes || []).find((c) => c?.type === 'BODY')
  return body?.text || ''
}

/** Quantas variáveis o template pede -- serve para o envio de teste saber
 *  quantos valores precisa inventar. Aceita {{1}} e {{nome}}. */
export function variaveisDoTemplate(componentes: any[]): string[] {
  const achadas: string[] = []
  for (const c of componentes || []) {
    const texto: string = c?.text || ''
    for (const m of texto.matchAll(/\{\{\s*([^}\s]+)\s*\}\}/g)) {
      if (!achadas.includes(m[1])) achadas.push(m[1])
    }
  }
  return achadas
}
