import { NextRequest, NextResponse } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { leads, leadActivities } from '@/lib/schema'
import { eq, and, isNull, ilike, or, desc } from 'drizzle-orm'
import type { LeadWithOwner, SearchHit } from '@/lib/types'
import { mapLead } from '@/lib/mappers'

export const dynamic = 'force-dynamic'

export async function POST(req: NextRequest) {
  try {
    const body = await req.json().catch(() => ({} as any))
    const q = (body.q ?? '').trim()
    const limit = Math.min(Math.max(body.limit ?? 50, 1), 100)

    if (q.length < 2) {
      return NextResponse.json({ error: 'q must be at least 2 characters' }, { status: 400 })
    }

    const auth = await authenticateRequest(req)
    const searchTerm = `%${q}%`

    const leadResults = await db.select().from(leads)
      .where(and(
        eq(leads.organizationId, auth.organizationId),
        isNull(leads.deletedAt),
        or(ilike(leads.title, searchTerm), ilike(leads.phone, searchTerm), ilike(leads.email, searchTerm))
      ))
      .limit(limit)

    const activityResults = await db.select({ leadId: leadActivities.leadId, content: leadActivities.content, createdAt: leadActivities.createdAt })
      .from(leadActivities)
      .where(and(eq(leadActivities.organizationId, auth.organizationId), ilike(leadActivities.content, searchTerm)))
      .orderBy(desc(leadActivities.createdAt))
      .limit(limit)

    const leadMap = new Map(leadResults.map(l => [l.id, l]))

    const hits: SearchHit[] = [
      ...leadResults.map(lead => ({
        lead: mapLead(lead) as unknown as LeadWithOwner,
        matchType: 'title' as const,
        snippet: undefined,
        matchedAt: lead.lastActivityAt?.toString(),
      })),
    ]

    const seenLeadIds = new Set(leadResults.map(l => l.id))
    for (const act of activityResults) {
      if (!seenLeadIds.has(act.leadId)) {
        seenLeadIds.add(act.leadId)
        const lead = leadMap.get(act.leadId)
        if (lead) {
          hits.push({
            lead: mapLead(lead) as unknown as LeadWithOwner,
            matchType: 'message' as const,
            snippet: act.content?.slice(0, 120) || undefined,
            matchedAt: act.createdAt?.toString(),
          })
        }
      }
    }

    return NextResponse.json({ hits })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
