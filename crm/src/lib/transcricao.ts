/**
 * A TRANSCRIÇÃO DO ÁUDIO, EMBAIXO DELE, COMO NO WHATSAPP (Pedro, 29/09/2026):
 * "usar api de transcrição do gpt e por a transcrição embaixo do áudio igual
 * no whatsapp". Nas três linhas desde a tarde de 29/09 (antes, só a Parceria).
 *
 * Quando: assim que o áudio entra (recebido, eco do celular ou mandado pelo
 * CRM), em segundo plano; e sob demanda para o áudio antigo, quando a
 * conversa abre. O texto fica em `metadata.transcricao`; `transcricao_status`
 * diz o que houve ('andando' | 'ok' | 'sem_audio' | 'falhou') e impede que o
 * mesmo áudio seja mandado duas vezes à OpenAI.
 *
 * O modelo é o mesmo que a Nay usa para ouvir o corretor (gpt-4o-transcribe,
 * ver Arquivos/nai/montar_transcricao.py), em português.
 */
import { and, eq, sql } from 'drizzle-orm'
import { db } from '@/lib/db'
import { integrations, leadActivities, leads } from '@/lib/schema'
import { lerMidia } from '@/lib/armazem'
import { channels, events, publishEvent } from '@/lib/realtime'

const MODELO = process.env.OPENAI_TRANSCRIBE_MODEL || 'gpt-4o-transcribe'
// as três linhas de WhatsApp (Pedro, 29/09: "quero a transcrição e o áudio
// para escutar"); até ali só a Parceria
const LINHAS_COM_TRANSCRICAO = ['whatsapp_zapi', 'whatsapp_zapi_captacao', 'whatsapp_cloud_official']

/*
 * FALHA DE PASSAGEM (29/09): a OpenAI sem crédito devolve 429 ("You have no
 * credits remaining") e o áudio ficava 'falhou' para sempre -- 103 áudios só
 * nesse dia. Falha assim (limite, crédito, 5xx, rede) é tentada de novo pela
 * rodada de minuto (`refazerTranscricoesQueFalharam`) e pelo botão da tela; a
 * de verdade (arquivo que a OpenAI recusa) fica como está.
 */
const ERRO_DE_PASSAGEM = '(OpenAI (429|5[0-9][0-9])|credit|rate limit|timeout|timed out|aborted|fetch failed|ECONN|ETIMEDOUT|socket)'
const DICA = 'Conversa de WhatsApp de uma imobiliária de Manaus com corretores e proprietários: '
  + 'imóveis, condomínios, bairros, visitas, aluguel, venda, código do imóvel.'

export function transcricaoLigada(): boolean {
  return !!process.env.OPENAI_API_KEY
}

export function linhaTemTranscricao(tipoDaIntegracao: string | null | undefined): boolean {
  return !!tipoDaIntegracao && LINHAS_COM_TRANSCRICAO.includes(tipoDaIntegracao)
}

const EXTENSAO: Record<string, string> = {
  'audio/ogg': 'ogg', 'audio/mpeg': 'mp3', 'audio/mp4': 'm4a', 'audio/x-m4a': 'm4a', 'audio/aac': 'm4a',
  'audio/wav': 'wav', 'audio/webm': 'webm', 'video/mp4': 'mp4', 'video/webm': 'webm',
}

/** Manda os bytes para a OpenAI e devolve o texto (vazio se não houver fala). */
export async function transcreverBytes(dados: Buffer, tipo: string): Promise<string> {
  const chave = process.env.OPENAI_API_KEY
  if (!chave) throw new Error('OPENAI_API_KEY ausente no CRM')
  const t = (tipo || 'audio/ogg').split(';')[0].trim().toLowerCase()
  const form = new FormData()
  form.append('file', new Blob([new Uint8Array(dados)], { type: t }), `audio.${EXTENSAO[t] || 'ogg'}`)
  form.append('model', MODELO)
  form.append('language', 'pt')
  form.append('prompt', DICA)
  form.append('response_format', 'json')
  const res = await fetch('https://api.openai.com/v1/audio/transcriptions', {
    method: 'POST',
    headers: { Authorization: `Bearer ${chave}` },
    body: form,
    signal: AbortSignal.timeout(120000),
  })
  const corpo = await res.json().catch(() => ({} as any))
  if (!res.ok) throw new Error(`OpenAI ${res.status}: ${corpo?.error?.message || 'erro'}`)
  return String(corpo?.text || '').trim()
}

/**
 * Transcreve um áudio do chat, se ainda não foi. Devolve o texto (ou null).
 * Pode ser chamada de novo à vontade: quem pega o áudio marca 'andando' num
 * UPDATE condicional, e só ele manda à OpenAI.
 */
