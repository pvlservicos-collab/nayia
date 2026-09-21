/**
 * Recebimento de leads das fontes externas — lógica compartilhada pelas duas
 * rotas de entrada:
 *
 *   POST /api/ingest/leads            → `source` vem no corpo
 *   POST /api/ingest/leads/{source}   → `source` vem na URL
 *
 * A segunda existe por causa do WordPress: a maioria dos plugins de formulário
 * (WPForms, Elementor, Fluent Forms, CF7 + addon) manda os campos do formulário
 * e nada mais — não dá pra acrescentar um `source` fixo no corpo. Com o source
 * na URL, o plugin só precisa saber colar um endereço.
 *
 * Pelo mesmo motivo esta camada é tolerante em três pontos onde a API "pura"
 * seria estrita. Nenhum deles é frouxidão: são limitações reais dos plugins.
 *
 *   1. Autenticação também por `?key=atl_...` na URL. Vários plugins não têm
 *      campo pra cabeçalho HTTP customizado, então exigir `Authorization` os
 *      deixaria de fora. O cabeçalho continua sendo o caminho preferido —
 *      chave em query string aparece em log de servidor e no histórico do
 *      navegador, então quem PODE mandar cabeçalho deve mandar.
 *   2. Corpo em `application/x-www-form-urlencoded` / `multipart/form-data`
 *      além de JSON. Boa parte dos plugins posta o formulário cru.
 *   3. Apelidos de campo: o nome do campo no WordPress é o que o autor do
 *      formulário escolheu ("your-name", "telefone", "field_3"), não o nosso.
 */
import { NextRequest } from 'next/server'
import { and, asc, eq, inArray, isNull, sql } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { getOrgRole } from '@/lib/admin-auth'
import { db } from '@/lib/db'
import { leadSourceSubmissions, leads, pipelineStages, webhookLogs } from '@/lib/schema'
import { isUniqueViolation } from '@/lib/db-helpers'
import {
  LEAD_SOURCE_ORDER,
  dedupeKeyFor,
  getLeadSource,
  telefoneVariantes,
  type LeadSourceKey,
  type NormalizedLead,
} from '@/lib/leadSources'
import { startFunnelForSource } from '@/lib/funnel-triggers'
import { publishEvent, channels, events } from '@/lib/realtime'

/**
 * Apelidos aceitos para os campos de contato, na ordem de preferência.
 *
 * Só vale para os campos que TODO formulário tem (nome, e-mail, telefone) — os
 * campos estruturados da Agenda (`agenda.a1`, `agenda.real`) vêm de um sistema
 * nosso, que manda os nomes certos, e não entram aqui.
 */
const FIELD_ALIASES: Record<string, string[]> = {
  nome: ['nome', 'name', 'nome_completo', 'nomecompleto', 'full_name', 'fullname', 'your-name', 'seu-nome', 'first_name'],
  email: ['email', 'e-mail', 'e_mail', 'mail', 'your-email', 'seu-email'],
  whatsapp: ['whatsapp', 'whats', 'telefone', 'phone', 'celular', 'tel', 'fone', 'numero', 'número', 'your-phone', 'seu-telefone'],
  instagram: ['instagram', 'insta', 'ig', '@instagram'],
  id: ['id', 'lead_id', 'external_id'],
}

/** "Seu Nome" / "seu_nome" / "seu-nome" / "SEU NOME" viram todos "seunome". */
function fieldKey(value: string): string {
  return value
    .toLowerCase()
    .normalize('NFD')
    .replace(/\p{M}/gu, '') // marcas de acento que o NFD acabou de separar
    .replace(/[\s_-]/g, '')
}

/**
 * Achata nomes de campo em notação de colchete.
 *
 * O Elementor Pro manda todo campo do formulário como `form_fields[nome]`,
 * `form_fields[email]` — nunca `nome` direto. Sem achatar, nenhum apelido casa
 * e a requisição morre em "campos obrigatórios ausentes". Outros plugins fazem
 * o mesmo com prefixos diferentes, então a regra é geral: qualquer
 * `wrapper[chave]` também passa a valer como `chave`.
 *
 * Só preenche o que ainda não existe no topo — se o corpo já trouxe `nome`
 * solto, ele ganha do `form_fields[nome]`.
 */
