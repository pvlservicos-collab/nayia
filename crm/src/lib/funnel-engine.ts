import { db } from '@/lib/db'
import {
  leads, leadActivities, messageFunnels, funnelBlocks, funnelConnections,
  funnelExecutions, funnelClickEvents, funnelResponseEvents, leadStageHistory,
} from '@/lib/schema'
import { eq, and, lte, asc, sql } from 'drizzle-orm'
import { publishEvent, channels, events } from '@/lib/realtime'
import { getAutomationAdapter } from '@/lib/channels/registry'
import { randomBytes } from 'crypto'
import { isUniqueViolation } from '@/lib/db-helpers'

const MAX_STEPS_PER_RUN = 25

/**
 * Base das URLs rastreaveis ({link} nas mensagens do funil).
 *
 * A ordem importa: VERCEL_PROJECT_PRODUCTION_URL e o dominio estavel do projeto,
 * VERCEL_URL e o do deploy especifico (muda a cada push, serve pra preview).
 * NEXT_PUBLIC_APP_URL cobre quem roda fora da Vercel (a VPS, por exemplo).
 *
 * O ultimo fallback e o dominio deste projeto — antes apontava pro
 * 'whatsappfm.vercel.app', do projeto de onde este codigo foi copiado, o que
 * mandaria o cliente pra um link de outra aplicacao se as env faltassem.
 */
export function getBaseUrl() {
  if (process.env.VERCEL_PROJECT_PRODUCTION_URL) return `https://${process.env.VERCEL_PROJECT_PRODUCTION_URL}`
  if (process.env.VERCEL_URL) return `https://${process.env.VERCEL_URL}`
  if (process.env.NEXT_PUBLIC_APP_URL) return process.env.NEXT_PUBLIC_APP_URL.replace(/\/+$/, '')
  return 'https://titacrm.vercel.app'
}

function waitMs(value: number, unit: string) {
  const factor: Record<string, number> = {
    seconds: 1000,
    minutes: 60 * 1000,
    hours: 60 * 60 * 1000,
    days: 24 * 60 * 60 * 1000,
  }
  return value * (factor[unit] || factor.minutes)
}

/**
 * Atraso aleatório (20-30 min) entre uma mensagem automática e a próxima.
 *
 * O tick roda todo minuto e processa TODA espera vencida na hora — normal
 * quando cada lead vence em um minuto diferente, mas depois de um problema
 * (Z-API caiu, cron parou, etc.) várias esperas vencem juntas, e sem isso todo
 * mundo que tava na fila recebia a mensagem no mesmo minuto. Só a mais antiga
 * da leva sai na hora; as outras ganham esse atraso, que espalha o resto.
 */
function atrasoDeFila(): number {
  return (20 + Math.random() * 10) * 60 * 1000
}

async function getNextBlock(funnelId: string, sourceBlockId: string, branch: 'default' | 'yes' | 'no') {
  const [conn] = await db.select({ targetBlockId: funnelConnections.targetBlockId })
    .from(funnelConnections)
    .where(and(
      eq(funnelConnections.funnelId, funnelId),
      eq(funnelConnections.sourceBlockId, sourceBlockId),
      eq(funnelConnections.branch, branch),
    ))
    .limit(1)

  if (!conn) return null

  const [block] = await db.select().from(funnelBlocks).where(eq(funnelBlocks.id, conn.targetBlockId)).limit(1)
  return block || null
}

/**
 * Primeiro nome, do jeito que uma pessoa chamaria: "OTONIEL de paula" → "Otoniel".
 *
 * `{nome}` antes virava o título inteiro do lead, e as mensagens do funil saíam
 * "Oi Otoniel de paula!" ou "Oi Pedro Victor Site VdT!" — o que ninguém da
 * equipe escreveria, e é o jeito mais rápido de uma mensagem automática
 * parecer automática.
 *
 * Se o título não tem nome (lead que ficou com o telefone no lugar), devolve
 * vazio: "Oi 5511987654321!" é pior do que só "Oi!".
 */
