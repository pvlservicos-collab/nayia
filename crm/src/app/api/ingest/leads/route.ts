/**
 * POST /api/ingest/leads — entrada de leads, com a fonte no corpo (`source`).
 *
 * Toda a lógica está em src/lib/ingest.ts, compartilhada com a variante
 * /api/ingest/leads/{source} (que é a usada pelo webhook do WordPress).
 * O GET no mesmo endereço serve pra testar a credencial.
 */
import { NextRequest } from 'next/server'
import { handleIngest, handleIngestPing } from '@/lib/ingest'

export async function POST(req: NextRequest) {
  return handleIngest(req)
}

export async function GET(req: NextRequest) {
  return handleIngestPing(req)
}