/**
 * Desempacota o formato CRU do Elementor Pro.
 *
 * O webhook do Elementor tem dois formatos, e um formulário novo costuma vir no
 * segundo sem ninguém avisar:
 *
 *   1. achatado — "No Label name", "No Label tel" (era o do popup antigo);
 *   2. cru — `fields[name][value]`, `fields[tel][value]`, `meta[date][value]`,
 *      mais `fields[name][id]`, `[type]`, `[title]`, `[required]`…
 *
 * O leitor genérico de colchetes só entende UM nível, e no formato cru ele
 * produzia lixo: `fields[name][value]` virava a chave `name][value`, e
 * `form[name]` — que é o nome do FORMULÁRIO — virava `name` e acabava como
 * nome do lead. Foi assim que um lead entrou chamado "New Form".
 *
 * Aqui cada `fields[x][value]` vira `x`, cada `meta[x][value]` vira `x`, e o
 * resto (`id`, `type`, `title`, `required`, `form[...]`) é descartado: é
 * descrição do formulário, não resposta de ninguém.
 */
export function desempacotarElementor(body: Record<string, any>): Record<string, any> {
  const ehFormatoCru = Object.keys(body).some((k) => /^fields\[[^\]]+\]\[value\]$/.test(k))
  if (!ehFormatoCru) return body

  const out: Record<string, any> = {}
  for (const [key, value] of Object.entries(body)) {
    const campo = key.match(/^fields\[([^\]]+)\]\[(value|raw_value)\]$/)
    if (campo) {
      // `value` manda; `raw_value` só preenche o que ficou vazio (é o mesmo dado
      // sem formatação, e alguns campos só trazem um dos dois).
      const [, nome, tipo] = campo
      const atual = out[nome]
      if (tipo === 'value' || atual === undefined || String(atual).trim() === '') {
        if (value !== undefined && value !== null && String(value).trim() !== '') out[nome] = value
      }
      continue
    }
    const meta = key.match(/^meta\[([^\]]+)\]\[value\]$/)
    if (meta) {
      out[meta[1]] = value
      continue
    }
    // Estrutura do formulário (fields[x][id|type|title|required], form[id],
    // form[name]) não é dado de lead: fica de fora.
    if (/^(fields|meta|form)\[/.test(key)) continue
    out[key] = value
  }
  return out
}

export function flattenBracketKeys(body: Record<string, any>): Record<string, any> {
  const out: Record<string, any> = { ...body }
  for (const [key, value] of Object.entries(body)) {
    const match = key.match(/^[A-Za-z_][\w.-]*\[(.+)\]$/)
    if (!match) continue
    const inner = match[1].trim()
    if (!inner) continue
    const atual = out[inner]
    if (atual !== undefined && atual !== null && String(atual).trim() !== '') continue
    out[inner] = value
  }
  return out
}

/**
 * Preenche os nomes canônicos a partir dos apelidos, sem sobrescrever o que já
 * veio com o nome certo.
 *
 * Exportada (junto com parseBody) porque é aqui que mora a compatibilidade com
 * os formulários do WordPress — a parte mais fácil de quebrar sem perceber, e a
 * única que dá pra testar sem banco.
 */
export function applyAliases(body: Record<string, any>): Record<string, any> {
  const normalizedKeys = new Map<string, string>()
  for (const key of Object.keys(body)) {
    normalizedKeys.set(fieldKey(key), key)
  }

  const result = { ...body }
  for (const [canonical, aliases] of Object.entries(FIELD_ALIASES)) {
    const current = result[canonical]
    if (current !== undefined && current !== null && String(current).trim() !== '') continue

    for (const alias of aliases) {
      const actualKey = normalizedKeys.get(fieldKey(alias))
      if (actualKey === undefined) continue
      const value = body[actualKey]
      if (value === undefined || value === null || String(value).trim() === '') continue
      result[canonical] = value
      break
    }
  }
  return result
}

/**
 * Descobre nome / e-mail / telefone pelo CONTEÚDO, quando o nome do campo não
 * ajudou.
 *
 * Um formulário de WordPress pode chegar com os campos batizados de qualquer
 * coisa — `field_1`, `campo-2`, `Qual seu contato?`. Nenhuma lista de apelidos
 * cobre isso. Então, no que sobrou sem identificação, a gente olha o valor:
 * e-mail tem @ e ponto, telefone é um punhado de dígitos, nome é o texto que
 * não é nenhum dos dois.
 *
 * É deliberadamente conservador: só preenche o que ainda está vazio, nunca
 * sobrescreve um campo que veio nomeado direito, e ignora valores que são
 * claramente metadados do plugin (id de formulário, url da página).
 */

/** Campos que os plugins mandam junto e que não são resposta do usuário. */
const META_KEYS = new Set([
  'formid', 'formname', 'form', 'pageurl', 'pagetitle', 'pageid', 'referrer',
  'remoteip', 'userAgent', 'useragent', 'queriedid', 'source', 'key', 'token',
  'submittedat', 'date', 'time', 'id',
])

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/

