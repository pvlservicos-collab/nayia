import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { leadStageHistory } from '@/lib/schema'
import { eq, asc } from 'drizzle-orm'

type Params = { params: Promise<{ id: string }> }

export async function GET(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const data = await db.select().from(leadStageHistory)
      .where(eq(leadStageHistory.leadId, id))
      .orderBy(asc(leadStageHistory.movedAt))
    return Response.json({ data })
  } catch (err: any) { return apiError(err.status || 500, err.message || 'Erro interno.') }
}
