/**
 * Em que etapa entra um lead novo — a primeira etapa do pipeline DA LINHA dele.
 *
 * Tel, 26/09/2026: "vai ter essa divisão no pipeline cada pipeline para cada
 * zap". Os dois pipelines existem:
 *
 *   WhatsApp API (captação)  ->  Recebeu mensagem · Em atendimento ·
 *                                Atualizou cadastro do seu imóvel · Sugeriu outro imóvel
 *                                (Tel, 28/09; antes: Contactando · Follow up · Imóvel novo)
 *   WhatsApp Parceria        ->  Agendou visita · Follow up · Fechou contrato
 *
 * O QUE ESTAVA ERRADO. Todo lugar que cria lead pegava a primeira etapa assim:
 *
 *     SELECT id FROM pipeline_stages WHERE organization_id = ... ORDER BY rank LIMIT 1
 *
 * Sem filtrar por pipeline. Com um pipeline só isso funcionava; com dois, os
 * dois têm etapa de rank 1 ("Contactando" e "Agendou visita") e o Postgres
 * devolve qualquer uma das duas -- então um corretor da parceria podia nascer
 * dentro do pipeline da captação, e ninguém teria como notar olhando a tela.
 *
 * Aqui a etapa sai do pipeline certo, escolhido pelo NOME da linha. Se o
 * pipeline daquela linha não existir, cai na primeira etapa que houver -- melhor
 * um lead no pipeline errado que um lead sem etapa nenhuma, que é o que não
 * aparece em tela nenhuma.
 */
import { and, asc, eq, ilike, isNull, sql } from 'drizzle-orm'
import { db } from './db'
import { pipelineStages, pipelines } from './schema'

/**
 * A etapa "Em atendimento" DO MESMO PIPELINE em que o lead já está -- e só se
 * ela vier DEPOIS da etapa atual. Null = não mexer.
 *
 * Tel, 28/09: o funil da captação passou a ter "Em atendimento". Quatro
 * lugares movem o lead para essa etapa quando alguém responde (o chat do CRM,
 * o celular pela Z-API, o "/código" e a Evolution), e todos a procuravam pelo
 * NOME na organização inteira, sem olhar o pipeline. Enquanto ela não existia,
 * não faziam nada. Existindo só na captação, responder um corretor da Parceria
 * jogaria o card dele no funil da captação -- e responder de novo quem já
 * "Atualizou cadastro do seu imóvel" o puxaria para trás.
 *
 * Então: só lead que já está num funil (conversa não vira card sozinha), só
 * dentro do pipeline dele, e só para a frente.
 */
export async function etapaEmAtendimentoDoMesmoPipeline(
  organizationId: string,
  etapaAtual: string | null | undefined,
): Promise<string | null> {
  if (!etapaAtual) return null
  const r = await db.execute(sql`
    SELECT s2.id
      FROM pipeline_stages s1
      JOIN pipeline_stages s2 ON s2.pipeline_id = s1.pipeline_id
     WHERE s1.id = ${etapaAtual}
       AND s1.organization_id = ${organizationId}
       AND s2.deleted_at IS NULL
       AND s2.name ILIKE 'Em atendimento'
       AND s2.rank > s1.rank
     LIMIT 1`)
  return (r.rows[0] as { id: string } | undefined)?.id ?? null
}

export type CanalDoLead = 'whatsapp_cloud_official' | 'whatsapp_zapi' | string | null | undefined

/**
 * O nome do pipeline de cada linha, como está cadastrado. UM FUNIL POR NÚMERO
 * (Pedro, 29/09/2026: "vai ter uma pipeline para cada número, podendo serem
 * alteradas por abas lá em cima"; migração crm/drizzle/0127). Até 29/09 a
 * Oficial e a captação dividiam "WhatsApp API (captação)", que virou o da
 * Oficial.
 */
export const PIPELINE_DA_LINHA: Record<string, string> = {
  whatsapp_cloud_official: 'WhatsApp API Oficial',
  whatsapp_zapi: 'WhatsApp Parceria',
  whatsapp_zapi_captacao: 'WhatsApp Captação',
}

/** O pipeline da linha pelo tipo da integração; sem linha conhecida, null. */
export function pipelineDaLinha(tipo: string | null | undefined): string | null {
  return PIPELINE_DA_LINHA[String(tipo || '')] ?? null
}

export async function etapaInicialDaLinha(
  organizationId: string,
  canal: CanalDoLead,
): Promise<string | null> {
  const nome = PIPELINE_DA_LINHA[String(canal || '')] || PIPELINE_DA_LINHA.whatsapp_zapi

  const [doPipeline] = await db
    .select({ id: pipelineStages.id })
    .from(pipelineStages)
    .innerJoin(pipelines, eq(pipelines.id, pipelineStages.pipelineId))
    .where(and(
      eq(pipelineStages.organizationId, organizationId),
      isNull(pipelineStages.deletedAt),
      isNull(pipelines.deletedAt),
      ilike(pipelines.name, nome),
    ))
    .orderBy(asc(pipelineStages.rank))
    .limit(1)

  if (doPipeline) return doPipeline.id

  // Reserva: qualquer primeira etapa. Lead sem etapa não aparece no Pipeline.
  const [qualquer] = await db
    .select({ id: pipelineStages.id })
    .from(pipelineStages)
    .where(and(
      eq(pipelineStages.organizationId, organizationId),
      isNull(pipelineStages.deletedAt),
    ))
    .orderBy(asc(pipelineStages.rank))
    .limit(1)

  return qualquer?.id ?? null
}
