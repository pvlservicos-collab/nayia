/**
 * O CHAT DA OLX DENTRO DO CRM (Pedro, 08/10/2026): "serão 2 contas ... aba Conta proprietários e aba Conta
 * corretores ... quero responder o chat da olx pelo meu crm, enviar e receber mensagens pelo crm".
 *
 * Tudo o que fala com o banco da Nay (onde as conversas moram, schema `privado`, migração 314) e com a OLX
 * (autorização, webhook e envio). A documentação da OLX e o desenho estão em crm/docs/olx/chat-da-olx.md.
 *
 * SÓ NO SERVIDOR: aqui passam o token de cada conta e o client_secret do aplicativo. A tela usa os tipos de
 * src/lib/olxChatTipos.ts e as rotas /api/olx/*.
 */
import { randomBytes } from 'node:crypto'
import { naydb } from '@/lib/nayDisparo'
import { CONTAS_OLX, type AnuncioOlx, type ChatOlxNaLista, type ContaOlx, type EstadoDaContaOlx, type MensagemOlx, type PainelDosAnunciosOlx } from '@/lib/olxChatTipos'

const BASE = (process.env.OLX_WEBHOOK_BASE || 'https://crm.imobeasy.online').replace(/\/+$/, '')
/** Tem de ser IGUAL à URI cadastrada na OLX no registro do aplicativo. */
export const OLX_REDIRECT_URI = process.env.OLX_REDIRECT_URI || `${BASE}/api/olx/oauth`
const OLX_AUTH = 'https://auth.olx.com.br/oauth'
const OLX_APPS = 'https://apps.olx.com.br'
const ESPERA_MS = 20_000
/* Os escopos pedidos na autorização. `autoupload` entrou em 13/10 para a aba Anúncios (a lista dos anúncios publicados
   da conta); o chat só precisa de `chat`. Se a OLX recusar o escopo para o nosso aplicativo, OLX_ESCOPOS no .env
   volta para "basic_user_info chat" sem mexer no código. */
const OLX_ESCOPOS = (process.env.OLX_ESCOPOS || 'basic_user_info autoupload chat').trim()

/** Um endereço do próprio CRM, pelo domínio público (atrás do proxy, `req.url` pode trazer o endereço interno). */
export function enderecoNoCrm(caminho: string): URL {
  return new URL(caminho, BASE)
}

export function ehContaOlx(v: unknown): v is ContaOlx {
  return typeof v === 'string' && (CONTAS_OLX as readonly string[]).includes(v)
}

export function aplicativoOlx(): { clientId: string; clientSecret: string } | null {
  const clientId = (process.env.OLX_CLIENT_ID || '').trim()
  const clientSecret = (process.env.OLX_CLIENT_SECRET || '').trim()
  return clientId && clientSecret ? { clientId, clientSecret } : null
}

const iso = (v: unknown) => (v ? new Date(v as string).toISOString() : null)

/* ── o banco ─────────────────────────────────────────────────────────────── */

export async function estadoDaContaOlx(conta: ContaOlx): Promise<EstadoDaContaOlx> {
  const r = await naydb().query('SELECT crm_olx_conta_estado($1) AS e', [conta])
  const e = r.rows[0]?.e || {}
  return {
    conta,
    conectada: !!e.conectada,
    conectadaEm: iso(e.conectada_em),
    conectadaPor: e.conectada_por || null,
    olxNome: e.olx_nome || null,
    olxEmail: e.olx_email || null,
    webhookAtivo: !!e.webhook_ativo,
    webhookAtivadoEm: iso(e.webhook_ativado_em),
    webhookResposta: e.webhook_resposta || null,
    conversas: Number(e.conversas || 0),
    ultimaMensagemEm: iso(e.ultima_mensagem_em),
    aplicativoCadastrado: !!aplicativoOlx(),
  }
}

