/**
 * GET /api/parceria/visitas -- as visitas que a Nay agenda, com todas as
 * datas (29/09/2026). Pedro: "uma aba só de visitas agendadas que a ia
 * preenche sozinha quando confirma uma visita e a Rayssa pode acompanhar por
 * lá o andamento, e as datas de tudo".
 *
 * Vem da Nay (crm_visitas, migração 166): as abertas sempre; as fechadas na
 * janela pedida (?desde=AAAA-MM-DD&ate=AAAA-MM-DD; sem janela, todas). Cada
 * visita traz a conversa do corretor no CRM, quando existe, para abrir o
 * chat dele com um clique. As chaves de telefone ficam aqui no servidor.
 */
import { NextRequest } from 'next/server'
import { and, eq, isNull } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { leads, profiles } from '@/lib/schema'
import { agendarVisita, visitasDaNay } from '@/lib/nayLeitura'
import { conversaPorChave, conversasDaParceria } from '@/lib/conversasDaParceria'
import { abrirLeadDaLinha } from '@/lib/abrirLead'
import { LEMBRETE_PADRAO_MIN, MODELO_DO_LEMBRETE, agendarLembreteDaVisita, preencherLembrete } from '@/lib/lembreteDaVisita'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const DATA = /^\d{4}-\d{2}-\d{2}$/

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const desde = req.nextUrl.searchParams.get('desde')
    const ate = req.nextUrl.searchParams.get('ate')
    const [visitas, conversas] = await Promise.all([
      visitasDaNay(desde && DATA.test(desde) ? desde : null, ate && DATA.test(ate) ? ate : null),
      conversasDaParceria(auth.organizationId),
    ])
    const porChave = conversaPorChave(conversas)
    const saida = visitas.map(({ corretorChaves, ...v }) => {
      const conversa = corretorChaves.map((ch) => porChave.get(ch)).find(Boolean) || null
      return { ...v, conversa: conversa ? { leadId: conversa.id, titulo: conversa.titulo, avatar: conversa.avatar } : null }
    })
    return Response.json({ visitas: saida, em: Date.now() })
  } catch (err: any) {
    console.error('[parceria/visitas]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui ler as visitas da Nay.')
  }
}

/**
 * POST /api/parceria/visitas -- AGENDAR VISITA À MÃO (Pedro, 01/10/2026): "eu vou
 * agendar manualmente, vou pôr o corretor, a duração e o dia, e posso adicionar
 * um lembrete ali mesmo... por padrão o lembrete já vem configurado para 1 hora
 * antes". Vale para o botão azul do card e para o + da agenda.
 *
 *   { codigo, corretor: { leadId? | telefone, nome? }, quando, duracaoMin,
 *     lembrete?: { minutosAntes, corretor, proprietario, mensagem? },
 *     proprietarioLeadId? }
 *
 * A visita nasce da equipe (migração 250): a Nay não manda nada sozinha. O
 * lembrete é uma mensagem agendada na conversa de cada um (o mesmo cron do
 * follow-up), presa à visita -- excluir ou arrastar a visita leva o lembrete.
 */