export async function transcreverAtividade(atividadeId: string, opcoes: { refazer?: boolean } = {}): Promise<string | null> {
  const refazer = !!opcoes.refazer
  if (!transcricaoLigada()) return null
  const [a] = await db
    .select({ id: leadActivities.id, leadId: leadActivities.leadId, metadata: leadActivities.metadata,
              tipoLinha: integrations.type })
    .from(leadActivities)
    .innerJoin(leads, eq(leads.id, leadActivities.leadId))
    .leftJoin(integrations, eq(integrations.id, leads.integrationId))
    .where(eq(leadActivities.id, atividadeId))
    .limit(1)
  if (!a) return null
  const m = (a.metadata || {}) as Record<string, any>
  if (m.media_type !== 'audio' || !m.media_url) return null
  if (!linhaTemTranscricao(a.tipoLinha)) return null
  if (typeof m.transcricao === 'string') return m.transcricao

  // quem pegou primeiro transcreve; 'andando' de mais de 5 min é tentativa
  // morta; 'falhou' só volta quando pedem de novo e a falha foi de passagem
  const pegou = await db.execute(sql`
    UPDATE lead_activities
       SET metadata = metadata || jsonb_build_object('transcricao_status', 'andando', 'transcricao_desde', now()::text,
                                                     'transcricao_tentativas', coalesce((metadata->>'transcricao_tentativas')::int, 0) + 1)
     WHERE id = ${a.id}
       AND NOT (metadata ? 'transcricao')
       AND (metadata->>'transcricao_status' IS NULL
            OR (metadata->>'transcricao_status' = 'andando'
                AND (metadata->>'transcricao_desde')::timestamptz < now() - interval '5 minutes')
            OR (${refazer}::boolean AND metadata->>'transcricao_status' = 'falhou'
                AND coalesce(metadata->>'transcricao_erro', '') ~* ${ERRO_DE_PASSAGEM}))
    RETURNING id`)
  if (!(pegou as any).rows?.length) return null

  let texto: string | null = null
  let status = 'ok'
  let erro: string | null = null
  try {
    const midia = await lerMidia(String(m.media_url))
    if (!midia || !midia.dados.length) {
      status = 'sem_audio'   // o link temporário da Z-API venceu antes do armazém existir
    } else {
      texto = await transcreverBytes(midia.dados, midia.tipo || m.media_mimetype || 'audio/ogg')
    }
  } catch (e: any) {
    status = 'falhou'
    erro = String(e?.message || e).slice(0, 300)
    console.error('[transcricao]', a.id, erro)
  }

  await db.execute(sql`
    UPDATE lead_activities
       SET metadata = (metadata - 'transcricao_desde')
                      || jsonb_build_object('transcricao_status', ${status}::text, 'transcricao_em', now()::text)
                      || CASE WHEN ${texto}::text IS NOT NULL THEN jsonb_build_object('transcricao', ${texto}::text) ELSE '{}'::jsonb END
                      || CASE WHEN ${erro}::text IS NOT NULL THEN jsonb_build_object('transcricao_erro', ${erro}::text) ELSE '{}'::jsonb END,
           updated_at = now()
     WHERE id = ${a.id}`)
  await publishEvent(channels.leadActivities(a.leadId), events.ACTIVITY_UPDATED, { id: a.id })
  return texto
}

/** Dispara sem esperar -- quem grava a mensagem não pode ficar preso na OpenAI. */
export function transcreverEmSegundoPlano(atividadeId: string | null | undefined): void {
  if (!atividadeId || !transcricaoLigada()) return
  void transcreverAtividade(atividadeId).catch((e) => console.error('[transcricao]', atividadeId, e?.message || e))
}

/*
 * A RODADA QUE REFAZ (29/09), chamada pelo cron de minuto. Tenta UM áudio
 * primeiro: se ainda falha (a OpenAI continua sem crédito), para e só sonda de
 * novo em 5 min -- não martela a OpenAI com centenas de áudios. Se passou,
 * segue com o resto, do mais novo para o mais velho (7 dias).
 */
let proximaSondagem = 0

export async function refazerTranscricoesQueFalharam(limite = 12): Promise<{ tentadas: number; ok: number }> {
  const r = { tentadas: 0, ok: 0 }
  if (!transcricaoLigada() || Date.now() < proximaSondagem) return r
  const linhas = await db.execute(sql`
    SELECT a.id::text AS id
      FROM lead_activities a
      JOIN leads l ON l.id = a.lead_id
      JOIN integrations i ON i.id = l.integration_id
     WHERE i.type IN (SELECT jsonb_array_elements_text(${JSON.stringify(LINHAS_COM_TRANSCRICAO)}::jsonb))
       AND a.metadata->>'media_type' = 'audio'
       AND a.metadata->>'transcricao_status' = 'falhou'
       AND NOT (a.metadata ? 'transcricao')
       AND coalesce(a.metadata->>'transcricao_erro', '') ~* ${ERRO_DE_PASSAGEM}
       AND coalesce((a.metadata->>'transcricao_em')::timestamptz, a.created_at) < now() - interval '5 minutes'
       AND a.created_at > now() - interval '7 days'
     ORDER BY a.created_at DESC
     LIMIT ${limite}`)
  for (const { id } of linhas.rows as Array<{ id: string }>) {
    r.tentadas++
    await transcreverAtividade(id, { refazer: true }).catch(() => null)
    const depois = await db.execute(sql`SELECT metadata->>'transcricao_status' AS status FROM lead_activities WHERE id = ${id}`)
    const status = (depois.rows[0] as { status?: string } | undefined)?.status
    if (status === 'falhou') {
      // a OpenAI ainda não voltou: sonda de novo daqui a 5 min
      proximaSondagem = Date.now() + 5 * 60_000
      break
    }
    if (status === 'ok') r.ok++
  }
  return r
}

/** Os áudios de uma conversa que ainda não têm transcrição (para os antigos). */
export async function audiosSemTranscricao(leadId: string, limite = 20): Promise<string[]> {
  const linhas = await db
    .select({ id: leadActivities.id })
    .from(leadActivities)
    .where(and(
      eq(leadActivities.leadId, leadId),
      sql`${leadActivities.metadata}->>'media_type' = 'audio'`,
      sql`NOT (${leadActivities.metadata} ? 'transcricao')`,
      sql`coalesce(${leadActivities.metadata}->>'transcricao_status', '') NOT IN ('sem_audio', 'falhou', 'andando')`))
    .orderBy(sql`${leadActivities.createdAt} DESC`)
    .limit(limite)
  return linhas.map((l) => l.id)
}
