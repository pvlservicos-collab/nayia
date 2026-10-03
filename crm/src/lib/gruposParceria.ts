/**
 * OS GRUPOS DO NÚMERO DA PARCERIA (Pedro, 03/10/2026: "preciso criar um painel com os grupos... ver,
 * editar, mandar msg, ler, tirar dados").
 *
 * O que a Z-API deixa, medido em 03/10:
 *   - VER: a lista dos grupos (/groups) e os dados de cada um (/group-metadata): participantes com
 *     telefone e quem é admin, descrição, configurações. A Z-API NÃO dá o nome de quem está no grupo:
 *     o nome vem do banco da Nay (corretores e contatos, `crm_grupo_pessoas`).
 *   - EDITAR: nome, descrição, configurações, adicionar/remover participante, promover/rebaixar admin.
 *     Só funciona onde o número da Parceria é ADMIN (5 de 27 grupos em 03/10). Todas por POST
 *     (os caminhos foram conferidos com um grupo que não existe, sem mexer em nada).
 *   - MANDAR: o mesmo send-text de sempre, com o id do grupo.
 *   - LER: a Z-API não entrega histórico ("Does not work in multi device version"). As mensagens vêm
 *     de `privado.grupo_conversa`, que guarda o que chega pelo webhook a partir do dia em que a guarda
 *     foi ligada (migração 277).
 *
 * ATENÇÃO: a Z-API responde "ok" até para remover alguém de um grupo que não existe. Toda edição relê o
 * grupo depois, e quem diz se deu certo é o grupo relido, não a resposta dela.
 */
import { chamar, getZapiCredentials, sendZapiMessage, type ZapiCredentials } from '@/lib/zapi'
import { naydb } from '@/lib/nayDisparo'

export interface CasaDoGrupo {
  disparo?: boolean            // o publicador manda imóvel neste grupo
  apelido?: string
  limite_dia?: number
  corretores?: boolean         // os membros viram corretores que a Nay atende
  mensagens?: number           // mensagens guardadas
  ultima_mensagem?: string
}

export interface GrupoNaLista {
  id: string
  nome: string
  naoLidas: number
  silenciado: boolean
  arquivado: boolean
  ultimaEm: number | null      // ms
  participantes: number | null
  souAdmin: boolean | null
  casa: CasaDoGrupo
}

export interface Participante {
  telefone: string
  lid: string | null
  admin: boolean
  dono: boolean
  nome: string | null
  corretor: boolean
  falouComANay: boolean
}

export interface DadosDoGrupo {
  id: string
  nome: string
  descricao: string | null
  criadoEm: number | null
  dono: string | null
  souAdmin: boolean
  config: { soAdminMandaMensagem: boolean; soAdminEdita: boolean; soAdminAdiciona: boolean; aprovacaoParaEntrar: boolean }
  linkDeConvite: string | null
  participantes: Participante[]
  casa: CasaDoGrupo
}

const sim = (v: unknown) => v === true || v === 'true' || v === '1' || v === 1

/* ── o número da Parceria (para saber se ele é admin) ── */
let meuNumero: { valor: string; em: number } | null = null
async function numeroDaParceria(creds: ZapiCredentials): Promise<string> {
  if (meuNumero && Date.now() - meuNumero.em < 3_600_000) return meuNumero.valor
  const d = await chamar(creds, 'device', { method: 'GET' }, 'Não consegui ler o número da Parceria')
  meuNumero = { valor: String(d?.phone || '').replace(/\D/g, ''), em: Date.now() }
  return meuNumero.valor
}
/** O mesmo número, com ou sem o 9 (o grupo guarda como o WhatsApp guardou). */
function mesmoNumero(a: string, b: string): boolean {
  const x = a.replace(/\D/g, ''), y = b.replace(/\D/g, '')
  if (!x || !y) return false
  return x === y || x.slice(-8) === y.slice(-8)
}

