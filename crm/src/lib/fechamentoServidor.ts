/**
 * O LADO DO SERVIDOR DA ABA FECHAMENTO (30/09/2026): o lead, as mídias da
 * conversa com o documento de cada uma (a escolha da Rayssa ou o automático) e o
 * fechamento na Nay. As regras (catálogo, automático, leitura dos campos) moram em
 * lib/fechamentoDocumentos; aqui é só banco e disco.
 */
import { stat } from 'node:fs/promises'
import { join } from 'node:path'
import { sql } from 'drizzle-orm'
import { db } from '@/lib/db'
import { naydb } from '@/lib/nayDisparo'
import { PASTA_DO_ARMAZEM, relativoDoArmazem } from '@/lib/armazem'
import type { TipoChecklist } from '@/lib/checklistFechamento'
import {
  documentoDaChave, donoDoPapel, identificarDocumento, type Dono, type Papel,
} from '@/lib/fechamentoDocumentos'

export interface LeadDoFechamento { id: string; nome: string; telefone: string | null }

export async function leadDoFechamento(org: string, leadId: string): Promise<LeadDoFechamento | null> {
  if (!/^[0-9a-f-]{36}$/i.test(leadId || '')) return null
  const r = await db.execute(sql`SELECT id, title, phone FROM leads
                                   WHERE id = ${leadId} AND organization_id = ${org} AND deleted_at IS NULL`)
  const l = r.rows[0] as any
  return l ? { id: l.id, nome: l.title, telefone: l.phone } : null
}

export interface FechamentoNaNay {
  tipo: TipoChecklist | null
  enviadoEm: string | null
  desde: string | null
}

/** O fechamento na Nay (211): o tipo e quando o checklist saiu. */
export async function fechamentoNaNay(telefone: string | null): Promise<FechamentoNaNay> {
  if (!telefone) return { tipo: null, enviadoEm: null, desde: null }
  try {
    const r = await naydb().query('SELECT * FROM crm_fechamento_do_contato($1)', [telefone])
    const l = r.rows[0] || {}
    const tipo = (l.tipo || l.checklist_tipo || null) as TipoChecklist | null
    const enviadoEm = l.checklist_em ? new Date(l.checklist_em).toISOString() : null
    const desde = l.iniciado_em ? new Date(l.iniciado_em).toISOString() : enviadoEm
    return { tipo: tipo === 'venda' || tipo === 'locacao' ? tipo : null, enviadoEm, desde }
  } catch (err) {
    console.error('[fechamento] a Nay não respondeu', (err as Error)?.message)
    return { tipo: null, enviadoEm: null, desde: null }
  }
}

export interface Atividade {
  id: string
  quando: string
  direcao: 'recebida' | 'enviada'
  texto: string
  midia: { tipo: string; url: string; mime: string | null; nome: string | null } | null
}

/** As mensagens do WhatsApp do lead, da mais velha para a mais nova (90 dias, até 3000). */
export async function atividadesDoLead(org: string, leadId: string): Promise<Atividade[]> {
  const r = await db.execute(sql`
    SELECT id, content, metadata, created_at FROM lead_activities
     WHERE lead_id = ${leadId} AND organization_id = ${org} AND type = 'whatsapp'
       AND created_at > now() - interval '90 days'
     ORDER BY created_at DESC LIMIT 3000`)
  return (r.rows as any[]).reverse().map((a) => {
    const m = a.metadata || {}
    const url = m.media_url ? String(m.media_url) : ''
    return {
      id: a.id,
      quando: new Date(a.created_at).toISOString(),
      direcao: m.direction === 'outbound' ? 'enviada' : 'recebida',
      texto: String(a.content || ''),
      midia: url && m.media_type ? { tipo: String(m.media_type), url, mime: m.media_mimetype || null, nome: m.media_filename || null } : null,
    }
  })
}

/**
 * Mídia que conta como documento: imagem, PDF/arquivo, vídeo, que a PESSOA mandou
 * (as fotos de imóvel que a Nay manda não entram); sem figurinha nem áudio.
 */
