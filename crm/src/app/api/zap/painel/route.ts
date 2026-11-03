/**
 * GET /api/zap/painel -- as abas Anúncios e Informações do Chat Zap (574).
 *
 * O banco (crm_zap_painel) dá os imóveis que o nosso cadastro manda ao feed, com os leads de cada um. Quem desses fica
 * FORA do XML do ZAP (sem CEP, menos de 5 fotos JPG, descrição curta) é regra do nay-site-api (zap_api._falta); aqui só
 * se junta o que ele responde em ?todos=1, para a regra continuar num lugar só. Se a API do site não responder, todos
 * aparecem como "no XML" e o aviso diz que a conferência não veio.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { naydb } from '@/lib/nayDisparo'
import type { AnuncioNoXml } from '@/lib/chavesNaMaoTipos'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const FEED = 'https://api.imobeasy.online/api/zap/imoveis.xml?todos=1'

export async function GET(req: NextRequest) {
  try {
    await authenticateRequest(req)
    const r = await naydb().query('SELECT crm_zap_painel() AS p')
    const p = r.rows[0]?.p ?? {}
    const anuncios: AnuncioNoXml[] = p.anuncios ?? []
    let fora: { codigo: number; falta: string[] }[] | null = null
    try {
      const f = await fetch(FEED, { cache: 'no-store', signal: AbortSignal.timeout(20000) })
      if (f.ok) fora = (await f.json())?.ficam ?? []
    } catch { /* fica null: a tela mostra todos no XML */ }
    const falta = new Map((fora ?? []).map((x) => [Number(x.codigo), x.falta]))
    for (const a of anuncios) {
      const f = falta.get(a.codigo)
      if (f) { a.ok = false; a.falta = f }
    }
    anuncios.sort((a, b) => Number(a.ok) - Number(b.ok))
    const vao = anuncios.filter((a) => a.ok).length
    return Response.json({ ...p, anuncios, vao, ficam: anuncios.length - vao, conferido: fora !== null })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui ler os anúncios do ZAP.')
  }
}