/* ── metadados: uma leitura por grupo, guardada 3 minutos (27 grupos na lista) ── */
const cache = new Map<string, { em: number; meta: any }>()
async function metadados(creds: ZapiCredentials, id: string, fresco = false): Promise<any> {
  const c = cache.get(id)
  if (!fresco && c && Date.now() - c.em < 180_000) return c.meta
  const meta = await chamar(creds, `group-metadata/${encodeURIComponent(id)}`, { method: 'GET' }, 'Não consegui ler o grupo')
  cache.set(id, { em: Date.now(), meta })
  return meta
}

async function casaDosGrupos(): Promise<Record<string, CasaDoGrupo>> {
  try {
    const r = await naydb().query('SELECT crm_grupos_conhecidos() AS j')
    return r.rows[0]?.j || {}
  } catch (e) {
    console.warn('[grupos] o banco da Nay não respondeu:', (e as Error)?.message)
    return {}
  }
}

/** Faz `fn` em cada item, no máximo `n` de cada vez (27 grupos: não dá para pedir tudo de uma vez à Z-API). */
async function aos_poucos<T, R>(itens: T[], n: number, fn: (x: T) => Promise<R>): Promise<R[]> {
  const saida: R[] = new Array(itens.length)
  let i = 0
  await Promise.all(Array.from({ length: Math.min(n, itens.length) }, async () => {
    while (i < itens.length) { const k = i++; saida[k] = await fn(itens[k]) }
  }))
  return saida
}

export async function listarGrupos(organizationId: string): Promise<{ grupos: GrupoNaLista[]; meuNumero: string }> {
  const creds = await getZapiCredentials(organizationId)
  const brutos: any[] = []
  for (let pagina = 1; pagina <= 20; pagina++) {
    const r = await chamar(creds, `groups?page=${pagina}&pageSize=100`, { method: 'GET' }, 'Não consegui listar os grupos')
    if (!Array.isArray(r) || !r.length) break
    brutos.push(...r)
    if (r.length < 100) break
  }
  const [eu, casa] = await Promise.all([numeroDaParceria(creds), casaDosGrupos()])
  const metas = await aos_poucos(brutos, 6, (g) => metadados(creds, String(g.phone)).catch(() => null))
  const grupos = brutos.map((g, k): GrupoNaLista => {
    const parts: any[] = metas[k]?.participants || []
    const id = String(g.phone)
    return {
      id,
      nome: String(g.name || metas[k]?.subject || id),
      naoLidas: Number(g.messagesUnread || g.unread || 0) || 0,
      silenciado: sim(g.isMuted),
      arquivado: sim(g.archived),
      ultimaEm: Number(g.lastMessageTime) || null,
      participantes: metas[k] ? parts.length : null,
      souAdmin: metas[k] ? parts.some((p) => mesmoNumero(String(p.phone || ''), eu) && (p.isAdmin || p.isSuperAdmin)) : null,
      casa: casa[id] || {},
    }
  })
  grupos.sort((a, b) => (b.ultimaEm || 0) - (a.ultimaEm || 0))
  return { grupos, meuNumero: eu }
}

