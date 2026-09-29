/**
 * Disparo de imóvel para um número (Tel, 28/09/2026): "lá em cima o número,
 * embaixo um campo de pesquisar imóvel... eu seleciono e clico em enviar e ele
 * envia via zapi, eu seleciono também qual número quero enviar, por padrão fica
 * o de parceria. Quero esse menu de envio no site e no CRM lá em cima."
 *
 * As duas telas (a do CRM e a do admin do site) chamam esta rota -- o site com
 * o token de API. Um remetente só: as paredes não podem depender de por onde o
 * Tel clicou.
 *
 *   GET  -> as linhas de WhatsApp, a Parceria primeiro (é o padrão), e as
 *           opções do nosso banco (bairros e tipos do que pode sair, com a
 *           contagem) -- a lista que desce no disparo por faixa
 *   POST -> { telefone, codigos: number[], integrationId?, quem? }
 *
 * PARCERIA vai pela caixa de saída da Nay (ver `nayDisparo.ts`): a conversa
 * aparece no CRM pelo eco da Z-API, como qualquer mensagem da Nay.
 *
 * API OFICIAL só alcança quem falou com o número nas últimas 24h -- fora disso
 * a Meta aceita o envio e descarta depois, sem erro nenhum na hora. Então a
 * janela é conferida ANTES, pela última mensagem que chegou dele por lá.
 */
import { NextRequest } from 'next/server'
import { and, desc, eq, gt, inArray, isNull, sql } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { integrations, leadActivities, leads, organizationMembers, profiles } from '@/lib/schema'
import { getChannelAdapter } from '@/lib/channels/registry'
import { ehEspelhoDeTreino, normalizePhone, telefoneVariantes } from '@/lib/leadSources'
import { registrarEnvioNoCrm } from '@/lib/registrarEnvio'
import { conferirParaOficial, enfileirarNaNay, liberarReserva, opcoesNaNay, TETO_POR_ENVIO } from '@/lib/nayDisparo'

const TETO_DE_IMOVEIS = TETO_POR_ENVIO
/** Fotos por imóvel na API oficial (a mesma conta do "enviar imóvel" da conversa). */
const TETO_DE_FOTOS = 8
const TIPOS = ['whatsapp_zapi', 'whatsapp_cloud_official']

async function linhasDaOrganizacao(organizationId: string) {
  const rows = await db
    .select({ id: integrations.id, nome: integrations.name, tipo: integrations.type })
    .from(integrations)
    .where(and(
      eq(integrations.organizationId, organizationId),
      inArray(integrations.type, TIPOS),
      eq(integrations.status, 'active'),
      isNull(integrations.deletedAt),
    ))
  // A Parceria (Z-API) é o padrão e vem primeiro.
  return rows
    .map((r) => ({
      id: r.id,
      nome: r.nome,
      tipo: r.tipo as string,
      padrao: r.tipo === 'whatsapp_zapi',
      aviso: r.tipo === 'whatsapp_cloud_official'
        ? 'Só chega para quem falou com este número nas últimas 24h.'
        : null,
    }))
    .sort((a, b) => Number(b.padrao) - Number(a.padrao))
}

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    // as opções ajudam, mas não são essenciais: sem elas a tela abre igual
    const opcoes = await opcoesNaNay().catch(() => ({ bairros: [], tipos: [] }))
    return Response.json({
      linhas: await linhasDaOrganizacao(auth.organizationId),
      opcoes,
      teto: TETO_DE_IMOVEIS,
    })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Não consegui listar as linhas.')
  }
}

async function nomeDeQuemPediu(auth: { memberId: string | null }, doCorpo: unknown): Promise<string> {
  if (auth.memberId) {
    const [m] = await db
      .select({ nome: profiles.fullName })
      .from(organizationMembers)
      .leftJoin(profiles, eq(profiles.id, organizationMembers.userId))
      .where(eq(organizationMembers.id, auth.memberId))
      .limit(1)
    return `CRM: ${m?.nome || 'equipe'}`
  }
  // Pelo token de API: o site diz quem estava logado no admin.
  return `site: ${String(doCorpo || '').trim().slice(0, 60) || 'admin'}`
}

