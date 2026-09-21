import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { getWhatsAppCredentials } from '@/lib/whatsapp'

// GET /api/integrations/whatsapp-cloud/test — botão "Testar conexão agora" do onboarding.
// Só confirma que WABA ID/Phone Number ID/token batem com a Meta (sem mandar mensagem
// nenhuma) — chamada de leitura, sem efeito colateral.
export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const { apiVersion, phoneNumberId, token } = await getWhatsAppCredentials(auth.organizationId)

    const res = await fetch(
      `https://graph.facebook.com/${apiVersion}/${phoneNumberId}?fields=verified_name,display_phone_number`,
      { headers: { Authorization: `Bearer ${token}` } }
    )
    const data = await res.json().catch(() => ({}))

    if (!res.ok) {
      const errMsg = data?.error?.message || `A Meta recusou a conexão (HTTP ${res.status})`
      return Response.json({ ok: false, error: errMsg })
    }

    return Response.json({
      ok: true,
      verified_name: data.verified_name,
      display_phone_number: data.display_phone_number,
    })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