export async function dadosDoGrupo(organizationId: string, id: string, fresco = false): Promise<DadosDoGrupo> {
  const creds = await getZapiCredentials(organizationId)
  const [meta, eu, casa] = await Promise.all([metadados(creds, id, fresco), numeroDaParceria(creds), casaDosGrupos()])
  if (!meta || meta.success === false || !Array.isArray(meta.participants)) {
    throw { status: 404, message: 'Não consegui ler esse grupo (o número da Parceria ainda está nele?).' }
  }
  const parts: any[] = meta.participants
  const telefones = parts.map((p) => String(p.phone || '').replace(/\D/g, '')).filter(Boolean)
  let pessoas: Record<string, any> = {}
  try {
    pessoas = (await naydb().query('SELECT crm_grupo_pessoas($1::text[]) AS j', [telefones])).rows[0]?.j || {}
  } catch (e) {
    console.warn('[grupos] sem os nomes do banco da Nay:', (e as Error)?.message)
  }
  const participantes: Participante[] = parts.map((p) => {
    const tel = String(p.phone || '').replace(/\D/g, '')
    const quem = pessoas[tel] || {}
    return {
      telefone: tel, lid: p.lid ? String(p.lid) : null,
      admin: !!(p.isAdmin || p.isSuperAdmin), dono: !!p.isSuperAdmin,
      nome: quem.nome || null, corretor: !!quem.corretor, falouComANay: !!quem.falou_com_a_nay,
    }
  }).sort((a, b) => Number(b.admin) - Number(a.admin) || (a.nome || '~').localeCompare(b.nome || '~', 'pt-BR'))
  return {
    id,
    nome: String(meta.subject || meta.name || id),
    descricao: meta.description ? String(meta.description) : null,
    criadoEm: Number(meta.creation) ? Number(meta.creation) * (Number(meta.creation) < 1e12 ? 1000 : 1) : null,
    dono: meta.owner ? String(meta.owner).replace(/\D/g, '') : null,
    souAdmin: parts.some((p) => mesmoNumero(String(p.phone || ''), eu) && (p.isAdmin || p.isSuperAdmin)),
    config: {
      soAdminMandaMensagem: sim(meta.adminOnlyMessage), soAdminEdita: sim(meta.adminOnlySettings),
      soAdminAdiciona: sim(meta.adminOnlyAddMember), aprovacaoParaEntrar: sim(meta.requireAdminApproval),
    },
    linkDeConvite: meta.invitationLink ? String(meta.invitationLink) : null,
    participantes,
    casa: casa[id] || {},
  }
}

export async function mensagensDoGrupo(id: string, antes: string | null): Promise<any[]> {
  const r = await naydb().query('SELECT crm_grupo_mensagens($1, $2::timestamptz, 80) AS j', [id, antes || null])
  return r.rows[0]?.j || []
}

/**
 * GUARDAR A MENSAGEM DE GRUPO (278). O nó "Espelhar no CRM" do n8n manda ao webhook do CRM uma cópia de tudo o
 * que chega pela Z-API; as de grupo vêm junto e iam fora. Só as da instância da PARCERIA são guardadas (a
 * captação tem a dela). O banco ignora repetida e nunca levanta erro (nai_grupo_guardar).
 */
export async function guardarMensagemDeGrupo(organizationId: string, body: any): Promise<void> {
  const creds = await getZapiCredentials(organizationId)
  if (body?.instanceId && String(body.instanceId) !== creds.instanceId) return
  await naydb().query('SELECT nai_grupo_guardar($1::jsonb)', [JSON.stringify(body)])
}

export async function mandarNoGrupo(organizationId: string, id: string, texto: string): Promise<string | null> {
  const r = await sendZapiMessage(organizationId, id, texto)
  return r.data?.messageId || r.data?.id || r.data?.zaapId || null
}

/* ── editar ── */
export type AcaoNoGrupo =
  | { acao: 'nome'; nome: string }
  | { acao: 'descricao'; descricao: string }
  | { acao: 'config'; soAdminMandaMensagem?: boolean; soAdminEdita?: boolean; soAdminAdiciona?: boolean; aprovacaoParaEntrar?: boolean }
  | { acao: 'adicionar' | 'remover' | 'promover' | 'rebaixar'; telefones: string[] }

