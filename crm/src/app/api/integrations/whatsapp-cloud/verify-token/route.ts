import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'

// GET /api/integrations/whatsapp-cloud/verify-token — devolve o Verify Token
// (mesmo valor pra todos os clientes) só pra quem já está logado. Não pode ir
// como NEXT_PUBLIC_ — isso colocaria o valor no bundle JS público, visível pra
// qualquer visitante sem sessão nenhuma.
export async function GET(req: NextRequest) {
  try {
    await authenticateRequest(req)
    return Response.json({ verify_token: process.env.FACEBOOK_WEBHOOK_VERIFY_TOKEN || '' })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