/** Garante a linha da conta e devolve o segredo do webhook dela (gerado aqui na primeira vez). */
export async function segredoDaContaOlx(conta: ContaOlx): Promise<string> {
  // 16 bytes = 32 caracteres. Com 32 bytes o endereço do webhook passava de 100 caracteres e a OLX devolvia HTTP 500
  // ("value too long for type character varying(100)", 13/10/2026, migração 362).
  const novo = randomBytes(16).toString('hex')
  const r = await naydb().query('SELECT crm_olx_conta_preparar($1, $2) AS s', [conta, novo])
  const s = r.rows[0]?.s
  if (!s) throw { status: 500, message: 'Não consegui preparar a conta da OLX no banco.' }
  return String(s)
}

/** O endereço que a OLX vai chamar para esta conta. O segredo vai no caminho: a OLX não assina a chamada. */
export function urlDoWebhookOlx(conta: ContaOlx, segredo: string): string {
  return `${BASE}/api/public/olx-chat/${conta}/${segredo}`
}

export async function receberDaOlx(conta: string, segredo: string, corpo: unknown, ip: string | null) {
  const r = await naydb().query('SELECT crm_olx_chat_receber($1, $2, $3::jsonb, $4) AS r', [conta, segredo, JSON.stringify(corpo ?? null), ip])
  return (r.rows[0]?.r || { ok: false, codigo_erro: 'falha' }) as { ok: boolean; novo?: boolean; chat?: number; de?: string; codigo_erro?: string; erro?: string }
}

export async function chatsDaContaOlx(conta: ContaOlx): Promise<ChatOlxNaLista[]> {
  const r = await naydb().query('SELECT * FROM crm_olx_chats($1, $2::int)', [conta, 500])
  return r.rows.map((l: any) => ({
    id: Number(l.id),
    listId: l.list_id || null,
    nome: l.nome || null,
    email: l.email || null,
    telefone: l.telefone || null,
    ultimaEm: iso(l.ultima_em),
    ultimaTexto: l.ultima_texto || null,
    ultimaDe: l.ultima_de || null,
    naoLidas: Number(l.nao_lidas || 0),
    criadoEm: iso(l.criado_em) || new Date().toISOString(),
    mensagens: Number(l.mensagens || 0),
  }))
}

export async function mensagensDoChatOlx(conta: ContaOlx, chat: number): Promise<MensagemOlx[]> {
  const r = await naydb().query('SELECT * FROM crm_olx_chat_mensagens($1, $2::bigint)', [conta, chat])
  return r.rows.map((l: any) => ({
    id: Number(l.id),
    de: l.de === 'nos' ? 'nos' : l.de === 'sistema' ? 'sistema' : 'comprador',
    texto: String(l.texto || ''),
    quando: iso(l.quando) || new Date().toISOString(),
    enviadaPor: l.enviada_por || null,
  }))
}

export async function marcarLidoOlx(conta: ContaOlx, chat: number): Promise<void> {
  await naydb().query('SELECT crm_olx_chat_lido($1, $2::bigint)', [conta, chat])
}

async function tokenDaContaOlx(conta: ContaOlx): Promise<string | null> {
  const r = await naydb().query('SELECT crm_olx_conta_token($1) AS t', [conta])
  return r.rows[0]?.t || null
}

/* ── a OLX ───────────────────────────────────────────────────────────────── */

/* `limite`: quanto da resposta guardar. O padrão (2.000) serve às respostas curtas; a lista de anúncios é longa, e
   cortada no meio deixava de ser JSON (a aba Anúncios dizia "a OLX não entregou a lista" com HTTP 200, 13/10). */
async function chamar(url: string, init: RequestInit, limite = 2000): Promise<{ status: number; texto: string }> {
  const controle = new AbortController()
  const prazo = setTimeout(() => controle.abort(), ESPERA_MS)
  try {
    const r = await fetch(url, { ...init, signal: controle.signal, cache: 'no-store' })
    return { status: r.status, texto: (await r.text().catch(() => '')).slice(0, limite) }
  } catch (e: any) {
    throw { status: 502, message: e?.name === 'AbortError' ? 'A OLX não respondeu a tempo.' : `Não consegui falar com a OLX (${e?.message || 'erro de rede'}).` }
  } finally {
    clearTimeout(prazo)
  }
}