function primeiroNome(titulo: string | null | undefined): string {
  const primeiro = (titulo || '').trim().split(/\s+/)[0] || ''
  if (!/\p{L}/u.test(primeiro)) return ''
  return primeiro.charAt(0).toLocaleUpperCase('pt-BR') + primeiro.slice(1).toLocaleLowerCase('pt-BR')
}

async function renderMessage(text: string, opts: { leadTitle: string; executionId: string; blockId: string; trackableUrl?: string; context?: Record<string, any> }) {
  const nome = primeiroNome(opts.leadTitle)
  let rendered = text
    // {nome_completo} existe pra quando o nome inteiro for mesmo o que se quer.
    .replace(/\{nome_completo\}/gi, (opts.leadTitle || '').trim())
    .replace(/\{nome\}/gi, nome)
  // Sem nome, "Oi {nome}!" viraria "Oi !" — junta a pontuação de volta.
  if (!nome) rendered = rendered.replace(/ +([!?,.])/g, '$1').replace(/ {2,}/g, ' ')

  if (rendered.includes('{link}') && opts.trackableUrl) {
    const token = randomBytes(8).toString('hex')
    await db.insert(funnelClickEvents).values({
      executionId: opts.executionId,
      blockId: opts.blockId,
      token,
      targetUrl: opts.trackableUrl,
    })
    rendered = rendered.replace(/\{link\}/gi, `${getBaseUrl()}/f/${token}`)
  }

  return rendered
}

