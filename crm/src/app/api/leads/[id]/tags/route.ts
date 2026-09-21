import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { leadTags, tags } from '@/lib/schema'
import { eq, and } from 'drizzle-orm'

type Params = { params: Promise<{ id: string }> }

export async function GET(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const data = await db.select({ tagId: leadTags.tagId, tag: tags })
      .from(leadTags)
      .leftJoin(tags, eq(tags.id, leadTags.tagId))
      .where(and(eq(leadTags.leadId, id), eq(leadTags.organizationId, auth.organizationId)))
    return Response.json({ data: data.map(d => ({ tag_id: d.tagId, tag: d.tag })) })
  } catch (err: any) { return apiError(err.status || 500, err.message || 'Erro interno.') }
}

export async function POST(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const body = await req.json()
    if (!body.tag_id) return apiError(400, 'tag_id é obrigatório.')
    await db.insert(leadTags).values({
      leadId: id,
      tagId: body.tag_id,
      organizationId: auth.organizationId,
    }).onConflictDoNothing()
    return Response.json({ success: true }, { status: 201 })
  } catch (err: any) { return apiError(err.status || 500, err.message || 'Erro interno.') }
}

export async function DELETE(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const body = await req.json()
    if (!body.tag_id) return apiError(400, 'tag_id é obrigatório.')
    await db.delete(leadTags).where(
      and(eq(leadTags.leadId, id), eq(leadTags.tagId, body.tag_id), eq(leadTags.organizationId, auth.organizationId))
    )
    return Response.json({ success: true })
  } catch (err: any) { return apiError(err.status || 500, err.message || 'Erro interno.') }
}
