/**
 * GET/PUT /api/linhas/tipos-de-contato -- os TIPOS DE CONTATO personalizados (Pedro, 03/11/2026: "preciso que tenha tipos de
 * contato diferentes personalizados, tem contato de administração lá"). Ficam em integrations.config.tipos_de_contato da
 * linha Leads (valem para as três abas). Sem lista gravada, valem os padrões (src/lib/organizacaoDoLead.ts).
 */
import { NextRequest } from 'next/server'
import { sql } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { TIPOS_PADRAO, type TipoDeContato } from '@/lib/organizacaoDoLead'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const r = await db.execute(sql`
      SELECT config->'tipos_de_contato' AS tipos FROM integrations
       WHERE organization_id = ${auth.organizationId} AND type = 'whatsapp_zapi_captacao' AND deleted_at IS NULL
       ORDER BY created_at LIMIT 1`)
    const tipos = (r.rows[0] as { tipos: unknown } | undefined)?.tipos
    return Response.json({ tipos: Array.isArray(tipos) && tipos.length ? tipos : TIPOS_PADRAO })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui ler os tipos de contato.')
  }
}

export async function PUT(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const corpo = await req.json().catch(() => ({}))
    const lista: TipoDeContato[] = (Array.isArray(corpo?.tipos) ? corpo.tipos : [])
      .map((t: any) => ({
        chave: String(t?.chave || t?.nome || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '').slice(0, 40),
        nome: String(t?.nome || '').trim().slice(0, 40),
        cor: /^#[0-9a-f]{6}$/i.test(String(t?.cor || '')) ? String(t.cor) : '#64748b',
      }))
      .filter((t: TipoDeContato) => t.chave && t.nome)
      .slice(0, 30)
    if (!lista.length) return apiError(400, 'Diga ao menos um tipo.')
    const unicos = lista.filter((t, i) => lista.findIndex((x) => x.chave === t.chave) === i)
    await db.execute(sql`
      UPDATE integrations SET config = coalesce(config, '{}'::jsonb) || jsonb_build_object('tipos_de_contato', ${JSON.stringify(unicos)}::jsonb),
             updated_at = now()
       WHERE organization_id = ${auth.organizationId} AND type = 'whatsapp_zapi_captacao' AND deleted_at IS NULL`)
    return Response.json({ ok: true, tipos: unicos })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui salvar os tipos de contato.')
  }
}