async function sendMessageBlock(
  execution: { id: string; funnelId: string; organizationId: string; leadId: string; context?: any },
  block: { id: string; config: any }
): Promise<{ variante: string | null } | undefined> {
  const [lead] = await db.select({ id: leads.id, title: leads.title, phone: leads.phone })
    .from(leads).where(eq(leads.id, execution.leadId)).limit(1)
  if (!lead) return

  const config = block.config as {
    text?: string
    trackableUrl?: string
    variantes?: { id: string; texto: string }[]
  }

  /*
   * Teste A/B/C: o bloco pode ter várias versões da mesma mensagem.
   *
   * Uma é sorteada por lead, com peso igual, e fica gravada na própria
   * mensagem (`metadata.variante`). É isso que depois permite dizer qual texto
   * fez mais gente responder — sem isso só dava pra contar envios, e a pergunta
   * "qual mensagem funciona melhor" continuaria sem resposta.
   *
   * Sorteio por lead, e não rodízio, de propósito: rodízio exige guardar de
   * quem foi a vez e dá viés quando os disparos não chegam na mesma ordem em
   * que os leads entram.
   */
  const variantes = Array.isArray(config?.variantes)
    ? config.variantes.filter((v) => v && typeof v.texto === 'string' && v.texto.trim())
    : []
  const variante = variantes.length > 0 ? variantes[Math.floor(Math.random() * variantes.length)] : null
  const textoDaMensagem = variante ? variante.texto : config?.text || ''

  const content = await renderMessage(textoDaMensagem, {
    leadTitle: lead.title,
    executionId: execution.id,
    blockId: block.id,
    trackableUrl: config?.trackableUrl,
    context: execution.context,
  })

  const metadata: Record<string, any> = {
    source: 'funnel',
    direction: 'outbound',
    automated: true,
    funnel_id: execution.funnelId,
    execution_id: execution.id,
    block_id: block.id,
    ...(variante ? { variante: variante.id } : {}),
  }

  if (!lead.phone) {
    metadata.send_status = 'failed'
    metadata.send_error = 'Lead sem telefone cadastrado.'
  } else {
    // Disparo de funil sai SEMPRE pelo canal de automação (Z-API), nunca pelo
    // canal por onde o lead falou. Antes isto chamava a Cloud API direto: além de
    // amarrar a automação a um provedor, era o motivo de o primeiro contato não
    // sair — a API oficial exige template aprovado pra iniciar conversa, e o funil
    // existe justamente pra iniciar conversa.
    const adapter = getAutomationAdapter()
    try {
      const result = await adapter.sendText(execution.organizationId, null, lead.phone, content)
      if (result.externalId) metadata[adapter.metadataIdKey] = result.externalId
      metadata.channel = 'automacao'
      metadata.send_status = 'sent'

      // Mesma correção do envio manual: se o canal só conseguiu entregar na
      // outra forma do número (com/sem nono dígito), o lead passa a guardar a
      // que funciona.
      // Só telefone de verdade (ver a mesma trava no envio manual).
      if (
        result.recipienteCorrigido &&
        /^\d{10,15}$/.test(result.recipienteCorrigido) &&
        result.recipienteCorrigido !== lead.phone
      ) {
        metadata.telefone_corrigido = result.recipienteCorrigido
        try {
          await db.update(leads).set({ phone: result.recipienteCorrigido }).where(eq(leads.id, lead.id))
        } catch (err) {
          console.error('[funnel] falha ao gravar o telefone corrigido:', err)
        }
      }
    } catch (err: any) {
      metadata.send_status = 'failed'
      metadata.send_error = err.message || 'Erro ao enviar mensagem.'
      // Falha de disparo automático não tem agente olhando a tela na hora — sem
      // este log ela só existiria dentro de lead_activities.metadata.
      console.error(`[funnel] falha ao disparar mensagem para o lead ${lead.id}:`, err)
    }
  }

  /*
   * A Z-API devolve um "eco" de toda mensagem que enviamos (notifySentByMe),
   * e o webhook desse eco corre em paralelo com este código. Se ele chegar
   * primeiro, grava a mensagem com o mesmo zapi_message_id — e este INSERT bate
   * no índice único e estoura.
   *
   * O estouro não era só barulho: a execução do funil travava no meio, e a
   * mensagem ficava registrada como se um HUMANO tivesse mandado (é assim que o
   * eco se grava). Aí, quando o lead respondesse, ninguém saberia que era
   * resposta à automação — nem o som grande, nem o aviso no grupo.
   *
   * Então: se o eco já gravou, a linha dele é adotada e recebe os dados do
   * funil. O resultado fica idêntico, venha quem vier primeiro.
   */
  let activity: { id: string }
  try {
    ;[activity] = await db.insert(leadActivities).values({
      organizationId: execution.organizationId,
      leadId: lead.id,
      type: 'whatsapp',
      content,
      metadata,
    }).returning({ id: leadActivities.id })
  } catch (err) {
    const idExterno = metadata.zapi_message_id
    if (!isUniqueViolation(err) || !idExterno) throw err
    const [eco] = await db.select({ id: leadActivities.id, metadata: leadActivities.metadata })
      .from(leadActivities)
      .where(sql`${leadActivities.metadata}->>'zapi_message_id' = ${idExterno}`)
      .limit(1)
    if (!eco) throw err
    await db.update(leadActivities)
      .set({ metadata: { ...(eco.metadata as object), ...metadata } })
      .where(eq(leadActivities.id, eco.id))
    activity = { id: eco.id }
  }

  await db.update(leads).set({
    lastMessageContent: content,
    lastMessageSenderType: 'automated',
    lastActivityAt: new Date(),
    // Sem isto a conversa não aparecia na lista do Chat: quem manda pelo CRM
    // grava `last_activity_type`, o funil não gravava, e a lista usa esse
    // marcador. O lead novo só surgia no chat quando ELE respondia.
    lastActivityType: 'whatsapp',
    isUnread: true,
  }).where(eq(leads.id, lead.id))

  await publishEvent(channels.leadActivities(lead.id), events.ACTIVITY_CREATED, { id: activity.id })
  await publishEvent(channels.orgLeads(execution.organizationId), events.LEAD_UPDATED, { id: lead.id })

  return { variante: variante ? variante.id : null }
}

/**
 * Bloco "Mover de etapa" — leva o lead para outra coluna do Kanban.
 *
 * É o que fecha o fluxo pedido: assim que o lead responde, o ramo "Sim" da
 * condição cai aqui e ele sai de "Contactado por IA" para "Atendimento por
 * humano" sozinho, sem ninguém arrastar card.
 *
 * Registra em lead_stage_history igual a uma movimentação manual, pra a linha do
 * tempo do lead não ter buraco quando quem moveu foi o funil.
 */
