/**
 * POST /api/integrations/zapi/chats — importa as conversas da instância.
 *
 * A Z-API não tem endpoint de histórico e não guarda mensagens, então o máximo
 * que existe pra trazer de um número já em uso é QUEM são as conversas: nome e
 * telefone. O histórico do CRM começa quando o webhook é ligado.
 *
 * CONVERSA NÃO É LEAD. O número já tinha centenas de conversas antes do CRM —
 * fornecedor, pessoal, grupo — e jogar tudo isso no funil misturaria essa
 * bagunça com os leads de verdade (Agenda, site, indicação). Por isso a linha
 * criada aqui nasce SEM etapa: o Kanban só desenha card com etapa
 * (PipelineBoard filtra por `stage_id`), então ela aparece no Chat e em lugar
 * nenhum mais. Quem atender e decidir que aquilo virou negócio escolhe a etapa
 * no painel do lead — aí sim entra no funil, por decisão de gente.
 *
 * Não sobrescreve lead que já existe: o nome no CRM costuma ser melhor que o
 * nome da agenda do celular.
 *
 * Grupo é OPT-IN. O número está em dezenas de grupos que são conversa interna
 * (equipe, turmas, churrasco) e trazer todos só encheria o chat. Por isso o
 * padrão é não importar nenhum: quem quiser um grupo específico manda o nome
 * dele em `grupos`, e só ele entra.
 *
 * Grupo importado é endereçado pelo id ("1203...-group") no lugar do telefone e
 * fica sem etapa, como toda conversa — num grupo escrevem várias pessoas, e o
 * card de funil seria de quem, afinal?
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { integrations, leads } from '@/lib/schema'
import { and, eq, isNull } from 'drizzle-orm'
import { isUniqueViolation } from '@/lib/db-helpers'
import { telefoneCanonico } from '@/lib/leadSources'
import { ZAPI_INTEGRATION_TYPE, fetchZapiChats } from '@/lib/zapi'

const PAGINA_TAMANHO = 50
/** Teto por chamada — a Vercel corta a função em 60s e o resto vem na próxima. */
const MAX_PAGINAS_POR_CHAMADA = 6