export async function POST(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const body = await req.json().catch(() => ({}))

    const telefone = normalizePhone(body?.telefone)
    if (!telefone || !telefone.startsWith('55') || telefone.length < 12 || telefone.length > 13) {
      return apiError(400, 'O número parece incompleto — use DDD + número, ex.: 92 99999-9999.')
    }
    const codigos: number[] = Array.from(new Set<number>(
      (Array.isArray(body?.codigos) ? body.codigos : [])
        .map((c: unknown) => Number(String(c ?? '').replace(/\D/g, '')))
        .filter((c: number) => Number.isInteger(c) && c > 0),
    ))
    if (!codigos.length) return apiError(400, 'Escolha pelo menos um imóvel.')
    if (codigos.length > TETO_DE_IMOVEIS) return apiError(400, `No máximo ${TETO_DE_IMOVEIS} imóveis por envio.`)

    const linhas = await linhasDaOrganizacao(auth.organizationId)
    const linha = body?.integrationId
      ? linhas.find((l) => l.id === body.integrationId)
      : linhas.find((l) => l.padrao)
    if (!linha) return apiError(400, 'Essa linha de WhatsApp não existe aqui.')

    const quem = await nomeDeQuemPediu(auth, body?.quem)

    // ---------------- PARCERIA: a caixa de saída da Nay ----------------
    if (linha.tipo === 'whatsapp_zapi') {
      const resumo = await enfileirarNaNay(telefone, codigos, quem)
      return Response.json({ ok: true, linha: linha.nome, canal: 'parceria', resumo })
    }

    // ---------------- API OFICIAL: o CRM manda ----------------
    if (ehEspelhoDeTreino(telefone)) {
      return apiError(400, 'Número de treino: pela API oficial não sai. Use a Parceria.')
    }
    const variantes = telefoneVariantes(telefone)
    const [ultima] = await db
      .select({ quando: leadActivities.createdAt })
      .from(leadActivities)
      .innerJoin(leads, eq(leads.id, leadActivities.leadId))
      .where(and(
        eq(leadActivities.organizationId, auth.organizationId),
        inArray(leads.phone, variantes),
        isNull(leads.deletedAt),
        sql`${leadActivities.metadata}->>'direction' = 'inbound'`,
        sql`${leadActivities.metadata}->>'source' = 'facebook_cloud'`,
        gt(leadActivities.createdAt, new Date(Date.now() - 24 * 60 * 60 * 1000)),
      ))
      .orderBy(desc(leadActivities.createdAt))
      .limit(1)
    if (!ultima) {
      return apiError(400, 'Esse número não falou com a API oficial nas últimas 24h — a Meta não entrega. Use a Parceria.')
    }

    const adapter = getChannelAdapter(linha.tipo)
    const itens: { codigo: number; ok: boolean; motivo?: string; fotos?: number; fotos_que_falharam?: number }[] = []

    for (const codigo of codigos) {
      const c = await conferirParaOficial(telefone, codigo, quem)
      if (!c.pode || !c.card) {
        itens.push({ codigo, ok: false, motivo: c.motivo || 'não pode ir' })
        continue
      }

      // 1) o card; se falhar, a reserva das 24h é desfeita e nenhuma foto vai
      try {
        const r = await adapter.sendText(auth.organizationId, linha.id, telefone, c.card, false)
        await registrarEnvioNoCrm({
          organizationId: auth.organizationId, memberId: auth.memberId, telefone,
          texto: c.card, canal: 'whatsapp_cloud_official', whatsappMessageId: r.externalId || null,
          origem: 'disparo', extraMetadata: { imovel_codigo: codigo, disparo_por: quem },
        }).catch((e) => console.error('[disparo] card saiu mas não gravou no CRM:', e))
      } catch (err: any) {
        await liberarReserva(telefone, codigo).catch(() => {})
        itens.push({ codigo, ok: false, motivo: `o card não saiu: ${err?.message || 'erro'}` })
        continue
      }

      // 2) as fotos, uma a uma; uma que falha não derruba as outras
      let foram = 0
      let falharam = 0
      for (const url of c.fotos.slice(0, TETO_DE_FOTOS)) {
        try {
          const r = await adapter.sendMedia(auth.organizationId, linha.id, telefone, 'image', url, '', undefined, false)
          foram += 1
          await registrarEnvioNoCrm({
            organizationId: auth.organizationId, memberId: auth.memberId, telefone,
            texto: '📷 Imagem', canal: 'whatsapp_cloud_official', whatsappMessageId: r.externalId || null,
            origem: 'disparo', extraMetadata: { imovel_codigo: codigo, media_type: 'image', media_url: url },
          }).catch((e) => console.error('[disparo] foto saiu mas não gravou no CRM:', e))
        } catch {
          falharam += 1
        }
      }
      itens.push({ codigo, ok: true, fotos: foram, fotos_que_falharam: falharam })
    }

    const foi = itens.filter((i) => i.ok)
    const naoFoi = itens.filter((i) => !i.ok)
    const resumo = [
      foi.length
        ? `Mandei para ${telefone}: ` + foi.map((i) => `${i.codigo} (card e ${i.fotos} foto${i.fotos === 1 ? '' : 's'}`
            + (i.fotos_que_falharam ? `, ${i.fotos_que_falharam} falharam` : '') + ')').join(', ') + '.'
        : `Não mandei nada para ${telefone}:`,
      ...naoFoi.map((i) => `${i.codigo}: ${i.motivo}`),
    ].join('\n')

    return Response.json({ ok: true, linha: linha.nome, canal: 'oficial', resumo, itens })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Não consegui disparar.')
  }
}
