/**
 * GET /api/esteira-followups?dias=7 -- a ESTEIRA DE FOLLOW-UP (Pedro, 02/11/2026): "uma esteira de follow-up por dia com todos
 * que vão receber follow-up nos próximos dias, de todas as Nays e de todos os lugares, os manuais e automáticos".
 *
 * Junta duas fontes: os MANUAIS e lembretes de visita do card (followups_agendados, banco do CRM) e os AUTOMÁTICOS de cada Nay
 * (crm_esteira_automatica, banco da Nay, 563). O que não tem dia (a fila da retomada, as dúvidas que esperam o dono) vem em
 * `semData`. Um follow-up que alguém marca no card aparece aqui na hora.
 */
import { NextRequest } from 'next/server'
import { sql } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { naydb } from '@/lib/nayDisparo'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const NAY_DA_LINHA: Record<string, string> = {
  'WhatsApp Parceria': 'Parceria', 'WhatsApp Captação (Z-API)': 'Leads', 'WhatsApp API (captação)': 'Oficial',
}
const manaus = (d: Date) => new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Manaus' }).format(d)   // AAAA-MM-DD

export interface ItemDaEsteira {
  dia: string | null; quando: string | null; janela?: string; nay: string; tipo: 'manual' | 'automatico'; origem: string
  titulo: string; nome: string | null; telefone: string | null; estado: string; detalhe?: string
  leadId?: string; criadoPor?: string; motivo?: string
}

/* O MOTIVO (Pedro, 02/11: "um quadrado Motivo explicando o porquê"): em uma frase, por que essa pessoa vai receber o follow-up. */
function motivoDe(i: ItemDaEsteira, minutosAntes?: number | null): string {
  switch (i.origem) {
    case 'manual':
      return `${i.criadoPor || 'Alguém da equipe'} marcou este follow-up no card da conversa. Sai no horário, pelo número da conversa.`
    case 'lembrete_da_visita':
      return `Tem visita marcada. O lembrete sai ${minutosAntes ?? 60} minutos antes, para ninguém esquecer.`
    case 'parceria_dia_seguinte': {
      if (i.estado === 'enviado') return 'Recebeu imóvel da Nay da Parceria no dia anterior; a pergunta "seu cliente tem interesse?" já saiu hoje.'
      if (i.estado === 'pulado') return `A Nay pulou este: ${i.detalhe || 'a regra do dia seguinte não valia para ele'}.`
      const quando = i.dia && new Date(i.dia + 'T12:00:00-04:00').getUTCDay() === 1 ? 'no fim de semana' : 'no dia anterior'
      return `Recebeu imóvel da Nay da Parceria ${quando} e não respondeu nem recusou. No dia seguinte ela pergunta se o cliente tem interesse.`
        + (i.estado === 'desligado' ? ' O follow-up automático da Parceria está DESLIGADO agora: enquanto estiver, não sai.' : '')
    }
    case 'leads_visita':
      return /como foi/i.test(i.titulo)
        ? 'A visita já passou. A Nay pergunta como foi, para saber se o cliente quer seguir (proposta, outra visita ou outro imóvel).'
        : 'O cliente marcou visita. A Nay lembra antes, para ele não faltar.'
    case 'busca_nos_grupos':
      return 'O lead pediu um imóvel e ninguém ofereceu no grupo ainda. A Nay repete o pedido (até 2 vezes) e para assim que alguém oferecer.'
    case 'retomada_oficial':
      return 'Donos que receberam a primeira mensagem da captação e nunca responderam. O disparo chama cada um uma vez pelo número oficial.'
    case 'duvida_cobranca':
      return 'A Nay perguntou ao dono algo que o cliente quer saber, e o dono ainda não respondeu. Ela cobra de hora em hora até ele responder.'
    default:
      return i.detalhe || ''
  }
}

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const dias = Math.min(30, Math.max(1, Number(req.nextUrl.searchParams.get('dias')) || 7))
    const hoje = manaus(new Date())
    const ate = manaus(new Date(Date.now() + dias * 86400000))
    const itens: ItemDaEsteira[] = []

    // manuais (e os lembretes de visita): hoje inteiro (o que já saiu também) e os próximos dias
    const r = await db.execute(sql`
      SELECT f.id::text, f.lead_id::text, f.mensagem, f.enviar_em, f.estado, f.criado_por_nome, f.visita_id, f.minutos_antes, f.erro,
             l.title, l.phone, i.name AS linha
        FROM followups_agendados f
        JOIN leads l ON l.id = f.lead_id
        LEFT JOIN integrations i ON i.id = l.integration_id
       WHERE f.organization_id = ${auth.organizationId}::uuid AND f.estado <> 'cancelado'
         AND (f.enviar_em AT TIME ZONE 'America/Manaus')::date BETWEEN ${hoje}::date AND ${ate}::date
       ORDER BY f.enviar_em`)
    for (const l of r.rows as any[]) {
      const quando = new Date(l.enviar_em).toISOString()
      const item: ItemDaEsteira = {
        dia: manaus(new Date(l.enviar_em)), quando, nay: NAY_DA_LINHA[l.linha] || 'CRM', tipo: 'manual',
        origem: l.visita_id ? 'lembrete_da_visita' : 'manual',
        titulo: l.visita_id ? `Lembrete da visita (${l.minutos_antes ?? 60} min antes)` : 'Follow-up marcado no card',
        nome: l.title || l.phone, telefone: l.phone,
        estado: l.estado === 'agendado' ? 'previsto' : l.estado === 'enviado' ? 'enviado' : l.estado,
        detalhe: String(l.mensagem || '').slice(0, 160) + (l.erro ? ` · erro: ${String(l.erro).slice(0, 80)}` : ''),
        leadId: l.lead_id, criadoPor: l.criado_por_nome || undefined,
      }
      item.motivo = motivoDe(item, l.minutos_antes)
      itens.push(item)
    }

    // automáticos de cada Nay
    let semData: ItemDaEsteira[] = []
    try {
      const a = await naydb().query('SELECT crm_esteira_automatica($1::int) AS j', [dias])
      for (const x of (a.rows[0]?.j || []) as any[]) {
        const item: ItemDaEsteira = {
          dia: x.dia || null, quando: x.quando || null, janela: x.janela, nay: x.nay, tipo: 'automatico', origem: x.origem,
          titulo: x.titulo, nome: x.nome || null, telefone: x.telefone || null, estado: x.estado, detalhe: x.detalhe,
        }
        item.motivo = motivoDe(item)
        if (item.dia) itens.push(item); else semData.push(item)
      }
    } catch (err: any) {
      console.error('[esteira-followups] automáticos', err?.message || err)    // antes da 563 no banco: só os manuais
    }
    itens.sort((p, q) => (p.quando || p.dia || '').localeCompare(q.quando || q.dia || ''))
    return Response.json({ hoje, dias, itens, semData })
  } catch (err: any) {
    console.error('[esteira-followups]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui montar a esteira.')
  }
}
