import { NextRequest } from 'next/server'
import { apiError } from '@/lib/api-auth'

const STAGE_COLORS = [
  '#6366f1','#8b5cf6','#ec4899','#ef4444','#f97316',
  '#eab308','#22c55e','#14b8a6','#3b82f6','#64748b',
]

export async function GET() {
  return Response.json({ data: STAGE_COLORS })
}
