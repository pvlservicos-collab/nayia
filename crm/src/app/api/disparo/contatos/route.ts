/**
 * GET /api/disparo/contatos?q=... — acha o cliente pelo nome ou pelo número, e diz por QUAL número ele fala com a gente.
 *
 * Pedro, 17/10/2026: "lá onde põe o número ou pesquisa o nome do cliente, se a pessoa pesquisou um cliente que é de um
 * número e marcou para disparar do outro aparece um avisozinho". A tela "Enviar imóvel" (site e CRM) chama esta rota
 * enquanto se digita: o nome (2 letras ou mais) ou parte do número (4 dígitos ou mais). Um contato por telefone (os 8
 * últimos dígitos), com as linhas em que ele tem conversa: whatsapp_zapi (Parceria), whatsapp_zapi_captacao (Captação),
 * whatsapp_cloud_official (Oficial). Grupo e conversa apagada ficam de fora.
 */
import { NextRequest } from 'next/server'
import { sql } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const q = String(req.nextUrl.searchParams.get('q') || '').trim().slice(0, 60)
    const digitos = q.replace(/\D/g, '')
    const porNumero = digitos.length >= 4 && digitos.length >= q.replace(/[\s()+.-]/g, '').length
    if (!porNumero && q.length < 2) return Response.json({ contatos: [] })
    const filtro = porNumero
      ? sql`regexp_replace(coalesce(l.phone, ''), '\\D', '', 'g') LIKE ${'%' + digitos.slice(-11) + '%'}`
      : sql`lower(coalesce(l.title, '')) LIKE ${'%' + q.toLowerCase() + '%'}`
    const r = await db.execute(sql`
      SELECT right(regexp_replace(l.phone, '\\D', '', 'g'), 8) AS chave,
             (array_agg(l.title ORDER BY coalesce(l.last_activity_at, l.updated_at) DESC NULLS LAST))[1] AS nome,
             (array_agg(l.phone ORDER BY coalesce(l.last_activity_at, l.updated_at) DESC NULLS LAST))[1] AS telefone,
             array_agg(DISTINCT i.type) AS tipos,
             max(coalesce(l.last_activity_at, l.updated_at)) AS ultima
        FROM leads l
        JOIN integrations i ON i.id = l.integration_id
       WHERE l.organization_id = ${auth.organizationId} AND l.deleted_at IS NULL AND NOT coalesce(l.is_group, false)
         AND i.type IN ('whatsapp_zapi', 'whatsapp_zapi_captacao', 'whatsapp_cloud_official')
         AND regexp_replace(coalesce(l.phone, ''), '\\D', '', 'g') ~ '^[0-9]{10,13}$'
         AND ${filtro}
       GROUP BY 1
       ORDER BY max(coalesce(l.last_activity_at, l.updated_at)) DESC NULLS LAST
       LIMIT 8
    `)
    const linhas: any[] = (r as any).rows ?? (r as any)
    return Response.json({
      contatos: linhas.map((l) => ({
        nome: l.nome || null,
        telefone: String(l.telefone || '').replace(/\D/g, ''),
        tipos: (l.tipos || []) as string[],
        ultima: l.ultima,
      })),
    })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui procurar o contato.')
  }
}
