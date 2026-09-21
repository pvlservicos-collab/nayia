/**
 * POST /api/ingest/leads/{source} — mesma entrada, com a fonte na URL.
 *
 * É esta que se cola no campo "Webhook URL" de um formulário do WordPress: o
 * plugin manda só os campos do formulário, sem conseguir acrescentar um
 * `source` fixo no corpo, então a fonte precisa estar no endereço.
 */
import { NextRequest } from 'next/server'
import { handleIngest, handleIngestPing } from '@/lib/ingest'

export async function POST(
  req: NextRequest,
  { params }: { params: Promise<{ source: string }> }
) {
  const { source } = await params
  return handleIngest(req, source)
}

export async function GET(
  req: NextRequest,
  { params }: { params: Promise<{ source: string }> }
) {
  const { source } = await params
  return handleIngestPing(req, source)
}