export function ehDocumentoPossivel(a: Atividade): boolean {
  if (!a.midia || a.direcao !== 'recebida') return false
  if (a.texto.trim() === '[Figurinha]' || a.midia.mime === 'image/webp') return false
  return ['image', 'document', 'video'].includes(a.midia.tipo)
}

/**
 * As escolhas da Rayssa pelas MENSAGENS, não pelo lead: quando duas conversas são
 * juntadas (juntarConversaNaOutra) as mensagens mudam de lead e a escolha vai junto.
 */
export async function escolhasDaRayssa(activityIds: string[]): Promise<Map<string, { documento: string; papel: Papel | null }>> {
  if (!activityIds.length) return new Map()
  const r = await db.execute(sql`SELECT activity_id, documento, papel FROM fechamento_documentos
                                   WHERE activity_id = ANY(${activityIds}::uuid[])`)
  return new Map((r.rows as any[]).map((l) => [l.activity_id, { documento: l.documento, papel: l.papel }]))
}

export async function bytesDoArquivo(url: string): Promise<number | null> {
  const rel = relativoDoArmazem(url)
  if (!rel) return null
  try { return (await stat(join(PASTA_DO_ARMAZEM, rel))).size } catch { return null }
}

export interface ItemDoFechamento {
  activityId: string
  quando: string
  direcao: 'recebida' | 'enviada'
  tipo: string
  mime: string | null
  nomeArquivo: string | null
  legenda: string | null
  url: string
  thumb: string | null
  bytes: number | null
  documento: { chave: string; rotulo: string } | null
  papel: Papel | null
  dono: Dono | null
  origem: 'automatico' | 'manual' | null
  motivo: string | null
}

/**
 * Cada mídia com o documento: a escolha da Rayssa manda; sem ela, o automático
 * (nome do arquivo, legenda, mensagem curta da mesma pessoa até 2 min antes/depois).
 */
export async function itensDoFechamento(atividades: Atividade[], _leadId: string,
                                        tipo: TipoChecklist | null): Promise<ItemDoFechamento[]> {
  const midias = atividades.filter(ehDocumentoPossivel)
  const escolhas = await escolhasDaRayssa(midias.map((a) => a.id))
  // os textos da pessoa com a hora já lida (a lista vem em ordem de tempo)
  const textos = atividades.filter((a) => !a.midia && a.direcao === 'recebida' && a.texto.trim())
    .map((a) => ({ t: Date.parse(a.quando), texto: a.texto }))
  const itens: ItemDoFechamento[] = []
  for (const a of midias) {
    const t = Date.parse(a.quando)
    const vizinhas = textos.filter((x) => Math.abs(x.t - t) <= 120_000).map((x) => x.texto)
    const legenda = a.texto && a.texto !== a.midia!.nome ? a.texto : null
    const escolha = escolhas.get(a.id)
    const auto = escolha ? null : identificarDocumento(a.midia!.nome, legenda, vizinhas, tipo)
    const chave = escolha?.documento ?? auto?.documento ?? null
    const doc = documentoDaChave(chave)
    const papel = (escolha ? escolha.papel : auto?.papel) ?? null
    const imagemNossa = a.midia!.tipo === 'image' && !!relativoDoArmazem(a.midia!.url)
    itens.push({
      activityId: a.id, quando: a.quando, direcao: a.direcao, tipo: a.midia!.tipo, mime: a.midia!.mime,
      nomeArquivo: a.midia!.nome, legenda, url: a.midia!.url,
      thumb: imagemNossa ? `${a.midia!.url.split('?')[0]}?w=160` : null,
      bytes: await bytesDoArquivo(a.midia!.url),
      documento: doc ? { chave: doc.chave, rotulo: doc.rotulo } : null,
      papel, dono: donoDoPapel(papel),
      origem: escolha ? 'manual' : doc ? 'automatico' : null,
      motivo: escolha ? null : auto?.motivo ?? null,
    })
  }
  return itens
}