/** A página da OLX em que o dono da conta autoriza o nosso aplicativo. */
export function urlDeAutorizacaoOlx(estado: string): string {
  const app = aplicativoOlx()
  if (!app) throw { status: 400, message: 'Falta cadastrar o aplicativo da OLX no servidor (OLX_CLIENT_ID e OLX_CLIENT_SECRET).' }
  const q = new URLSearchParams({
    client_id: app.clientId, redirect_uri: OLX_REDIRECT_URI, response_type: 'code', scope: OLX_ESCOPOS, state: estado,
  })
  return `${OLX_AUTH}?${q.toString()}`
}

/** Troca o código que voltou da OLX pelo token da conta. */
export async function tokenPeloCodigoOlx(codigo: string): Promise<string> {
  const app = aplicativoOlx()
  if (!app) throw { status: 400, message: 'Falta cadastrar o aplicativo da OLX no servidor (OLX_CLIENT_ID e OLX_CLIENT_SECRET).' }
  const corpo = new URLSearchParams({
    code: codigo, client_id: app.clientId, client_secret: app.clientSecret, redirect_uri: OLX_REDIRECT_URI, grant_type: 'authorization_code',
  })
  const r = await chamar(`${OLX_AUTH}/token`, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: corpo.toString() })
  let token = ''
  try { token = String(JSON.parse(r.texto)?.access_token || '') } catch { /* cai no erro abaixo */ }
  // a resposta de erro da OLX pode repetir o que mandamos: não vai inteira para a tela nem para o log
  if (r.status !== 200 || !token) throw { status: 502, message: `A OLX não entregou o token (HTTP ${r.status}).` }
  return token
}

/** Quem é a conta que autorizou (para a equipe conferir que ligou a conta certa). Falhar aqui não impede nada. */
export async function quemEAContaOlx(token: string): Promise<{ nome: string | null; email: string | null }> {
  try {
    const r = await chamar(`${OLX_APPS}/oauth_api/basic_user_info`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', 'User-Agent': 'Mozilla/5.0' }, body: JSON.stringify({ access_token: token }),
    })
    const j = JSON.parse(r.texto)
    return { nome: j?.user_name || j?.name || null, email: j?.user_email || j?.email || null }
  } catch {
    return { nome: null, email: null }
  }
}

export async function gravarConexaoOlx(conta: ContaOlx, token: string, quem: string, nome: string | null, email: string | null) {
  await naydb().query('SELECT crm_olx_conta_conectar($1, $2, $3, $4, $5)', [conta, token, quem, nome, email])
}

/** Liga (ou atualiza) o webhook do chat desta conta na OLX. Devolve o que a OLX respondeu, em uma linha. */
export async function ligarWebhookOlx(conta: ContaOlx): Promise<{ ok: boolean; resposta: string }> {
  const token = await tokenDaContaOlx(conta)
  if (!token) throw { status: 400, message: 'Esta conta ainda não foi conectada à OLX.' }
  const url = urlDoWebhookOlx(conta, await segredoDaContaOlx(conta))
  const r = await chamar(`${OLX_APPS}/autoservice/v1/chat`, {
    method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ webhook: url }),
  })
  const ok = r.status === 200 || r.status === 201
  const resposta = `HTTP ${r.status}${ok ? (r.status === 201 ? ' (ativado)' : ' (atualizado)') : r.status === 401 ? ' (token inválido)' : ''}`
  await naydb().query('SELECT crm_olx_conta_webhook($1, $2, $3)', [conta, ok, resposta])
  return { ok, resposta }
}