function pareceTelefone(valor: string): boolean {
  const digitos = valor.replace(/\D/g, '')
  // 8 a 15 dígitos cobre fixo local até DDI+DDD+9 dígitos (padrão E.164).
  if (digitos.length < 8 || digitos.length > 15) return false
  // Precisa ser majoritariamente dígito — evita confundir com um endereço
  // ("Rua 7 de Setembro, 1500") ou com uma data.
  const naoDigitos = valor.replace(/[\d\s()+.\-]/g, '').length
  return naoDigitos === 0
}

function pareceNome(valor: string): boolean {
  if (EMAIL_RE.test(valor)) return false
  if (pareceTelefone(valor)) return false
  if (/^https?:\/\//i.test(valor)) return false
  // Pelo menos duas letras seguidas: descarta "12345", "---", "R$ 10".
  return /\p{L}{2,}/u.test(valor)
}

export function inferContactFields(body: Record<string, any>): Record<string, any> {
  const out = { ...body }
  const vazio = (k: string) => {
    const v = out[k]
    return v === undefined || v === null || String(v).trim() === ''
  }

  const candidatos: string[] = []
  for (const [chave, valor] of Object.entries(body)) {
    if (typeof valor !== 'string') continue
    const texto = valor.trim()
    if (!texto) continue
    if (META_KEYS.has(fieldKey(chave))) continue
    candidatos.push(texto)
  }

  if (vazio('email')) {
    const achado = candidatos.find((v) => EMAIL_RE.test(v))
    if (achado) out.email = achado
  }
  if (vazio('whatsapp')) {
    const achado = candidatos.find((v) => pareceTelefone(v))
    if (achado) out.whatsapp = achado
  }
  if (vazio('nome')) {
    const achado = candidatos.find((v) => pareceNome(v))
    if (achado) out.nome = achado
  }

  return out
}

/**
 * Lê o corpo em qualquer um dos formatos que os plugins mandam.
 *
 * Em formulário urlencoded tudo chega string, inclusive o que deveria ser
 * objeto. Se o valor parecer JSON (`{...}` / `[...]`) a gente tenta desserializar
 * — é assim que um formulário consegue mandar o `agenda` inteiro num campo só.
 */
export async function parseBody(req: NextRequest): Promise<Record<string, any> | null> {
  const contentType = req.headers.get('content-type') || ''

  if (contentType.includes('application/json')) {
    try {
      const parsed = await req.json()
      return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : null
    } catch {
      return null
    }
  }

  if (
    contentType.includes('application/x-www-form-urlencoded') ||
    contentType.includes('multipart/form-data')
  ) {
    try {
      const form = await req.formData()
      const out: Record<string, any> = {}
      for (const [key, value] of form.entries()) {
        const raw = typeof value === 'string' ? value : null
        if (raw === null) continue
        const trimmedValue = raw.trim()
        if (
          (trimmedValue.startsWith('{') && trimmedValue.endsWith('}')) ||
          (trimmedValue.startsWith('[') && trimmedValue.endsWith(']'))
        ) {
          try {
            out[key] = JSON.parse(trimmedValue)
            continue
          } catch {
            /* não era JSON — segue como texto */
          }
        }
        out[key] = raw
      }
      return out
    } catch {
      return null
    }
  }

  // Sem Content-Type reconhecível (alguns plugins não mandam nenhum): última
  // tentativa lendo como texto e adivinhando entre JSON e querystring.
  try {
    const text = (await req.text()).trim()
    if (!text) return {}
    if (text.startsWith('{')) return JSON.parse(text)
    const params = new URLSearchParams(text)
    const out: Record<string, any> = {}
    for (const [key, value] of params.entries()) out[key] = value
    return Object.keys(out).length > 0 ? out : null
  } catch {
    return null
  }
}

/**
 * Autentica pelo cabeçalho e, se não houver, por `?key=`.
 *
 * O fallback monta uma requisição com o cabeçalho preenchido em vez de
 * reimplementar a checagem do token — assim continua existindo um único lugar
 * que sabe validar credencial (authenticateRequest).
 */
async function authenticate(req: NextRequest) {
  if (req.headers.get('authorization')) return authenticateRequest(req)

  const key = req.nextUrl.searchParams.get('key') || req.nextUrl.searchParams.get('token')
  if (!key) return authenticateRequest(req)

  const headers = new Headers(req.headers)
  headers.set('authorization', `Bearer ${key}`)
  return authenticateRequest(new NextRequest(req.nextUrl, { headers }) as NextRequest)
}

/**
 * Quem está do outro lado pode cadastrar lead?
 *
 * Sistema externo (token de API) sempre pode — é para isso que a chave existe, e
 * ela não tem papel nem permissão. A pergunta só faz sentido para PESSOA logada,
 * que é o caso do formulário de indicação no Pipeline: ali existe um papel, e a
 * tela de permissões promete um botão "Criar e editar leads". Sem esta checagem
 * a promessa seria falsa — bastaria abrir o formulário para furar a regra.
 */
async function podeCadastrarLead(auth: {
  memberId: string | null
  roleId: string | null
  isSuperAdmin?: boolean
}): Promise<boolean> {
  if (!auth.memberId) return true
  if (auth.isSuperAdmin) return true
  const role = await getOrgRole(auth.roleId)
  const permissoes = (role?.permissions ?? {}) as Record<string, any>
  // `{'*': true}` é como o papel de administrador guarda "pode tudo".
  if (permissoes['*'] === true) return true
  return permissoes?.leads?.create_edit === true
}

/** Cria o lead no CRM ou devolve o que já existe pro mesmo telefone. */
async function upsertCrmLead(
  organizationId: string,
  source: LeadSourceKey,
  normalized: NormalizedLead,
  /**
   * Membro que fica como dono do lead novo.
   *
   * Preenchido só quando quem chamou é uma PESSOA logada (o formulário de
   * indicação no Pipeline) — sistema externo entra por token de API e não tem
   * membro. Importa porque um papel pode estar com "ver apenas seus próprios
   * leads": sem dono, o agente cadastraria a indicação e ela sumiria da tela
   * dele no mesmo instante.
   */
  ownerMemberId?: string | null,
  /** Ressincronização em massa da Agenda — ver o uso mais abaixo. */
  ehResync = false
): Promise<{ id: string; created: boolean; promovido: boolean } | null> {
  if (normalized.phone) {
    // Pelas DUAS formas do celular (com e sem o nono dígito). Uma conversa
    // importada do WhatsApp pode estar gravada na forma antiga, e comparar só a
    // forma exata criaria um lead novo pra quem já tem conversa aberta aqui —
    // o atendimento acabaria falando com a pessoa em dois lugares.
    const [existing] = await db
      .select({
        id: leads.id,
        title: leads.title,
        stageId: leads.stageId,
        customAttributes: leads.customAttributes,
      })
      .from(leads)
      .where(and(
        eq(leads.organizationId, organizationId),
        inArray(leads.phone, telefoneVariantes(normalized.phone)),
        isNull(leads.deletedAt)
      ))
      .limit(1)

    if (existing) {
      /*
       * O telefone já estava aqui, mas só como CONVERSA (importada do WhatsApp,
       * ou uma planilha antiga) — nunca como lead de aquisição. Agora ele
       * preencheu o formulário: é lead novo pra todos os efeitos, e precisa
       * entrar no funil.
       *
       * Sem isto o "já existe" mandava parar por aqui: o Arthur preencheu a
       * Agenda, o CRM reconheceu o número de uma conversa importada e ele ficou
       * sem fonte, sem card no Pipeline, sem mensagem automática e ainda com o
       * nome antigo (que era o próprio número).
       *
       * `lead_source` é o que separa os dois mundos: quem já tem fonte é lead de
       * aquisição de verdade, e aí o reenvio do mesmo formulário continua não
       * disparando mensagem nenhuma.
       */
      const atributos = (existing.customAttributes ?? {}) as Record<string, unknown>
      const ehSoConversa = !atributos.lead_source

      /*
       * Lead que JÁ é de aquisição e voltou (o quiz da Agenda que avançou, a
       * segunda etapa do formulário do site): atualiza o que veio de novo e
       * mantém o resto. Antes parava aqui sem gravar nada, e as respostas da
       * segunda etapa só existiam na tabela de submissões — o card do lead
       * ficava sem elas.
       *
       * Só isso: nada de mudar etapa nem de disparar funil, que é o que
       * diferencia "atualizar cadastro" de "lead novo".
       */
      // Nome: o da conversa importada costuma ser o próprio número. Só troca
      // quando o que está lá não tem letra nenhuma — assim não se perde um nome
      // bom ("Eduardo de Andrade Ref Patriota") por um apelido curto do formulário.
      const tituloTemLetra = /\p{L}/u.test(existing.title || '')
      // Campo vazio da fonte vem como null (a Agenda manda `aumento: null` quando
      // a pessoa não respondeu). Se entrasse no merge, apagaria o que já estava
      // gravado — atualizar um cadastro nunca pode subtrair.
      const camposPreenchidos = Object.fromEntries(
        Object.entries(normalized.fields).filter(([, valor]) => valor !== null && valor !== undefined && valor !== '')
      )
      const mudancas: Record<string, unknown> = {
        customAttributes: {
          ...atributos,
          // A fonte é por onde a pessoa ENTROU, e isso não muda: quem veio da
          // Agenda e depois preenche o formulário do site continua da Agenda,
          // senão o card mudaria de coluna na "Fonte:" do Pipeline.
          lead_source: ehSoConversa ? source : atributos.lead_source,
          ...camposPreenchidos,
        },
        lastActivityAt: new Date(),
      }
      if (!tituloTemLetra && normalized.name) mudancas.title = normalized.name
      if (normalized.email) mudancas.email = normalized.email

      // Entra no Kanban na primeira etapa só quem está VIRANDO lead agora. Quem
      // já era lead de aquisição e voltou fica onde está — reenviar formulário
      // não pode puxar de volta pra primeira coluna quem já avançou.
      if (ehSoConversa && !existing.stageId && !ehResync) {
        const [primeiraEtapa] = await db
          .select({ id: pipelineStages.id })
          .from(pipelineStages)
          .where(and(eq(pipelineStages.organizationId, organizationId), isNull(pipelineStages.deletedAt)))
          .orderBy(asc(pipelineStages.rank))
          .limit(1)
        if (primeiraEtapa) mudancas.stageId = primeiraEtapa.id
      }

      await db.update(leads).set(mudancas).where(eq(leads.id, existing.id))
      // Promovido (e portanto "novo" pro funil e pro plin) só quem era apenas
      // conversa. Reenvio de lead que já era de aquisição é atualização e nada mais.
      return { id: existing.id, created: false, promovido: ehSoConversa && !ehResync }
    }
  }

  const [firstStage] = await db
    .select({ id: pipelineStages.id })
    .from(pipelineStages)
    .where(and(
      eq(pipelineStages.organizationId, organizationId),
      isNull(pipelineStages.deletedAt)
    ))
    .orderBy(asc(pipelineStages.rank))
    .limit(1)

  try {
    const [lead] = await db
      .insert(leads)
      .values({
        organizationId,
        title: normalized.name,
        phone: normalized.phone,
        email: normalized.email,
        stageId: firstStage?.id ?? null,
        ownerMemberId: ownerMemberId ?? null,
        customAttributes: { lead_source: source, ...normalized.fields },
        lastActivityAt: new Date(),
      })
      .returning({ id: leads.id })
    return lead ? { id: lead.id, created: true, promovido: false } : null
  } catch (err) {
    // leads_org_phone_unique: outra requisição criou o mesmo telefone entre o
    // SELECT acima e este INSERT. Busca de novo em vez de estourar.
    if (!isUniqueViolation(err) || !normalized.phone) throw err
    const [raceLead] = await db
      .select({ id: leads.id })
      .from(leads)
      .where(and(
        eq(leads.organizationId, organizationId),
        inArray(leads.phone, telefoneVariantes(normalized.phone)),
        isNull(leads.deletedAt)
      ))
      .limit(1)
    return raceLead ? { id: raceLead.id, created: false, promovido: false } : null
  }
}

/**
 * Registra toda tentativa de ingestão em `webhook_logs`, inclusive as que
 * falham.
 *
 * Existe porque uma requisição recusada (401 por chave errada, 400 por campo
 * faltando) não cria linha em lead_source_submissions — então, quando alguém do
 * outro lado diz "não está entrando", não havia como distinguir "a requisição
 * nem chegou" de "chegou e foi recusada". Sem isso a investigação vira adivinha.
 *
 * A chave NUNCA é gravada: a URL vai com o `key`/`token` mascarado, e o
 * cabeçalho Authorization não é registrado.
 *
 * Nunca lança: log é diagnóstico, não pode derrubar a entrada de um lead.
 */
async function logAttempt(
  req: NextRequest,
  dados: {
    resultado: string
    source?: string | null
    detalhe?: string | null
    camposRecebidos?: string[]
    organizationId?: string | null
    submissionId?: string | null
    leadId?: string | null
  }
) {
  try {
    const url = new URL(req.nextUrl.toString())
    for (const p of ['key', 'token']) {
      if (url.searchParams.has(p)) url.searchParams.set(p, '***')
    }

    await db.insert(webhookLogs).values({
      payload: {
        origem: 'ingest',
        resultado: dados.resultado,
        source: dados.source ?? null,
        detalhe: dados.detalhe ?? null,
        campos_recebidos: dados.camposRecebidos ?? null,
        url: url.pathname + url.search,
        metodo: req.method,
        content_type: req.headers.get('content-type') || null,
        user_agent: req.headers.get('user-agent') || null,
        tem_cabecalho_auth: !!req.headers.get('authorization'),
        tem_key_na_url: !!(req.nextUrl.searchParams.get('key') || req.nextUrl.searchParams.get('token')),
        organization_id: dados.organizationId ?? null,
        submission_id: dados.submissionId ?? null,
        lead_id: dados.leadId ?? null,
        em: new Date().toISOString(),
      },
    })
  } catch (err) {
    console.error('[ingest] falhou ao gravar o log da tentativa:', err)
  }
}

/**
 * Trata uma requisição de entrada de lead.
 *
 * `sourceFromPath` vem preenchido quando a rota é /api/ingest/leads/{source};
 * nesse caso a URL manda e o corpo nem precisa trazer `source`.
 *
 * `autenticacaoInterna` é pra quem já sabe de qual organização é o lead e não
 * tem credencial pra apresentar — hoje só o formulário público do site
 * (/api/public/aplicacao), que roda no navegador de quem se inscreve e por isso
 * NÃO pode carregar token de API nenhum. Quem chama assim já validou a origem;
 * daqui pra baixo o caminho é exatamente o mesmo das fontes externas.
 */
export async function handleIngest(
  req: NextRequest,
  sourceFromPath?: string,
  autenticacaoInterna?: { organizationId: string; memberId: string | null }
) {
  try {
    let auth
    try {
      auth = autenticacaoInterna
        ? { ...autenticacaoInterna, userId: null, roleId: null }
        : await authenticate(req)
    } catch (err: any) {
      // Registra a recusa por credencial ANTES de propagar — e o caso mais
      // comum de "o webhook nao entra" e o mais invisivel sem isto.
      await logAttempt(req, { resultado: 'credencial_recusada', detalhe: err?.message ?? null })
      throw err
    }

    const rawBody = await parseBody(req)
    if (rawBody === null) {
      await logAttempt(req, { resultado: 'corpo_ilegivel', organizationId: auth.organizationId })
      return apiError(400, 'Corpo inválido: envie JSON ou os campos do formulário (urlencoded / multipart).')
    }
    const body = inferContactFields(applyAliases(flattenBracketKeys(desempacotarElementor(rawBody))))

    const sourceDef = getLeadSource(sourceFromPath ?? body.source)
    if (!sourceDef) {
      await logAttempt(req, {
        resultado: 'fonte_desconhecida',
        source: String(sourceFromPath ?? body.source ?? ''),
        camposRecebidos: Object.keys(rawBody),
        organizationId: auth.organizationId,
      })
      return apiError(
        400,
        `Fonte desconhecida: ${JSON.stringify(sourceFromPath ?? body.source ?? null)}. ` +
        `Valores aceitos: ${LEAD_SOURCE_ORDER.join(', ')}.`
      )
    }

    // Fonte sem `required` (o formulário do site) nunca recusa: registra o que
    // chegou e segue. Recusar dá "Webhook error." na cara de quem preencheu o
    // formulário e o dado se perde — pior que guardar um lead incompleto, que
    // pelo menos dá pra completar depois.
    const faltando = sourceDef.required.filter((field) => {
      const value = body[field]
      return value === undefined || value === null || String(value).trim() === ''
    })
    if (faltando.length > 0) {
      await logAttempt(req, {
        resultado: 'campos_faltando',
        source: sourceDef.key,
        detalhe: faltando.join(', '),
        camposRecebidos: Object.keys(rawBody),
        organizationId: auth.organizationId,
      })
      return apiError(
        400,
        `Campos obrigatórios ausentes para a fonte "${sourceDef.key}": ${faltando.join(', ')}. ` +
        `Campos recebidos: ${Object.keys(rawBody).join(', ') || '(nenhum)'}.`
      )
    }

    if (!(await podeCadastrarLead(auth))) {
      await logAttempt(req, {
        resultado: 'sem_permissao',
        source: sourceDef.key,
        organizationId: auth.organizationId,
      })
      return apiError(403, 'Seu perfil não tem permissão para cadastrar leads.')
    }

    // Reenvio de base existente (ver o uso mais abaixo). Aceita tanto no corpo
    // quanto na URL porque quem dispara é um script — e script erra menos
    // quando os dois jeitos funcionam.
    const ehResync =
      body.resync === true ||
      String(body.resync ?? '').toLowerCase() === 'true' ||
      req.nextUrl.searchParams.get('resync') === '1'

    /*
     * "Cadastre, mas não mande mensagem nenhuma."
     *
     * Quem pede é o cadastro manual do Pipeline: registrar na Agenda ou no site
     * um lead que já foi atendido, ou arrumar um cadastro antigo, não pode
     * disparar a mensagem de boas-vindas no WhatsApp da pessoa. É decisão de
     * quem cadastra, no interruptor do formulário — por isso vem na requisição
     * e não numa configuração fixa.
     */
    const semAutomacao =
      body.sem_automacao === true ||
      String(body.sem_automacao ?? '').toLowerCase() === 'true' ||
      req.nextUrl.searchParams.get('automacao') === '0'

    const normalized = sourceDef.normalize(body)
    const dedupeKey = dedupeKeyFor(sourceDef.key, normalized)

    const values = {
      organizationId: auth.organizationId,
      source: sourceDef.key,
      externalId: dedupeKey,
      name: normalized.name,
      email: normalized.email,
      phone: normalized.phone,
      instagram: normalized.instagram,
      payload: normalized.fields,
      receivedAt: new Date(),
      updatedAt: new Date(),
    }

    // Com chave de dedupe, reenviar o mesmo lead atualiza a linha (o caso real:
    // o quiz da Agenda sai de "w1" pra "done" e é mandado de novo). Sem chave,
    // cada requisição vira uma linha nova. `received_at` não entra no UPDATE de
    // propósito: a coluna registra quando aquele lead apareceu pela primeira
    // vez; quando ele mudou é `updated_at`.
    const [submission] = dedupeKey
      ? await db.insert(leadSourceSubmissions).values(values)
          .onConflictDoUpdate({
            target: [
              leadSourceSubmissions.organizationId,
              leadSourceSubmissions.source,
              leadSourceSubmissions.externalId,
            ],
            set: {
              name: values.name,
              email: values.email,
              phone: values.phone,
              instagram: values.instagram,
              /*
               * JUNTA com o que já estava gravado, não substitui.
               *
               * As duas etapas do site chegam separadas: o popup manda nome,
               * e-mail, telefone e de onde a pessoa veio (UTM, página, anúncio);
               * o formulário de aplicação manda as respostas. Substituindo, a
               * segunda etapa apagava a origem da primeira — e origem de lead
               * pago é justamente o que não pode sumir.
               *
               * `||` do jsonb: o da direita (o que acabou de chegar) vence nas
               * chaves repetidas.
               */
              payload: sql`${leadSourceSubmissions.payload} || ${values.payload}::jsonb`,
              updatedAt: values.updatedAt,
            },
            // targetWhere (não setWhere): o índice único é parcial
            // (WHERE external_id IS NOT NULL), e o Postgres só consegue inferir
            // um índice parcial se o ON CONFLICT repetir o mesmo predicado.
            targetWhere: sql`${leadSourceSubmissions.externalId} IS NOT NULL`,
          })
          .returning({ id: leadSourceSubmissions.id, leadId: leadSourceSubmissions.leadId })
      : await db.insert(leadSourceSubmissions).values(values)
          .returning({ id: leadSourceSubmissions.id, leadId: leadSourceSubmissions.leadId })

    // Daqui pra baixo é best-effort: o log já está gravado, e é ele que não pode
    // se perder. Se o CRM engasgar (pipeline sem etapa, funil mal configurado), a
    // requisição ainda responde 201 — o outro lado não deve reenviar por isso.
    let leadId = submission?.leadId ?? null
    let leadCreated = false

    /*
     * A submissão já conhecia o lead (é reenvio): atualiza o cadastro aqui
     * mesmo. Sem isto as respostas da segunda etapa do site ficavam SÓ na
     * tabela de submissões — o card do lead no chat e no Pipeline não via nada,
     * porque `upsertCrmLead` só roda quando ainda não há lead ligado.
     *
     * Campo vazio não entra: atualizar cadastro nunca pode apagar o que já
     * estava lá. Etapa, fonte e funil não se mexem — isso é atualização, não
     * lead novo.
     */
    if (leadId) {
      try {
        const [atual] = await db
          .select({ customAttributes: leads.customAttributes, title: leads.title, email: leads.email })
          .from(leads)
          .where(eq(leads.id, leadId))
          .limit(1)
        if (atual) {
          const preenchidos = Object.fromEntries(
            Object.entries(normalized.fields).filter(([, v]) => v !== null && v !== undefined && v !== '')
          )
          const atributos = (atual.customAttributes ?? {}) as Record<string, unknown>
          await db
            .update(leads)
            .set({
              customAttributes: { ...atributos, ...preenchidos },
              ...(atual.email ? {} : normalized.email ? { email: normalized.email } : {}),
              updatedAt: new Date(),
            })
            .where(eq(leads.id, leadId))
        }
      } catch (err) {
        console.error('[ingest] não consegui atualizar o lead do reenvio:', err)
      }
    }

    if (!leadId) {
      try {
        const lead = await upsertCrmLead(auth.organizationId, sourceDef.key, normalized, auth.memberId, ehResync)
        leadId = lead?.id ?? null
        // Promovido (era só conversa e virou lead de aquisição) conta como novo:
        // toca o "plin", entra no funil e recebe a mensagem automática.
        leadCreated = (lead?.created || lead?.promovido) ?? false
        if (leadId && submission) {
          await db.update(leadSourceSubmissions)
            .set({ leadId })
            .where(eq(leadSourceSubmissions.id, submission.id))
        }
      } catch (err) {
        console.error('[ingest] log gravado, mas falhou ao criar o lead no CRM:', err)
      }
    }

    // Avisa as telas abertas que nasceu um lead: a lista do Chat/Pipeline se
    // atualiza sozinha e o aviso sonoro toca (SomNovoLead). Sem isto, lead
    // vindo da Agenda ou do site só aparecia pra quem recarregasse a página —
    // e o "plin" nunca tocaria pro caso que mais importa, que é o lead novo
    // chegando enquanto o time está com o CRM aberto.
    if (leadId && leadCreated) {
      await publishEvent(channels.orgLeads(auth.organizationId), events.LEAD_CREATED, { id: leadId })
    }

    // Funil de atendimento — só para lead novo. Sem isso, reenviar o mesmo lead
    // (o quiz que virou "done") dispararia a mensagem de boas-vindas de novo.
    //
    // `resync` desliga o funil mesmo para lead novo: é a ressincronização em
    // massa da Agenda, que reenvia a base inteira pra trazer a agenda montada de
    // quem já estava cadastrado. Sem essa saída, rodar a ressincronização
    // mandaria a mensagem de boas-vindas pra todo lead antigo que ainda não
    // tivesse linha no CRM — de uma vez só, meses depois de ele ter se cadastrado.
    if (leadId && leadCreated && !ehResync && !semAutomacao) {
      try {
        await startFunnelForSource(auth.organizationId, sourceDef.key, leadId)
      } catch (err) {
        console.error('[ingest] lead criado, mas falhou ao iniciar o funil:', err)
      }
    }

    // 200, e não 201: o Elementor Pro (e outros plugins de webhook) só tratam
    // 200 como sucesso — qualquer outro 2xx vira "Webhook error." na tela do
    // formulário, mesmo com o lead gravado certinho. O corpo já diz o que
    // aconteceu (lead_created), então a distinção 200/201 não carrega nenhuma
    // informação que se perca, e a compatibilidade vale mais que o rigor do
    // verbo HTTP.
    await logAttempt(req, {
      resultado: 'ok',
      source: sourceDef.key,
      detalhe: ehResync ? 'resync' : semAutomacao ? 'sem_automacao' : null,
      camposRecebidos: Object.keys(rawBody),
      organizationId: auth.organizationId,
      submissionId: submission?.id ?? null,
      leadId,
    })

    return Response.json({
      data: {
        id: submission?.id ?? null,
        source: sourceDef.key,
        external_id: dedupeKey,
        lead_id: leadId,
        lead_created: leadCreated,
      },
    })
  } catch (err: any) {
    // Erro com `status` veio de authenticate() e a mensagem é pra quem chamou
    // ("token inválido"). Sem `status` é falha nossa (banco fora, bug) — aí loga
    // o motivo real e responde genérico: este endpoint é chamado por um sistema
    // externo, que não tem por que receber string de conexão ou stack trace.
    if (err?.status) return apiError(err.status, err.message)
    console.error('[ingest] erro inesperado:', err)
    return apiError(500, 'Erro interno ao registrar o lead.')
  }
}

/** Teste de credencial — quem configura o envio confere a chave antes. */
export async function handleIngestPing(req: NextRequest, sourceFromPath?: string) {
  try {
    const auth = await authenticate(req)
    if (sourceFromPath && !getLeadSource(sourceFromPath)) {
      return apiError(404, `Fonte desconhecida: "${sourceFromPath}". Válidas: ${LEAD_SOURCE_ORDER.join(', ')}.`)
    }
    return Response.json({
      data: {
        ok: true,
        organization_id: auth.organizationId,
        source: sourceFromPath ?? null,
        sources: LEAD_SOURCE_ORDER,
      },
    })
  } catch (err: any) {
    if (err?.status) return apiError(err.status, err.message)
    console.error('[ingest] erro inesperado no ping:', err)
    return apiError(500, 'Erro interno.')
  }
}
