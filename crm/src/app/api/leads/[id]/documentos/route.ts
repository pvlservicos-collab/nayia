/**
 * A PASTA DO CORRETOR (Pedro, 29/09/2026): "uma pasta embaixo dos corretores
 * para anexar os documentos dela para quando for preciso ... fica no banco".
 *
 * GET  /api/leads/{id}/documentos           a lista
 * POST /api/leads/{id}/documentos (form)    `arquivo` -- até 25 MB, qualquer tipo
 *
 * O arquivo vai para documentos-corretores/<lead>/ no disco do CRM, servido só
 * com login (/api/midia). O registro fica em corretor_documentos (0128).
 */
import { NextRequest } from 'next/server'
import { randomUUID } from 'node:crypto'
import { and, desc, eq, isNull } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { corretorDocumentos, leads } from '@/lib/schema'
import { guardarMidia } from '@/lib/armazem'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const MAXIMO = 25 * 1024 * 1024

async function leadDaOrganizacao(id: string, org: string) {
  const [lead] = await db.select({ id: leads.id }).from(leads)
    .where(and(eq(leads.id, id), eq(leads.organizationId, org), isNull(leads.deletedAt))).limit(1)
  return lead
}

export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    if (!(await leadDaOrganizacao(id, auth.organizationId))) return apiError(404, 'Contato não encontrado.')
    const docs = await db.select().from(corretorDocumentos)
      .where(and(eq(corretorDocumentos.leadId, id), isNull(corretorDocumentos.apagadoEm)))
      .orderBy(desc(corretorDocumentos.criadoEm))
    return Response.json({ documentos: docs })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui ler os documentos.')
  }
}

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    if (!auth.userId) return apiError(403, 'Só quem entra no CRM guarda documento.')
    const { id } = await params
    if (!(await leadDaOrganizacao(id, auth.organizationId))) return apiError(404, 'Contato não encontrado.')

    const form = await req.formData()
    const arquivo = form.get('arquivo')
    if (!(arquivo instanceof File)) return apiError(400, 'Faltou o arquivo.')
    if (arquivo.size > MAXIMO) return apiError(413, 'Arquivo grande demais (máximo 25 MB).')
    const tipo = (arquivo.type || 'application/octet-stream').split(';')[0].trim().toLowerCase()
    const dados = Buffer.from(await arquivo.arrayBuffer())
    const url = await guardarMidia(`documentos-corretores/${id}`, `${Date.now()}_${randomUUID().slice(0, 8)}`, dados, tipo, arquivo.name)

    const [doc] = await db.insert(corretorDocumentos).values({
      organizationId: auth.organizationId,
      leadId: id,
      nome: (arquivo.name || 'documento').slice(0, 200),
      url,
      tipo,
      tamanho: arquivo.size,
      enviadoPor: auth.memberId || null,
    }).returning()
    return Response.json({ documento: doc }, { status: 201 })
  } catch (err: any) {
    console.error('[documentos do corretor]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui guardar o documento.')
  }
}
