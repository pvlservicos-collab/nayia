/**
 * De qual imóvel fala a mensagem que o corretor MARCOU.
 *
 * Tel, 27/09/2026: "se alguem marcar uma mensagem de um imovel disparado no
 * grupo vai aparecer encima da mensagem um popup com o imovel".
 *
 * A Z-API só manda o id da mensagem marcada, sem o conteúdo. Quem sabe de qual
 * imóvel aquela mensagem era é a caixa de saída da Nay -- e é ela que a API do
 * site consulta. 404 aqui significa "não sei", e a tela então não mostra popup
 * nenhum, em vez de mostrar o imóvel errado.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { imovelDaMensagem } from '@/lib/imoveisNay'

export async function GET(req: NextRequest) {
  try {
    await authenticateRequest(req)
    const id = String(req.nextUrl.searchParams.get('id') || '').trim().slice(0, 80)
    if (!id) return apiError(400, 'Falta o id da mensagem.')
    return Response.json(await imovelDaMensagem(id))
  } catch (err: any) {
    return apiError(err.status || 404, err.message || 'Não sei de qual imóvel essa mensagem fala.')
  }
}