async function moveStageBlock(
  execution: { organizationId: string; leadId: string },
  block: { config: any }
) {
  const stageId = (block.config as { stageId?: string })?.stageId
  if (!stageId) return

  const [lead] = await db.select({ stageId: leads.stageId })
    .from(leads).where(eq(leads.id, execution.leadId)).limit(1)
  if (!lead) return
  if (lead.stageId === stageId) return // já está lá — não polui o histórico

  await db.update(leads)
    .set({ stageId, updatedAt: new Date() })
    .where(eq(leads.id, execution.leadId))

  await db.insert(leadStageHistory).values({
    organizationId: execution.organizationId,
    leadId: execution.leadId,
    fromStageId: lead.stageId,
    toStageId: stageId,
  })

  await publishEvent(channels.orgLeads(execution.organizationId), events.LEAD_UPDATED, { id: execution.leadId })
}

/**
 * Avança a execução do funil a partir do bloco atual, processando blocos em sequência
 * até encontrar um bloco que precise aguardar (espera, condição) ou finalizar (fim).
 */
export async function advanceExecution(executionId: string) {
  for (let step = 0; step < MAX_STEPS_PER_RUN; step++) {
    const [execution] = await db.select().from(funnelExecutions).where(eq(funnelExecutions.id, executionId)).limit(1)
    if (!execution || !execution.currentBlockId) return

    const [block] = await db.select().from(funnelBlocks).where(eq(funnelBlocks.id, execution.currentBlockId)).limit(1)
    if (!block) {
      await db.update(funnelExecutions).set({ status: 'stopped', updatedAt: new Date() }).where(eq(funnelExecutions.id, executionId))
      return
    }

    if (block.type === 'trigger') {
      const next = await getNextBlock(execution.funnelId, block.id, 'default')
      if (!next) {
        await db.update(funnelExecutions).set({ status: 'completed', updatedAt: new Date() }).where(eq(funnelExecutions.id, executionId))
        return
      }
      await db.update(funnelExecutions).set({ currentBlockId: next.id, updatedAt: new Date() }).where(eq(funnelExecutions.id, executionId))
      continue
    }

    if (block.type === 'message') {
      /*
       * Se o lead já teve contato de verdade (respondeu, ou um humano já falou
       * com ele) desde o último passo do funil, não manda a automática por
       * cima — sobretudo depois de uma fila acumulada (Z-API caiu, tick
       * atrasou), mandar "Recebemos sua aplicação!" horas depois de alguém já
       * ter conversado com o lead fica robótico e fora de contexto. A execução
       * encerra aqui, como se tivesse concluído normalmente.
       */
      const contextoAtual = (execution.context as any) || {}
      const desde = contextoAtual.lastMessageAt ? new Date(contextoAtual.lastMessageAt) : execution.startedAt
      if (await temContatoRealDesde(execution.leadId, desde as Date)) {
        await db.update(funnelExecutions).set({ status: 'completed', updatedAt: new Date() }).where(eq(funnelExecutions.id, executionId))
        return
      }

      const enviada = await sendMessageBlock(execution as any, block as any)
      await db.update(funnelExecutions).set({
        context: {
          ...(execution.context as object),
          lastMessageAt: new Date().toISOString(),
          ...(enviada?.variante ? { variante: enviada.variante } : {}),
        },
        updatedAt: new Date(),
      }).where(eq(funnelExecutions.id, executionId))

      const next = await getNextBlock(execution.funnelId, block.id, 'default')
      if (!next) {
        await db.update(funnelExecutions).set({ status: 'completed', updatedAt: new Date() }).where(eq(funnelExecutions.id, executionId))
        return
      }
      await db.update(funnelExecutions).set({ currentBlockId: next.id, updatedAt: new Date() }).where(eq(funnelExecutions.id, executionId))
      continue
    }

    if (block.type === 'wait') {
      const config = block.config as { value?: number; unit?: string }
      const waitUntil = new Date(Date.now() + waitMs(config?.value || 0, config?.unit || 'minutes'))
      await db.update(funnelExecutions).set({ status: 'waiting', waitUntil, updatedAt: new Date() }).where(eq(funnelExecutions.id, executionId))
      return
    }

    if (block.type === 'condition') {
      const config = block.config as { value?: number; unit?: string }
      const waitUntil = new Date(Date.now() + waitMs(config?.value || 0, config?.unit || 'minutes'))
      await db.update(funnelExecutions).set({ status: 'waiting_condition', waitUntil, updatedAt: new Date() }).where(eq(funnelExecutions.id, executionId))
      return
    }

    if (block.type === 'move_stage') {
      await moveStageBlock(execution as any, block as any)
      const next = await getNextBlock(execution.funnelId, block.id, 'default')
      if (!next) {
        await db.update(funnelExecutions).set({ status: 'completed', updatedAt: new Date() }).where(eq(funnelExecutions.id, executionId))
        return
      }
      await db.update(funnelExecutions).set({ currentBlockId: next.id, updatedAt: new Date() }).where(eq(funnelExecutions.id, executionId))
      continue
    }

    if (block.type === 'end') {
      await db.update(funnelExecutions).set({ status: 'completed', currentBlockId: null, updatedAt: new Date() }).where(eq(funnelExecutions.id, executionId))
      return
    }

    // Tipo desconhecido: encerra para evitar loop
    await db.update(funnelExecutions).set({ status: 'stopped', updatedAt: new Date() }).where(eq(funnelExecutions.id, executionId))
    return
  }

  // Excedeu o limite de passos (possível ciclo na configuração do funil)
  await db.update(funnelExecutions).set({ status: 'stopped', updatedAt: new Date() }).where(eq(funnelExecutions.id, executionId))
}

