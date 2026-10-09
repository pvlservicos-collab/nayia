/**
 * GET /api/conversas/por-telefone?telefone=5592... -- a conversa de um telefone, em todas as linhas (oficial,
 * captação, parceria), para quem está FORA do CRM mostrar: o Cadastro rápido do site (Pedro, 09/10/2026: "esses
 * imóveis que vêm de conversa eu quero ver a conversa, pega o mockup de conversa lá do CRM, em um popup").
 *
 * Só lê. Devolve as mensagens em ordem, com quem mandou (a pessoa, a Nay, o Tel/Rayssa pelo login, o celular) e a
 * mídia num endereço ASSINADO com validade curta: o popup do site não tem a sessão do CRM. Casa pelo fim do
 * telefone (8 dígitos), como o resto do CRM.
 */
import { NextRequest } from 'next/server'
import { sql } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { enderecoParaFora, ehDoArmazem } from '@/lib/armazem'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const LINHA_DO_TIPO: Record<string, { linha: string; rotulo: string }> = {
  whatsapp_cloud_official: { linha: 'oficial', rotulo: 'WhatsApp oficial' },
  whatsapp_zapi_captacao: { linha: 'captacao', rotulo: 'WhatsApp da captação (Z-API)' },
  whatsapp_zapi: { linha: 'parceria', rotulo: 'WhatsApp da Nay (Parceria)' },
}
const VALIDADE_DA_MIDIA = 6 * 3600   // o popup fica aberto minutos, não dias

function autorDe(meta: any, membro: string | null, saida: boolean, nomeDoLead: string): string {
  if (!saida) return String(meta?.sender_name || nomeDoLead || 'Contato')
  if (meta?.source === 'human') return membro || 'Equipe (CRM)'
  if (meta?.source === 'ai_agent') return meta?.template ? 'Nay (modelo do disparo)' : 'Nay'
  if (meta?.source === 'followup_agendado') return 'Mensagem agendada'
  if (meta?.automated || meta?.agente) return 'Nay'
  return 'Nosso número'      // saiu pela Z-API: a Nay da linha ou alguém no celular
}

export async function GET(req: NextRequest) {
  try {
    const { organizationId } = await authenticateRequest(req)
    const digitos = String(req.nextUrl.searchParams.get('telefone') || '').replace(/\D/g, '')
    if (digitos.length < 8) return apiError(400, 'Diga o telefone (com DDD).')
    const fim8 = digitos.slice(-8)
    const limite = Math.min(Math.max(Number(req.nextUrl.searchParams.get('limite')) || 400, 20), 1000)

    const leads = await db.execute(sql`
      SELECT l.id::text AS id, coalesce(l.title, '') AS nome, coalesce(l.phone, '') AS telefone, i.type AS tipo, coalesce(i.name, '') AS integracao
        FROM leads l JOIN integrations i ON i.id = l.integration_id
       WHERE l.organization_id = ${organizationId} AND l.deleted_at IS NULL AND coalesce(l.is_group, false) = false
         AND right(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g'), 8) = ${fim8}`)

    const conversas = []
    for (const l of leads.rows as Array<{ id: string; nome: string; telefone: string; tipo: string; integracao: string }>) {
      const r = await db.execute(sql`
        SELECT x.* FROM (
          SELECT a.id::text AS id, a.created_at AS quando, coalesce(a.content, '') AS texto, coalesce(a.metadata, '{}'::jsonb) AS meta,
                 p.full_name AS membro
            FROM lead_activities a
            LEFT JOIN organization_members m ON m.id = a.actor_member_id
            LEFT JOIN profiles p ON p.id = m.user_id
           WHERE a.lead_id = ${l.id}::uuid AND a.organization_id = ${organizationId} AND a.type = 'whatsapp'
           ORDER BY a.created_at DESC LIMIT ${limite}) x
         ORDER BY x.quando`)
      const mensagens = (r.rows as any[]).filter((m) => !m.meta?.is_reaction).map((m) => {
        const meta = m.meta || {}
        const saida = meta.direction === 'outbound'
        let midia: { tipo: string; url: string; mime: string | null; nome: string | null; segundos: number | null } | null = null
        if (meta.media_url) {
          let url = String(meta.media_url)
          try { if (ehDoArmazem(url)) url = enderecoParaFora(url, VALIDADE_DA_MIDIA) } catch { /* sem base: fica o caminho */ }
          midia = { tipo: String(meta.media_type || 'document'), url, mime: meta.media_mimetype || null,
                    nome: meta.media_filename || null, segundos: meta.audio_seconds != null ? Number(meta.audio_seconds) : null }
        }
        return {
          id: m.id, quando: m.quando, saida,
          autor: autorDe(meta, m.membro, saida, l.nome),
          deGente: saida && meta.source === 'human',
          texto: String(m.texto || ''),
          midia,
          transcricao: meta.transcricao ? String(meta.transcricao) : null,
          citado: meta.quoted_text ? String(meta.quoted_text).slice(0, 300) : null,
          falhou: meta.send_status === 'failed',
        }
      })
      if (!mensagens.length) continue
      const linha = LINHA_DO_TIPO[l.tipo] || { linha: l.tipo, rotulo: l.integracao || l.tipo }
      conversas.push({ ...linha, lead: l.id, nome: l.nome, telefone: l.telefone, mensagens,
                       ultima: mensagens[mensagens.length - 1].quando })
    }
    conversas.sort((a, b) => new Date(b.ultima).getTime() - new Date(a.ultima).getTime())
    return Response.json({ conversas })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui ler a conversa.')
  }
}