/** Manda a nossa resposta no chat da OLX e, se ela aceitar, grava. */
export async function responderNoChatOlx(conta: ContaOlx, chat: number, texto: string, quem: string): Promise<{ messageId: string }> {
  const token = await tokenDaContaOlx(conta)
  if (!token) throw { status: 400, message: 'Esta conta ainda não foi conectada à OLX: não dá para responder por aqui.' }
  const r0 = await naydb().query('SELECT crm_olx_chat_id_da_olx($1, $2::bigint) AS c', [conta, chat])
  const chatId = r0.rows[0]?.c
  if (!chatId) throw { status: 404, message: 'Não achei essa conversa.' }
  const messageId = `crm-${Date.now()}-${randomBytes(6).toString('hex')}`
  const r = await chamar(`${OLX_APPS}/autoservice/v1/chat/send`, {
    method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ textMessage: texto, messageId, chatId }),
  })
  if (r.status !== 200) {
    const porque = r.status === 401 ? 'o token da conta não vale mais: conecte a conta de novo'
      : r.status === 400 ? 'a OLX recusou (mensagem inválida ou conta sem a integração de chat)'
      : `a OLX respondeu HTTP ${r.status}`
    throw { status: 502, message: `A mensagem NÃO foi enviada: ${porque}.` }
  }
  await naydb().query('SELECT crm_olx_chat_enviada($1, $2::bigint, $3, $4, $5)', [conta, chat, messageId, texto, quem])
  return { messageId }
}

/* ── os anúncios da conta (aba Anúncios, 13/10) ─────────────────────────────── */

/**
 * Os anúncios da conta: o que a OLX lista como publicado (escopo `autoupload`) somado ao que conhecemos pelas
 * conversas (cada conversa traz o `listId` do anúncio). A lista da OLX NUNCA foi exercitada antes de a conta ser
 * conectada: se ela falhar ou vier em formato inesperado, a tela mostra o que a OLX respondeu e continua com os
 * anúncios das conversas.
 */
export async function anunciosDaContaOlx(conta: ContaOlx): Promise<{ anuncios: AnuncioOlx[]; daOlx: 'ok' | 'sem_conta' | 'falhou'; aviso: string | null }> {
  const porId = new Map<string, AnuncioOlx>()
  for (const c of await chatsDaContaOlx(conta)) {
    if (!c.listId) continue
    const a = porId.get(c.listId) || { listId: c.listId, titulo: null, situacao: null, conversas: 0, naoLidas: 0, ultimaEm: null, daOlx: false }
    a.conversas += 1
    a.naoLidas += c.naoLidas
    if (c.ultimaEm && (!a.ultimaEm || c.ultimaEm > a.ultimaEm)) a.ultimaEm = c.ultimaEm
    porId.set(c.listId, a)
  }
  let daOlx: 'ok' | 'sem_conta' | 'falhou' = 'sem_conta'
  let aviso: string | null = null
  const token = await tokenDaContaOlx(conta)
  if (token) {
    try {
      const r = await chamar(`${OLX_APPS}/autoupload/v1/published`, { method: 'GET', headers: { Authorization: `Bearer ${token}`, 'User-Agent': 'Mozilla/5.0' } }, 5_000_000)
      let j: any = null
      try { j = JSON.parse(r.texto) } catch { /* não é JSON */ }
      const lista: any[] = Array.isArray(j) ? j : Array.isArray(j?.data) ? j.data : Array.isArray(j?.ads) ? j.ads : []
      if (r.status === 200 && (Array.isArray(j) || lista.length || j?.data || j?.ads)) {
        daOlx = 'ok'
        for (const x of lista) {
          const id = String(x?.list_id ?? x?.listId ?? x?.id ?? '').trim()
          if (!id) continue
          const a = porId.get(id) || { listId: id, titulo: null, situacao: null, conversas: 0, naoLidas: 0, ultimaEm: null, daOlx: true }
          a.daOlx = true
          a.titulo = String(x?.subject ?? x?.title ?? '').trim() || a.titulo
          a.situacao = String(x?.status ?? x?.state ?? '').trim() || a.situacao
          porId.set(id, a)
        }
      } else {
        daOlx = 'falhou'
        aviso = r.status === 401 ? 'A OLX não aceitou o token para listar os anúncios: conecte a conta de novo (a autorização precisa incluir os anúncios).'
          : r.status === 403 ? 'A OLX não liberou a lista de anúncios para esta conta (HTTP 403).'
          : `A OLX não entregou a lista de anúncios (HTTP ${r.status}).`
      }
    } catch (e: any) {
      daOlx = 'falhou'
      aviso = e?.message || 'Não consegui ler os anúncios na OLX.'
    }
  }
  const anuncios = [...porId.values()].sort((x, y) => (y.ultimaEm || '').localeCompare(x.ultimaEm || '') || Number(y.daOlx) - Number(x.daOlx) || x.listId.localeCompare(y.listId))
  return { anuncios, daOlx, aviso }
}