/**
 * O lead terminou o formulário do fim da Agenda?
 *
 * Ver o uso em processTick (conditionType `formulario_agenda`).
 */
export async function preencheuFormularioDaAgenda(leadId: string): Promise<boolean> {
  const [lead] = await db
    .select({ customAttributes: leads.customAttributes })
    .from(leads)
    .where(eq(leads.id, leadId))
    .limit(1)
  if (!lead) return false
  const atributos = (lead.customAttributes ?? {}) as Record<string, unknown>
  return ['area', 'aumento', 'investimento'].some((campo) => {
    const valor = atributos[campo]
    return typeof valor === 'string' && valor.trim() !== ''
  })
}

/**
 * Inicia uma nova execução de funil para um lead, a partir do bloco "trigger".
 */
export async function startExecution(funnelId: string, organizationId: string, leadId: string, context: Record<string, any> = {}, triggerBlockId?: string) {
  let triggerBlock: { id: string } | undefined = triggerBlockId ? { id: triggerBlockId } : undefined

  if (!triggerBlock) {
    const [found] = await db.select({ id: funnelBlocks.id }).from(funnelBlocks)
      .where(and(eq(funnelBlocks.funnelId, funnelId), eq(funnelBlocks.type, 'trigger')))
      .limit(1)
    triggerBlock = found
  }
  if (!triggerBlock) return null

  const [execution] = await db.insert(funnelExecutions).values({
    funnelId,
    organizationId,
    leadId,
    currentBlockId: triggerBlock.id,
    status: 'running',
    context,
  }).returning({ id: funnelExecutions.id })

  await advanceExecution(execution.id)
  return execution.id
}

/**
 * Processa todas as execuções pendentes: esperas vencidas e checagens de "Respondeu?".
 * Deve ser chamado periodicamente (ex: Schedule Trigger do n8n a cada poucos minutos).
 */