export async function POST(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    if (!auth.userId) return apiError(403, 'Só quem entra no CRM agenda visita.')
    const corpo = await req.json().catch(() => ({} as any))

    const codigo = /^\d{1,6}$/.test(String(corpo?.codigo ?? '')) ? Number(corpo.codigo) : null
    if (!codigo) return apiError(400, 'Diga o código do imóvel.')
    const quando = new Date(String(corpo?.quando || ''))
    if (Number.isNaN(quando.getTime())) return apiError(400, 'Escolha o dia e a hora.')
    const duracaoMin = Math.round(Number(corpo?.duracaoMin) || 60)

    // o corretor: pela conversa dele (escolhido na lista) ou pelo número digitado
    let corretorLead: string | null = null
    let corretorTelefone = String(corpo?.corretor?.telefone || '').replace(/\D/g, '')
    let corretorNome: string | null = String(corpo?.corretor?.nome || '').trim().slice(0, 120) || null
    if (corpo?.corretor?.leadId) {
      const [l] = await db.select({ id: leads.id, telefone: leads.phone, titulo: leads.title }).from(leads)
        .where(and(eq(leads.id, String(corpo.corretor.leadId)), eq(leads.organizationId, auth.organizationId), isNull(leads.deletedAt)))
        .limit(1)
      if (!l?.telefone) return apiError(404, 'Não achei a conversa desse corretor.')
      corretorLead = l.id
      corretorTelefone = l.telefone.replace(/\D/g, '')
      corretorNome = corretorNome || l.titulo || null
    }
    if (corretorTelefone.length < 10) return apiError(400, 'Escolha o corretor ou digite o número dele com DDD.')

    const [perfil] = await db.select({ nome: profiles.fullName }).from(profiles).where(eq(profiles.id, auth.userId)).limit(1)
    const quem = perfil?.nome?.trim() || 'alguém no CRM'

    const v = await agendarVisita(codigo, corretorTelefone, corretorNome, quando, duracaoMin, quem)
    if (!v.ok || !v.visita) return Response.json({ ok: false, mensagem: v.mensagem }, { status: 409 })

    /* ---- o lembrete (opcional; por padrão, 1 hora antes) ---- */
    const avisos: string[] = []
    const lembretes: Array<{ para: string; quando: string }> = []
    const l = corpo?.lembrete
    if (l && (l.corretor || l.proprietario)) {
      const minutos = Math.max(0, Math.min(7 * 24 * 60, Math.round(Number(l.minutosAntes ?? LEMBRETE_PADRAO_MIN))))
      const enviarEm = new Date(quando.getTime() - minutos * 60_000)
      const proprio = String(l.mensagem || '').trim().slice(0, 4000)
      if (enviarEm.getTime() < Date.now() + 60_000) {
        avisos.push('A hora do lembrete já passou: a visita ficou agendada, sem lembrete.')
      } else {
        const destinos: Array<{ para: 'corretor' | 'proprietario'; leadId: string | null; nome: string | null }> = []
        if (l.corretor) {
          const aberto = corretorLead ? { id: corretorLead } : await abrirLeadDaLinha(auth.organizationId, corretorTelefone, corretorNome)
          destinos.push({ para: 'corretor', leadId: aberto?.id || null, nome: v.corretorNome || corretorNome })
        }
        if (l.proprietario) {
          let dono: string | null = null
          if (corpo?.proprietarioLeadId) {
            const [d] = await db.select({ id: leads.id }).from(leads)
              .where(and(eq(leads.id, String(corpo.proprietarioLeadId)), eq(leads.organizationId, auth.organizationId), isNull(leads.deletedAt)))
              .limit(1)
            dono = d?.id || null
          } else if (v.proprietarioTelefone) {
            dono = (await abrirLeadDaLinha(auth.organizationId, v.proprietarioTelefone, v.proprietarioNome))?.id || null
          }
          if (!dono) avisos.push('O imóvel não tem proprietário com telefone no cadastro: o lembrete dele não foi agendado.')
          else destinos.push({ para: 'proprietario', leadId: dono, nome: v.proprietarioNome })
        }
        for (const d of destinos) {
          if (!d.leadId) { avisos.push(`Não consegui abrir a conversa do ${d.para} para o lembrete.`); continue }
          await agendarLembreteDaVisita({
            organizacao: auth.organizationId, leadId: d.leadId, visita: v.visita, minutosAntes: minutos,
            // o texto da janela (o padrão ou o que a pessoa escreveu) vale para cada destino:
            // as marcas {nome}, {quando} e {imóvel} são trocadas pelo que vale para ELE
            mensagem: preencherLembrete(proprio || MODELO_DO_LEMBRETE, d.para, d.nome, quando, enviarEm, v.imovel, v.imovelDoDono),
            enviarEm, criadoPor: auth.userId, criadoPorNome: perfil?.nome?.trim() || null,
          })
          lembretes.push({ para: d.para, quando: enviarEm.toISOString() })
        }
      }
    }
    return Response.json({ ok: true, mensagem: v.mensagem, visita: v.visita, lembretes, avisos }, { status: 201 })
  } catch (err: any) {
    console.error('[parceria/visitas] agendar', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui agendar a visita.')
  }
}
