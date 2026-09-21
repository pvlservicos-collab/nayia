/**
 * POST /api/public/aplicacao — o formulário de aplicação do site manda aqui.
 *
 * É o ÚNICO endpoint do CRM que roda sem credencial, e por um motivo concreto:
 * quem envia é o navegador de quem está se inscrevendo, numa página do
 * WordPress. Qualquer token colocado ali estaria à vista de todo mundo no
 * código-fonte da página — e os tokens de API deste CRM dão acesso à
 * organização inteira.
 *
 * O que substitui o token:
 *   - só aceita requisição vinda do site (ou do próprio CRM, que serve a
 *     página de teste);
 *   - só escreve na fonte "site_evento", nunca em outra;
 *   - exige nome e um WhatsApp plausível;
 *   - campo-armadilha invisível (`website`): robô preenche, gente não;
 *   - limite por IP na mesma instância, pra travar envio em rajada.
 *
 * Daqui pra baixo é o mesmo caminho das fontes externas (handleIngest): mesma
 * normalização de telefone, mesmo dedupe, mesmo registro em
 * lead_source_submissions. O lead do popup (nome/e-mail/WhatsApp) e as
 * respostas desta etapa acabam na MESMA pessoa porque a fonte site_evento
 * identifica o lead pelo telefone.
 */
import { NextRequest } from 'next/server'
import { and, eq, isNull } from 'drizzle-orm'
import { db } from '@/lib/db'
import { leadSourceSubmissions, organizations } from '@/lib/schema'
import { handleIngest } from '@/lib/ingest'

/** De onde o formulário pode chamar, além do próprio CRM. */
const ORIGENS_PERMITIDAS = [
  'https://ascensaotita.com',
  'https://www.ascensaotita.com',
]

const FONTE = 'site_evento'

/** Uma inscrição a cada 20s por IP é folgado pra gente e apertado pra robô. */
const ESPERA_ENTRE_ENVIOS_MS = 20_000
const ultimoEnvioPorIp = new Map<string, number>()

/**
 * Origem autorizada?
 *
 * O site, e também o próprio CRM: a página de teste
 * (/formulario-aplicacao.html) é servida aqui, e sem isto ela levava 403 —
 * "não consegui enviar agora" ao testar, mesmo com tudo certo.
 */
function origemPermitida(origin: string | null, req: NextRequest): boolean {
  if (!origin) return true // curl, teste, requisição sem Origin
  if (ORIGENS_PERMITIDAS.includes(origin)) return true
  try {
    return new URL(origin).host === req.nextUrl.host
  } catch {
    return false
  }
}

function corsHeaders(origin: string | null, req: NextRequest): Record<string, string> {
  const permitida = origemPermitida(origin, req)
  return {
    'Access-Control-Allow-Origin': permitida && origin ? origin : ORIGENS_PERMITIDAS[0],
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Max-Age': '86400',
  }
}

export async function OPTIONS(req: NextRequest) {
  return new Response(null, { status: 204, headers: corsHeaders(req.headers.get('origin'), req) })
}

export async function POST(req: NextRequest) {
  const origin = req.headers.get('origin')
  const headers = corsHeaders(origin, req)

  try {
    if (!origemPermitida(origin, req)) {
      return Response.json({ error: 'Origem não autorizada.' }, { status: 403, headers })
    }

    const corpo = await req.json().catch(() => null)
    if (!corpo || typeof corpo !== 'object') {
      return Response.json({ error: 'Envie um JSON com as respostas.' }, { status: 400, headers })
    }

    // Armadilha: o campo existe no HTML, fica escondido e ninguém digita nele.
    // Responde 200 de propósito — robô que recebe erro tenta de novo.
    if (String((corpo as Record<string, unknown>).website ?? '').trim()) {
      return Response.json({ data: { ok: true } }, { status: 200, headers })
    }

    const nome = String((corpo as Record<string, unknown>).nome ?? '').trim()
    const whatsapp = String((corpo as Record<string, unknown>).whatsapp ?? '')
    // 10 = fixo com DDD, 11 = celular, 12/13 = com o 55 na frente.
    const digitos = whatsapp.replace(/\D/g, '')
    const temIdentidade = nome.length >= 2 && digitos.length >= 10 && digitos.length <= 15

    const ip = (req.headers.get('x-forwarded-for') || '').split(',')[0].trim() || 'sem-ip'
    const agora = Date.now()
    const ultimo = ultimoEnvioPorIp.get(ip)
    if (ultimo && agora - ultimo < ESPERA_ENTRE_ENVIOS_MS) {
      return Response.json({ error: 'Calma, sua inscrição já foi recebida.' }, { status: 429, headers })
    }
    ultimoEnvioPorIp.set(ip, agora)
    // A memória é por instância e some sozinha; limpa o que já não segura nada.
    if (ultimoEnvioPorIp.size > 500) {
      for (const [chave, quando] of ultimoEnvioPorIp) {
        if (agora - quando > ESPERA_ENTRE_ENVIOS_MS) ultimoEnvioPorIp.delete(chave)
      }
    }

    const [org] = await db
      .select({ id: organizations.id })
      .from(organizations)
      .where(process.env.ORG_FORMULARIO_PUBLICO
        ? and(eq(organizations.id, process.env.ORG_FORMULARIO_PUBLICO), isNull(organizations.deletedAt))
        : isNull(organizations.deletedAt))
      .limit(1)
    if (!org) return Response.json({ error: 'Organização não encontrada.' }, { status: 500, headers })

    // Refaz a requisição pro caminho comum: corpo limpo, fonte fixa. `website`
    // (a armadilha) fica de fora pra não virar campo do lead.
    const { website: _armadilha, ...limpo } = corpo as Record<string, unknown>

    /*
     * Sem nome e telefone não dá pra dizer DE QUEM são as respostas — acontece
     * quando o popup ainda não está passando os dados no redirecionamento.
     *
     * Mesmo assim o envio é aceito: quem está do outro lado respondeu tudo e não
     * pode ver um erro por causa de configuração nossa. As respostas ficam
     * guardadas como submissão sem dono (dá pra casar depois pelo horário), e
     * NÃO viram lead — lead sem telefone é lead que ninguém consegue atender.
     */
    if (!temIdentidade) {
      await db.insert(leadSourceSubmissions).values({
        organizationId: org.id,
        source: FONTE,
        externalId: null,
        name: nome || 'Sem identificação',
        email: String((corpo as Record<string, unknown>).email ?? '').trim() || null,
        phone: null,
        payload: limpo,
        receivedAt: new Date(),
        updatedAt: new Date(),
      })
      console.warn('[aplicacao] respostas recebidas sem identidade — popup não está passando nome/whatsapp na URL')
      return Response.json({ data: { ok: true, sem_identidade: true } }, { status: 200, headers })
    }

    const interna = new NextRequest(new URL('/api/ingest/leads/site_evento', req.url), {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(limpo),
    })

    const resposta = await handleIngest(interna, FONTE, { organizationId: org.id, memberId: null })
    const dados = await resposta.json().catch(() => ({}))
    return Response.json(dados, { status: resposta.status, headers })
  } catch (err: any) {
    console.error('[aplicacao] falhou:', err)
    return Response.json({ error: 'Não consegui registrar agora. Tente de novo.' }, { status: 500, headers })
  }
}