export async function processTick() {
  const now = new Date()
  let processed = 0

  // Esperas simples vencidas → segue para o próximo bloco. Ordenada por
  // vencimento: quem venceu primeiro sai primeiro, o resto de uma leva grande
  // é espalhado (ver atrasoDeFila).
  const dueWaits = await db.select().from(funnelExecutions)
    .where(and(eq(funnelExecutions.status, 'waiting'), lte(funnelExecutions.waitUntil, now)))
    .orderBy(asc(funnelExecutions.waitUntil))

  for (let i = 0; i < dueWaits.length; i++) {
    const execution = dueWaits[i]
    if (!execution.currentBlockId) continue

    if (i > 0) {
      await db.update(funnelExecutions)
        .set({ waitUntil: new Date(Date.now() + atrasoDeFila()), updatedAt: new Date() })
        .where(and(eq(funnelExecutions.id, execution.id), eq(funnelExecutions.status, 'waiting')))
      continue
    }

    /*
     * Reivindica a execução antes de mexer nela: só segue quem conseguir virar o
     * status de 'waiting' pra 'running'.
     *
     * O tick roda a cada minuto. Se um tick demorar mais que isso, o seguinte
     * encontra a MESMA espera ainda como 'waiting' — ler e depois atualizar
     * deixava os dois avançarem, e o lead recebia a mensagem duas vezes. O
     * UPDATE condicional é atômico no Postgres: só um dos dois ganha.
     */
    const [reivindicada] = await db.update(funnelExecutions)
      .set({ status: 'running', updatedAt: new Date() })
      .where(and(eq(funnelExecutions.id, execution.id), eq(funnelExecutions.status, 'waiting')))
      .returning({ id: funnelExecutions.id })
    if (!reivindicada) continue

    const next = await getNextBlock(execution.funnelId, execution.currentBlockId, 'default')
    if (!next) {
      await db.update(funnelExecutions).set({ status: 'completed', updatedAt: new Date() }).where(eq(funnelExecutions.id, execution.id))
      continue
    }
    await db.update(funnelExecutions).set({ currentBlockId: next.id, updatedAt: new Date() }).where(eq(funnelExecutions.id, execution.id))
    await advanceExecution(execution.id)
    processed++
  }

  // Condições "Respondeu?" → checa se o lead respondeu desde a última mensagem
  const pendingConditions = await db.select().from(funnelExecutions)
    .where(eq(funnelExecutions.status, 'waiting_condition'))
    .orderBy(asc(funnelExecutions.waitUntil))

  // Só o ramo "não" (prazo esgotado, ver abaixo) manda mensagem — "sim" é
  // reação a uma resposta que o próprio lead já mandou, sem rajada nenhuma pra
  // espalhar. Mesmo espalhamento do loop de esperas, só nesse ramo.
  let timeoutsLiberados = 0

  for (const execution of pendingConditions) {
    if (!execution.currentBlockId) continue
    const context = (execution.context as any) || {}

    const [block] = await db.select({ config: funnelBlocks.config }).from(funnelBlocks)
      .where(eq(funnelBlocks.id, execution.currentBlockId)).limit(1)
    const conditionType = (block?.config as any)?.conditionType || 'respondeu'

    // Verifica se a condição configurada já foi satisfeita
    let responded = false
    if (conditionType === 'formulario_agenda') {
      /*
       * "A pessoa terminou o formulário do fim da Agenda?"
       *
       * O site da Agenda só manda área / aumento / investimento quando o CTA de
       * 4 passos é concluído — então ter qualquer um deles preenchido É a
       * confirmação de que ela se cadastrou. Enquanto não tiver, a execução
       * segue esperando, e no fim do prazo cai no ramo "não" (a mensagem).
       *
       * É assim que o cancelamento acontece sozinho: quem preenche durante a
       * espera sai pelo ramo "sim", que termina o fluxo sem enviar nada.
       */
      responded = await preencheuFormularioDaAgenda(execution.leadId)
    } else if (conditionType === 'clique_pagina') {
      responded = !!context.viu_pagina || await hasClickedSince(execution.id)
    } else if (conditionType === 'pagamento') {
      responded = !!context.pagamento_confirmado
    } else {
      const lastMessageAt = context.lastMessageAt ? new Date(context.lastMessageAt) : execution.startedAt
      responded = await hasRespondedSince(execution.leadId, lastMessageAt as Date)
    }

    if (responded) {
      await db.insert(funnelResponseEvents).values({ executionId: execution.id, blockId: execution.currentBlockId, branch: 'yes' })
      const next = await getNextBlock(execution.funnelId, execution.currentBlockId, 'yes')
      if (!next) {
        await db.update(funnelExecutions).set({ status: 'completed', updatedAt: new Date() }).where(eq(funnelExecutions.id, execution.id))
      } else {
        await db.update(funnelExecutions).set({ currentBlockId: next.id, status: 'running', updatedAt: new Date() }).where(eq(funnelExecutions.id, execution.id))
        await advanceExecution(execution.id)
      }
      processed++
    } else if (execution.waitUntil && execution.waitUntil <= now) {
      if (timeoutsLiberados > 0) {
        await db.update(funnelExecutions)
          .set({ waitUntil: new Date(Date.now() + atrasoDeFila()), updatedAt: new Date() })
          .where(and(eq(funnelExecutions.id, execution.id), eq(funnelExecutions.status, 'waiting_condition')))
        continue
      }
      timeoutsLiberados++

      await db.insert(funnelResponseEvents).values({ executionId: execution.id, blockId: execution.currentBlockId, branch: 'no' })
      const next = await getNextBlock(execution.funnelId, execution.currentBlockId, 'no')
      if (!next) {
        await db.update(funnelExecutions).set({ status: 'completed', updatedAt: new Date() }).where(eq(funnelExecutions.id, execution.id))
      } else {
        await db.update(funnelExecutions).set({ currentBlockId: next.id, status: 'running', updatedAt: new Date() }).where(eq(funnelExecutions.id, execution.id))
        await advanceExecution(execution.id)
      }
      processed++
    }
  }

  return { processed, checkedWaits: dueWaits.length, checkedConditions: pendingConditions.length }
}