/** Faz a ação e RELÊ o grupo. Devolve o grupo como ficou e se a mudança aparece nele. */
export async function editarGrupo(organizationId: string, id: string, a: AcaoNoGrupo): Promise<{ grupo: DadosDoGrupo; conferido: boolean }> {
  const creds = await getZapiCredentials(organizationId)
  const antes = await dadosDoGrupo(organizationId, id, true)
  if (!antes.souAdmin) throw { status: 403, message: 'O número da Parceria não é admin deste grupo: só dá para ver.' }
  const telefones = 'telefones' in a ? a.telefones.map((t) => t.replace(/\D/g, '')).filter((t) => t.length >= 10 && t.length <= 13) : []
  if ('telefones' in a && !telefones.length) throw { status: 400, message: 'Diga o telefone com DDD.' }
  const caminho: Record<string, string> = {
    nome: 'update-group-name', descricao: 'update-group-description', config: 'update-group-settings',
    adicionar: 'add-participant', remover: 'remove-participant', promover: 'add-admin', rebaixar: 'remove-admin',
  }
  const corpo =
    a.acao === 'nome' ? { groupId: id, groupName: a.nome.trim().slice(0, 100) }
    : a.acao === 'descricao' ? { groupId: id, groupDescription: a.descricao.slice(0, 2048) }
    : a.acao === 'config' ? {
        phone: id,
        adminOnlyMessage: a.soAdminMandaMensagem ?? antes.config.soAdminMandaMensagem,
        adminOnlySettings: a.soAdminEdita ?? antes.config.soAdminEdita,
        adminOnlyAddMember: a.soAdminAdiciona ?? antes.config.soAdminAdiciona,
        requireAdminApproval: a.aprovacaoParaEntrar ?? antes.config.aprovacaoParaEntrar,
      }
    : a.acao === 'adicionar' ? { groupId: id, phones: telefones, autoInvite: true }
    : { groupId: id, phones: telefones }
  const r = await chamar(creds, caminho[a.acao], { body: corpo }, 'A Z-API não aceitou a mudança')
  if (r && (r.value === false || r.success === false)) {
    throw { status: 400, message: r.message || r.error || 'A Z-API não aceitou a mudança.' }
  }
  const depois = await dadosDoGrupo(organizationId, id, true)
  const tem = (t: string) => depois.participantes.find((p) => p.telefone.slice(-8) === t.slice(-8))
  const conferido =
    a.acao === 'nome' ? depois.nome === corpo.groupName
    : a.acao === 'descricao' ? (depois.descricao || '') === (corpo as any).groupDescription
    : a.acao === 'config' ? true
    : a.acao === 'adicionar' ? telefones.every((t) => !!tem(t))
    : a.acao === 'remover' ? telefones.every((t) => !tem(t))
    : a.acao === 'promover' ? telefones.every((t) => !!tem(t)?.admin)
    : telefones.every((t) => !tem(t)?.admin)
  return { grupo: depois, conferido }
}

/* ── tirar dados ── */
function celula(v: unknown): string {
  const s = String(v ?? '')
  return /[";\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s
}
export function csv(linhas: unknown[][]): string {
  // ponto e vírgula e BOM: abre certo no Excel em português
  return '﻿' + linhas.map((l) => l.map(celula).join(';')).join('\r\n') + '\r\n'
}

export function csvDoGrupo(g: DadosDoGrupo): string {
  return csv([
    ['grupo', 'telefone', 'nome', 'admin', 'corretor cadastrado', 'já falou com a Nay'],
    ...g.participantes.map((p) => [g.nome, p.telefone, p.nome || '', p.admin ? 'sim' : '', p.corretor ? 'sim' : '', p.falouComANay ? 'sim' : '']),
  ])
}

/** Todos os grupos numa planilha só: uma linha por PESSOA, com os grupos em que ela está. */
export async function csvDeTodos(organizationId: string): Promise<string> {
  const { grupos } = await listarGrupos(organizationId)
  const dados = await aos_poucos(grupos, 4, (g) => dadosDoGrupo(organizationId, g.id).catch(() => null))
  const pessoas = new Map<string, { p: Participante; grupos: string[] }>()
  dados.forEach((d) => d?.participantes.forEach((p) => {
    if (!p.telefone) return
    const k = p.telefone.slice(-8)
    const x = pessoas.get(k) || { p, grupos: [] }
    x.grupos.push(d.nome)
    if (!x.p.nome && p.nome) x.p = p
    pessoas.set(k, x)
  }))
  const ordem = [...pessoas.values()].sort((a, b) => b.grupos.length - a.grupos.length)
  return csv([
    ['telefone', 'nome', 'quantos grupos', 'grupos', 'corretor cadastrado', 'já falou com a Nay'],
    ...ordem.map(({ p, grupos: gs }) => [p.telefone, p.nome || '', gs.length, gs.join(' | '), p.corretor ? 'sim' : '', p.falouComANay ? 'sim' : '']),
  ])
}
