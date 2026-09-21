/**
 * GET / PATCH /api/ai-settings — configuração da IA da organização.
 *
 * Guarda prompt, guardrails e modelo. **Nada no app consome isto ainda**: hoje
 * não existe nenhuma chamada a provedor de LLM no projeto (os botões de IA do
 * chat disparam webhook pra um sistema externo). A tela existe pra o prompt ser
 * escrito e revisado antes de a IA ser ligada.
 *
 * O GET devolve o padrão desligado quando ainda não há linha, em vez de 404 —
 * assim a tela abre igual na primeira vez e nas seguintes.
 */
import { NextRequest } from 'next/server'
import { eq } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { aiSettings } from '@/lib/schema'

/** Modelos oferecidos na tela, do mais capaz ao mais barato. */
const MODELOS_VALIDOS = ['claude-opus-5', 'claude-sonnet-5', 'claude-haiku-4-5']

const PADRAO = {
  enabled: false,
  model: 'claude-opus-5',
  systemPrompt: '',
  guardrails: '',
}

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const [linha] = await db
      .select()
      .from(aiSettings)
      .where(eq(aiSettings.organizationId, auth.organizationId))
      .limit(1)

    return Response.json({
      data: {
        enabled: linha?.enabled ?? PADRAO.enabled,
        model: linha?.model ?? PADRAO.model,
        system_prompt: linha?.systemPrompt ?? PADRAO.systemPrompt,
        guardrails: linha?.guardrails ?? PADRAO.guardrails,
        updated_at: linha?.updatedAt ?? null,
        // Deixa explícito pra tela: existe configuração, mas nada a executa.
        conectado: false,
        modelos: MODELOS_VALIDOS,
      },
    })
  } catch (err: any) {
    if (err?.status) return apiError(err.status, err.message)
    console.error('[ai-settings] GET falhou:', err)
    return apiError(500, 'Erro ao carregar a configuração da IA.')
  }
}

export async function PATCH(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const body = await req.json().catch(() => null)
    if (!body || typeof body !== 'object') return apiError(400, 'Corpo inválido.')

    if (body.model !== undefined && !MODELOS_VALIDOS.includes(body.model)) {
      return apiError(400, `Modelo inválido. Aceitos: ${MODELOS_VALIDOS.join(', ')}.`)
    }

    const valores = {
      organizationId: auth.organizationId,
      enabled: body.enabled === undefined ? PADRAO.enabled : !!body.enabled,
      model: body.model ?? PADRAO.model,
      systemPrompt: typeof body.system_prompt === 'string' ? body.system_prompt : PADRAO.systemPrompt,
      guardrails: typeof body.guardrails === 'string' ? body.guardrails : PADRAO.guardrails,
      updatedByMemberId: auth.memberId ?? null,
      updatedAt: new Date(),
    }

    const [salvo] = await db
      .insert(aiSettings)
      .values(valores)
      .onConflictDoUpdate({
        target: aiSettings.organizationId,
        set: {
          enabled: valores.enabled,
          model: valores.model,
          systemPrompt: valores.systemPrompt,
          guardrails: valores.guardrails,
          updatedByMemberId: valores.updatedByMemberId,
          updatedAt: valores.updatedAt,
        },
      })
      .returning()

    return Response.json({
      data: {
        enabled: salvo.enabled,
        model: salvo.model,
        system_prompt: salvo.systemPrompt,
        guardrails: salvo.guardrails,
        updated_at: salvo.updatedAt,
        conectado: false,
        modelos: MODELOS_VALIDOS,
      },
    })
  } catch (err: any) {
    if (err?.status) return apiError(err.status, err.message)
    console.error('[ai-settings] PATCH falhou:', err)
    return apiError(500, 'Erro ao salvar a configuração da IA.')
  }
}
