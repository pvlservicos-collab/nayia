/**
 * AS ABAS DE CADA NÚMERO SÃO ETIQUETAS (Tel, por Pedro, 20/10/2026: "troque as etapas que têm Todos, Visitas, pelas
 * tags que têm pessoas ... de forma editável, todas as etapas de todos os números editáveis").
 *
 *   GET ?linha=parceria|captacao|oficial -> { ids: string[] | null }   null = nunca editado (a tela usa as etiquetas
 *                                                                        que têm pessoas nesta linha)
 *   PUT { linha, ids: string[] }         -> { ok }                       a ordem é a das abas
 *
 * Guardado em integrations.config.abas_etiquetas da linha: só essa chave muda, o resto da configuração fica.
 */
import { NextRequest } from 'next/server'
import { sql } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const TIPO: Record<string, string> = { parceria: 'whatsapp_zapi', captacao: 'whatsapp_zapi_captacao', oficial: 'whatsapp_cloud_official' }

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const tipo = TIPO[req.nextUrl.searchParams.get('linha') || '']
    if (!tipo) return apiError(400, 'Linha inválida.')
    const r = await db.execute(sql`
      SELECT config->'abas_etiquetas' AS ids FROM integrations
       WHERE organization_id = ${auth.organizationId} AND type = ${tipo} AND deleted_at IS NULL
       ORDER BY created_at LIMIT 1`)
    const ids = (r.rows[0] as { ids: unknown } | undefined)?.ids
    return Response.json({ ids: Array.isArray(ids) ? ids.map(String) : null })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui ler as abas.')
  }
}

export async function PUT(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const corpo = await req.json().catch(() => ({}))
    const tipo = TIPO[String(corpo?.linha || '')]
    if (!tipo) return apiError(400, 'Linha inválida.')
    const ids = Array.isArray(corpo?.ids) ? [...new Set(corpo.ids.map(String).filter((x: string) => /^[0-9a-f-]{36}$/i.test(x)))].slice(0, 30) : null
    if (!ids) return apiError(400, 'Diga as etiquetas.')
    // só etiquetas desta organização
    const validas = ids.length
      ? (await db.execute(sql`SELECT id::text FROM tags WHERE organization_id = ${auth.organizationId}
                                AND id = ANY(${sql.raw(`ARRAY[${ids.map((i) => `'${i}'`).join(',')}]::uuid[]`)})`)).rows.map((x: any) => x.id)
      : []
    const ordem = ids.filter((i) => validas.includes(i))
    await db.execute(sql`
      UPDATE integrations SET config = coalesce(config, '{}'::jsonb) || jsonb_build_object('abas_etiquetas', ${JSON.stringify(ordem)}::jsonb),
             updated_at = now()
       WHERE organization_id = ${auth.organizationId} AND type = ${tipo} AND deleted_at IS NULL`)
    return Response.json({ ok: true, ids: ordem })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui salvar as abas.')
  }
}