/** O que a aba Informações mostra do nosso lado (nada de segredo: só os endereços e os escopos). */
export function informacoesDoAplicativoOlx() {
  return { redirectUri: OLX_REDIRECT_URI, escopos: OLX_ESCOPOS, cadastrado: !!aplicativoOlx() }
}

/* ── a publicação automática (13/10, migração 364) ──────────────────────────────
   Quem publica é o serviço nay-olx, no servidor; o banco decide o que sobe. A tela só LÊ o painel e muda as chaves
   (ligar/desligar, a conta, o teto, mostrar o telefone). */

export async function painelDosAnunciosOlx(): Promise<PainelDosAnunciosOlx> {
  const r = await naydb().query('SELECT crm_olx_anuncios_painel() AS p')
  return r.rows[0]?.p as PainelDosAnunciosOlx
}

export async function gravarChaveOlx(chave: string, valor: string, quem: string): Promise<{ ok: boolean; erro?: string }> {
  const r = await naydb().query('SELECT crm_olx_config_gravar($1, $2, $3) AS r', [chave, valor, quem])
  return (r.rows[0]?.r || { ok: false, erro: 'O banco não respondeu.' }) as { ok: boolean; erro?: string }
}

/* ── as métricas (14/10, migração 369) ──────────────────────────────────────────── */

export interface LinhaDeMetricaOlx {
  list_id: string; ad_id: string | null; codigo: number | null; negocio: string | null; conta: string; situacao: string | null
  url: string | null; titulo: string | null; preco: number | null; publicado_em: string | null; dias_no_ar: number | null
  conversas: number; recebidas: number; enviadas: number; da_nay: number; sem_resposta: number; recebidas_7d: number
  ultima_do_cliente: string | null; leads: number; leads_whatsapp: number; leads_telefone: number; leads_chat: number
  leads_outros: number; ultimo_lead: string | null; imovel_status: string | null; bairro: string | null; tipo: string | null
}

export async function metricasOlx(): Promise<{ linhas: LinhaDeMetricaOlx[]; leads_ligados: boolean; atualizado_em: string }> {
  const r = await naydb().query('SELECT crm_olx_metricas() AS m')
  return r.rows[0]?.m || { linhas: [], leads_ligados: false, atualizado_em: new Date().toISOString() }
}

/** O saldo do plano profissional da conta (quantos anúncios o plano dá, usados e livres). Null sem conta ou sem plano. */
export async function saldoDoPlanoOlx(conta: ContaOlx): Promise<{ nome: string; total: number; usados: number; livres: number; renova_em: string | null } | null> {
  const token = await tokenDaContaOlx(conta)
  if (!token) return null
  const r = await chamar(`${OLX_APPS}/autoupload/balance`, { method: 'GET', headers: { Authorization: `Bearer ${token}`, 'User-Agent': 'Mozilla/5.0' } })
  if (r.status !== 200) return null
  try {
    const j = JSON.parse(r.texto)
    return { nome: String(j?.name || 'Plano da OLX'), total: Number(j?.ads?.total || 0), usados: Number(j?.ads?.performed || 0),
             livres: Number(j?.ads?.available || 0), renova_em: j?.next_renew_date || null }
  } catch { return null }
}