export async function POST(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const body = await req.json().catch(() => ({}))
    const paginaInicial = Math.max(1, Number(body?.pagina) || 1)

    /**
     * Quais grupos trazer: `'todos'`, ou uma lista de nomes/ids. Ausente = nenhum.
     * A comparação é por nome sem diferenciar maiúscula/acento, porque quem pede
     * digita "lead magnet e crm", não o id "1203...-group".
     */
    const pedidoGrupos = body?.grupos
    const todosOsGrupos = pedidoGrupos === 'todos'
    const gruposEscolhidos = new Set(
      (Array.isArray(pedidoGrupos) ? pedidoGrupos : []).map((g: unknown) => chaveDeNome(String(g)))
    )
    const querEsteGrupo = (nome: string, id: string) =>
      todosOsGrupos || gruposEscolhidos.has(chaveDeNome(nome)) || gruposEscolhidos.has(chaveDeNome(id))

    const [integration] = await db
      .select({ id: integrations.id })
      .from(integrations)
      .where(and(
        eq(integrations.organizationId, auth.organizationId),
        eq(integrations.type, ZAPI_INTEGRATION_TYPE),
        isNull(integrations.deletedAt)
      ))
      .limit(1)
    if (!integration) return apiError(400, 'Integração Z-API não configurada.')

    let criados = 0
    let existentes = 0
    let grupos = 0
    let pagina = paginaInicial
    let acabou = false

    for (let i = 0; i < MAX_PAGINAS_POR_CHAMADA; i++) {
      const conversas = await fetchZapiChats(auth.organizationId, pagina, PAGINA_TAMANHO)
      if (conversas.length === 0) {
        acabou = true
        break
      }

      for (const conversa of conversas) {
        // Grupo é endereçado pelo id, não por telefone — telefoneCanonico o
        // destruiria (ele só entende dígitos).
        //
        // telefoneCanonico e NÃO normalizePhone: o normalize deixa passar os 12
        // dígitos (celular na forma antiga, sem o nono) exatamente como vieram,
        // e aí a mesma pessoa vira duas linhas — a conversa importada com 12 e o
        // lead da Agenda com 13. Aconteceu de verdade em 17 contatos na primeira
        // importação.
        const phone = conversa.isGroup
          ? String(conversa.phone || '').trim()
          : telefoneCanonico(conversa.phone)
        if (!phone) continue

        // Comunidade e lista de transmissão chegam como um id numérico gigante
        // no lugar do telefone. Não são conversa com ninguém: viravam uma linha
        // no chat chamada "120363404701403742", que não dá pra abrir nem
        // responder.
        if (!conversa.isGroup && phone.replace(/\D/g, '').length > 14) continue
        if (conversa.isGroup) {
          if (!querEsteGrupo(String(conversa.name || ''), phone)) {
            grupos++
            continue
          }
        }

        const [existente] = await db
          .select({ id: leads.id })
          .from(leads)
          .where(and(
            eq(leads.organizationId, auth.organizationId),
            eq(leads.phone, phone),
            isNull(leads.deletedAt)
          ))
          .limit(1)

        if (existente) {
          existentes++
          continue
        }

        try {
          await db.insert(leads).values({
            organizationId: auth.organizationId,
            title: (conversa.name || '').trim() || phone,
            phone,
            isGroup: !!conversa.isGroup,
            integrationId: integration.id,
            // Sem etapa de propósito — ver o cabeçalho do arquivo.
            stageId: null,
            // A conversa é antiga: usar "agora" faria todas elas irem pro topo da
            // lista de conversas como se tivessem acabado de chegar.
            lastActivityAt: horaDaConversa(conversa.lastMessageTime),
            // A lista do Chat mostra CONVERSA, não contato: ela esconde quem
            // tem `last_activity_type` nulo, e é isso que impede a planilha de
            // 644 contatos de virar 644 entradas vazias (ver LeadList).
            //
            // Conversa importada do WhatsApp é o outro caso: ela EXISTE, com
            // histórico no aparelho, só não tem as mensagens aqui — a Z-API não
            // devolve histórico. Marcar o tipo é o que a faz aparecer no chat,
            // que é o ponto de importar. O horário vem do WhatsApp, então a
            // ordem da lista continua sendo a ordem real das conversas.
            // A conversa EXISTE e a última atividade dela foi uma mensagem de
            // WhatsApp — é isso que fica gravado, sem recorte nenhum.
            //
            // Quais dessas aparecem na lista é decisão de TELA, não de banco:
            // quem recorta é o LeadList (conversa parada há mais de 30 dias sai
            // da lista mas continua achável na busca). Guardar o recorte aqui
            // significaria destruir dado pra mudar exibição — e mudar de ideia
            // sobre o recorte exigiria reimportar tudo.
            lastActivityType: 'whatsapp',
            // `origem` e não `lead_source`: `lead_source` é o que marca CANAL DE
            // AQUISIÇÃO e alimenta a coluna "Fonte:" do Kanban e o dashboard.
            // Conversa importada não é aquisição, e usar a mesma chave a faria
            // aparecer nos dois lugares como se fosse.
            customAttributes: { origem: 'conversa_whatsapp' },
          })
          criados++
        } catch (err) {
          if (!isUniqueViolation(err)) throw err
          existentes++
        }
      }

      if (conversas.length < PAGINA_TAMANHO) {
        acabou = true
        break
      }
      pagina++
    }

    return Response.json({
      criados,
      existentes,
      grupos_ignorados: grupos,
      proxima_pagina: acabou ? null : pagina + 1,
      fim: acabou,
    })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}

/** "Lead Magnet e CRM" e "lead magnet e crm" viram a mesma chave. */
function chaveDeNome(valor: string): string {
  return valor
    .trim()
    .toLowerCase()
    .normalize('NFD')
    .replace(/\p{M}/gu, '')
}

/** `lastMessageTime` vem em milissegundos (às vezes como string). */
function horaDaConversa(valor: unknown): Date | null {
  const n = Number(valor)
  if (!Number.isFinite(n) || n <= 0) return null
  const data = new Date(n)
  return Number.isNaN(data.getTime()) ? null : data
}
