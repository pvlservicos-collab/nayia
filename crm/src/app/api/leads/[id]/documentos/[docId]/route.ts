/**
 * DELETE /api/leads/{id}/documentos/{docId} -- tira o documento da pasta do
 * corretor. Não apaga o arquivo nem a linha: marca apagado_em (documento de
 * gente não some por um clique errado).
 */
import { NextRequest } from 'next/server'
import { and, eq, isNull } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { corretorDocumentos } from '@/lib/schema'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string; docId: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    if (!auth.userId) return apiError(403, 'Só quem entra no CRM mexe na pasta.')
    const { id, docId } = await params
    const feito = await db.update(corretorDocumentos).set({ apagadoEm: new Date() })
      .where(and(
        eq(corretorDocumentos.id, docId),
        eq(corretorDocumentos.leadId, id),
        eq(corretorDocumentos.organizationId, auth.organizationId),
        isNull(corretorDocumentos.apagadoEm),
      ))
      .returning({ id: corretorDocumentos.id })
    if (!feito.length) return apiError(404, 'Documento não encontrado.')
    return Response.json({ ok: true })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui tirar o documento.')
  }
}