/**
 * Resolve imediatamente uma execução parada em "waiting_condition" para o
 * ramo informado (yes/no), sem esperar o próximo tick do cron. Usado quando
 * um webhook externo já confirma a condição (ex: lead visitou a página).
 */
export async function resolveConditionNow(executionId: string, branch: 'yes' | 'no') {
  const [execution] = await db.select().from(funnelExecutions).where(eq(funnelExecutions.id, executionId)).limit(1)
  if (!execution || !execution.currentBlockId || execution.status !== 'waiting_condition') return

  await db.insert(funnelResponseEvents).values({ executionId: execution.id, blockId: execution.currentBlockId, branch })

  const next = await getNextBlock(execution.funnelId, execution.currentBlockId, branch)
  if (!next) {
    await db.update(funnelExecutions).set({ status: 'completed', updatedAt: new Date() }).where(eq(funnelExecutions.id, execution.id))
    return
  }
  await db.update(funnelExecutions).set({ currentBlockId: next.id, status: 'running', updatedAt: new Date() }).where(eq(funnelExecutions.id, execution.id))
  await advanceExecution(execution.id)
}

async function hasClickedSince(executionId: string) {
  const [row] = await db.select({ id: funnelClickEvents.id }).from(funnelClickEvents)
    .where(and(eq(funnelClickEvents.executionId, executionId), eq(funnelClickEvents.clicked, true)))
    .limit(1)
  return !!row
}

async function hasRespondedSince(leadId: string, since: Date) {
  const { sql } = await import('drizzle-orm')
  const [row] = await db.select({ id: leadActivities.id }).from(leadActivities)
    .where(and(
      eq(leadActivities.leadId, leadId),
      sql`${leadActivities.metadata}->>'direction' = 'inbound'`,
      sql`${leadActivities.createdAt} > ${since.toISOString()}`,
    ))
    .limit(1)
  return !!row
}

/** O lead respondeu, ou um humano da equipe já falou com ele, desde `since`? */
async function temContatoRealDesde(leadId: string, since: Date) {
  const [row] = await db.select({ id: leadActivities.id }).from(leadActivities)
    .where(and(
      eq(leadActivities.leadId, leadId),
      sql`(${leadActivities.metadata}->>'direction' = 'inbound' OR ${leadActivities.metadata}->>'source' = 'human')`,
      sql`${leadActivities.createdAt} > ${since.toISOString()}`,
    ))
    .limit(1)
  return !!row
}
