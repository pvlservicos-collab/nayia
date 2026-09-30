/**
 * OS DOCUMENTOS E OS DADOS DO FECHAMENTO (Pedro, 30/09/2026): na aba Fechamento a
 * Rayssa vê as mídias que a pessoa mandou, diz qual documento é cada uma (quando a
 * Nay não identificou), separa CORRETOR e CLIENTE, e o checklist se preenche com o
 * que veio escrito na conversa. As rotas (api/parceria/fechamento/*) usam daqui:
 *
 *   CATALOGO               os documentos, na ordem do checklist, com o que é exigido
 *   identificarDocumento   o automático: nome do arquivo, legenda, mensagem ao lado
 *   lerCampos              os dados do checklist a partir das mensagens de texto
 *
 * Sem OCR: o que não dá para ler do texto fica null, para a Rayssa escolher.
 */
import { CHECKLISTS, type TipoChecklist } from '@/lib/checklistFechamento'

export type Papel = 'inquilino' | 'comprador' | 'vendedor' | 'corretor'
export type Dono = 'corretor' | 'cliente'

export interface DocumentoDoCatalogo {
  chave: string
  rotulo: string
  papeis: Papel[]
  /** qual caixinha do checklist ele marca, por tipo e papel */
  marca: { locacao?: string; venda_comprador?: string; venda_vendedor?: string }
  /** exigido em cada tipo, para quais papéis (as listas documentos_locacao/venda da nai_config) */
  exigidoPara: { locacao?: Papel[]; venda?: Papel[] }
}

const CLIENTE: Papel[] = ['inquilino', 'comprador', 'vendedor']

export const CATALOGO: DocumentoDoCatalogo[] = [
  { chave: 'rg_cnh', rotulo: 'RG e CPF ou CNH', papeis: [...CLIENTE, 'corretor'],
    marca: { locacao: 'doc_rg', venda_comprador: 'doc_c_rg', venda_vendedor: 'doc_v_rg' },
    exigidoPara: { locacao: ['inquilino'], venda: ['comprador', 'vendedor'] } },
  { chave: 'cpf', rotulo: 'CPF (separado)', papeis: [...CLIENTE, 'corretor'],
    marca: { locacao: 'doc_rg', venda_comprador: 'doc_c_rg', venda_vendedor: 'doc_v_rg' }, exigidoPara: {} },
  { chave: 'comprovante_residencia', rotulo: 'Comprovante de residência', papeis: CLIENTE,
    marca: { locacao: 'doc_residencia', venda_comprador: 'doc_c_residencia', venda_vendedor: 'doc_v_residencia' },
    exigidoPara: { locacao: ['inquilino'], venda: ['comprador', 'vendedor'] } },
  { chave: 'comprovante_renda', rotulo: 'Comprovante de renda (contracheque, extrato, IR)', papeis: ['inquilino', 'comprador'],
    marca: { locacao: 'doc_renda', venda_comprador: 'doc_c_renda' }, exigidoPara: { locacao: ['inquilino'] } },
  { chave: 'extrato_fgts', rotulo: 'Extrato do FGTS', papeis: ['comprador'],
    marca: { venda_comprador: 'doc_c_renda' }, exigidoPara: {} },
  { chave: 'certidao_estado_civil', rotulo: 'Certidão de casamento ou nascimento', papeis: ['comprador', 'vendedor'],
    marca: { venda_comprador: 'doc_c_certidao', venda_vendedor: 'doc_v_certidao' },
    exigidoPara: { venda: ['comprador', 'vendedor'] } },
  { chave: 'contrato_social_cnpj', rotulo: 'Contrato social / CNPJ (se PJ)', papeis: ['inquilino', 'comprador'],
    marca: { locacao: 'doc_pj', venda_comprador: 'doc_c_pj' }, exigidoPara: {} },
  { chave: 'matricula', rotulo: 'Matrícula atualizada do imóvel', papeis: ['vendedor'],
    marca: { venda_vendedor: 'doc_v_matricula' }, exigidoPara: { venda: ['vendedor'] } },
  { chave: 'iptu', rotulo: 'IPTU do ano ou certidão negativa de IPTU', papeis: ['vendedor'],
    marca: { venda_vendedor: 'doc_v_iptu' }, exigidoPara: { venda: ['vendedor'] } },
  { chave: 'declaracao_condominio', rotulo: 'Declaração de quitação do condomínio', papeis: ['vendedor'],
    marca: { venda_vendedor: 'doc_v_condominio' }, exigidoPara: {} },
  { chave: 'certidoes_negativas', rotulo: 'Certidões negativas (federais, trabalhistas, protestos, cíveis)', papeis: ['vendedor'],
    marca: { venda_vendedor: 'doc_v_certidoes' }, exigidoPara: { venda: ['vendedor'] } },
  { chave: 'creci', rotulo: 'CRECI do corretor', papeis: ['corretor'], marca: {}, exigidoPara: {} },
  { chave: 'outro', rotulo: 'Outro documento', papeis: [...CLIENTE, 'corretor'], marca: {}, exigidoPara: {} },
]

const POR_CHAVE = new Map(CATALOGO.map((d) => [d.chave, d]))
export const documentoDaChave = (chave: string | null | undefined) => (chave ? POR_CHAVE.get(chave) ?? null : null)

export function donoDoPapel(papel: Papel | null | undefined): Dono | null {
  if (!papel) return null
  return papel === 'corretor' ? 'corretor' : 'cliente'
}

/** A caixinha do checklist que um documento marca, no tipo e papel dados. */
export function marcaDoDocumento(chave: string, tipo: TipoChecklist, papel: Papel | null): string | null {
  const d = POR_CHAVE.get(chave)
  if (!d) return null
  // documento do CORRETOR não marca a caixinha do cliente (o RG dele não é o do inquilino)
  if (papel === 'corretor') return null
  if (tipo === 'locacao') return d.marca.locacao ?? null
  if (papel === 'vendedor') return d.marca.venda_vendedor ?? null
  if (papel === 'comprador') return d.marca.venda_comprador ?? null
  return d.marca.venda_comprador ?? d.marca.venda_vendedor ?? null
}

/** O catálogo como a tela recebe: na ordem, com `exigido` do tipo em questão. */
export function catalogoPara(tipo: TipoChecklist) {
  return CATALOGO.map((d, i) => ({
    chave: d.chave, rotulo: d.rotulo, papeis: d.papeis, marca: d.marca, ordem: i + 1,
    exigido: (d.exigidoPara[tipo] || []).length > 0,
    exigidoPara: d.exigidoPara[tipo] || [],
  }))
}

// ---------------------------------------------------------------------------
// O AUTOMÁTICO
// ---------------------------------------------------------------------------
export function normalizar(t: string | null | undefined): string {
  return String(t || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()
    .replace(/[_\-.]+/g, ' ').replace(/\s+/g, ' ').trim()
}

/** Na ordem: o mais específico primeiro (FGTS antes de extrato, certidão negativa antes de certidão). */
const REGRAS: [string, RegExp][] = [
  ['extrato_fgts', /\bfgts\b/],
  ['certidoes_negativas', /\bcertid(ao|oes) negativa|\bcnd\b|\bprotesto|trabalhist|debitos? federa|acoes? civeis/],
  ['iptu', /\biptu\b/],
  ['declaracao_condominio', /(quitacao|declaracao|nada consta).{0,25}condominio/],
  ['matricula', /\bmatricula\b/],
  ['certidao_estado_civil', /\bcertidao\b/],
  ['contrato_social_cnpj', /contrato social|\bcnpj\b/],
  // medido nas conversas reais (30/09): "recibodepagamento DE PROLABORE", "Faturamento"
  ['comprovante_renda', /contra ?cheque|holerite|\brenda\b|\bextrato|imposto de renda|\birpf\b|declaracao de ir\b|pro ?labore|recibo ?de ?pagamento|\bfaturamento\b|\bdecore\b/],
  ['comprovante_residencia', /comprovante de (residencia|endereco)|conta de (luz|energia|agua)|amazonas energia|aguas de manaus|\bresidencia\b|\bfatura\b/],
  ['creci', /\bcreci\b/],
  // "REPUBLICA FEDERATIVA DO BRASIL.pdf" é o cabeçalho do RG/CNH; "exportado pela CDT" é a CNH digital
  ['rg_cnh', /\brg\b|\bidentidade\b|\bcnh\b|habilitacao|carteira de motorista|\bdoc (frente|verso)\b|\bfrente e verso\b|republica federativa do brasil|\bcdt\b|carteira digital de transito/],
  ['cpf', /\bcpf\b/],
]

const REGRAS_PAPEL: [Papel, RegExp][] = [
  ['corretor', /\b(meu|minha|do corretor|da corretora)\b.{0,15}\bcreci\b|\bcreci\b/],
  ['inquilino', /\b(inquilin[oa]|locatari[oa])\b/],
  ['comprador', /\b(comprador[a]?)\b/],
  ['vendedor', /\b(vendedor[a]?|proprietari[oa]|don[oa] do imovel)\b/],
]

export interface Identificado {
  documento: string | null
  papel: Papel | null
  motivo: string | null
}

/**
 * O documento pelo que veio escrito: o nome do arquivo, a legenda e as mensagens
 * de texto da mesma pessoa até 2 minutos antes/depois ("segue o rg dele").
 * O papel vem do texto; sem isso, do documento e do tipo do fechamento.
 */
export function identificarDocumento(
  nomeArquivo: string | null, legenda: string | null, vizinhas: string[], tipo: TipoChecklist | null,
): Identificado {
  // mensagem ao lado só se for curta ("segue o rg dele"): a longa é o formulário
  // de dados, e "renda de 5 mil" nela não diz o que é a foto
  const fontes: [string, string | null][] = [
    ['nome do arquivo', nomeArquivo], ['legenda', legenda],
    ...vizinhas.filter((v) => String(v || '').trim().length <= 80).map((v): [string, string] => ['mensagem', v]),
  ]
  let documento: string | null = null
  let motivo: string | null = null
  for (const [onde, texto] of fontes) {
    const n = normalizar(texto)
    if (!n || n === '[figurinha]') continue
    const achou = REGRAS.find(([, rx]) => rx.test(n))
    if (achou) {
      documento = achou[0]
      motivo = `${onde}: "${String(texto).trim().slice(0, 60)}"`
      break
    }
  }
  const tudo = normalizar(fontes.map(([, t]) => t || '').join(' '))
  let papel: Papel | null = REGRAS_PAPEL.find(([, rx]) => rx.test(tudo))?.[0] ?? null
  if (!papel && documento) {
    const d = POR_CHAVE.get(documento)!
    if (d.papeis.length === 1) papel = d.papeis[0]
    else if (tipo === 'locacao' && d.papeis.includes('inquilino')) papel = 'inquilino'
  }
  return { documento, papel, motivo }
}

// ---------------------------------------------------------------------------
// OS DADOS DO CHECKLIST
// ---------------------------------------------------------------------------
export interface MensagemDeTexto { activityId: string; texto: string }
export interface CamposLidos {
  valores: Record<string, string | boolean>
  origem: Record<string, { activityId: string; trecho: string }>
}

/** Rótulo escrito pela pessoa -> campo (sem o prefixo da pessoa). */
const ROTULOS: [RegExp, string][] = [
  [/^nome( completo)?$/, 'nome'],
  [/^cpf$/, 'cpf'],
  [/^(rg|identidade|cnh|rg\/cpf|documento)$/, 'rg'],
  [/^nacionalidade$/, 'nacionalidade'],
  [/^profissao$/, 'profissao'],
  [/^estado civil$/, 'estado_civil'],
  [/^(telefone|celular|whatsapp|telefone\/whatsapp|contato|fone)$/, 'telefone'],
  [/^e ?mail$/, 'email'],
  [/^endereco( completo)?( com cep)?$/, 'endereco'],
  [/^(razao social|cnpj)$/, 'pj'],
  [/^conjuge$/, 'conjuge'],
]
const ROTULOS_DO_NEGOCIO: [RegExp, string][] = [
  [/^(codigo|cod|codigo do imovel|imovel codigo)$/, 'imovel_codigo'],
  [/^(condominio|imovel|endereco do imovel)$/, 'imovel_endereco'],
  [/^(valor|valor do aluguel|aluguel|valor da venda)$/, 'valor'],
  [/^(data de inicio|inicio|inicio da locacao|data de inicio da locacao)$/, 'inicio'],
  [/^(prazo|prazo do contrato)$/, 'prazo'],
  [/^garantia$/, 'garantia'],
  [/^(matricula|cartorio)$/, 'imovel_matricula'],
  [/^(pagamento|forma de pagamento)$/, 'pagamento'],
]

function pessoaDaSecao(linha: string, tipo: TipoChecklist): string | null {
  if (/\b(inquilin|locatari)/.test(linha)) return 'inquilino'
  if (tipo === 'venda' && /\bcomprador/.test(linha)) return 'comprador'
  if (tipo === 'venda' && /\b(vendedor|proprietari)/.test(linha)) return 'vendedor'
  return null
}

/**
 * Lê as mensagens (da mais velha para a mais nova; a mais nova vence): pares
 * "Rótulo: valor" -- o corretor costuma devolver o modelo preenchido -- e, sem
 * rótulo, CPF, e-mail e estado civil soltos. O que vem de uma seção "Comprador"
 * ou "Vendedor" vai para essa pessoa; sem seção, locação é o inquilino e venda,
 * o comprador. Só sugere: a tela preenche e a Rayssa confere.
 */
export function lerCampos(mensagens: MensagemDeTexto[], tipo: TipoChecklist): CamposLidos {
  const validos = new Set(CHECKLISTS[tipo].secoes.flatMap((s) => s.campos.map((c) => c.chave)))
  const valores: Record<string, string | boolean> = {}
  const origem: CamposLidos['origem'] = {}
  const padrao = tipo === 'locacao' ? 'inquilino' : 'comprador'
  const por = (campo: string, valor: string, m: MensagemDeTexto, trecho: string) => {
    if (!validos.has(campo) || !valor) return
    valores[campo] = valor.slice(0, 300)
    origem[campo] = { activityId: m.activityId, trecho: trecho.slice(0, 120) }
  }
  for (const m of mensagens) {
    let pessoa = padrao
    for (const cru of String(m.texto || '').split(/\r?\n/)) {
      const linha = cru.replace(/^[\s•*\-–✅☑️▪️]+/, '').trim()
      if (!linha) continue
      const n = normalizar(linha)
      const secao = pessoaDaSecao(n, tipo)
      const par = linha.match(/^([^:]{2,40}):\s*(.+)$/)
      if (secao && !par) { pessoa = secao; continue }
      if (par) {
        const rot = normalizar(par[1]).replace(/[^a-z0-9/ ]/g, '').trim()
        const valor = par[2].trim()
        // "Comprador: João Silva" -- abre a seção e já é o nome
        if (secao && /^(compradora?|vendedora?|inquilin[oa]|locatari[oa]|proprietari[oa])$/.test(rot)) {
          pessoa = secao
          por(`${secao}_nome`, valor, m, linha)
          continue
        }
        const pessoal = ROTULOS.find(([rx]) => rx.test(rot))
        if (pessoal) {
          const campo = pessoal[1] === 'conjuge' ? 'vendedor_conjuge' : `${pessoa}_${pessoal[1]}`
          por(campo, valor, m, linha)
          continue
        }
        const negocio = ROTULOS_DO_NEGOCIO.find(([rx]) => rx.test(rot))
        if (negocio) { por(negocio[1], valor, m, linha); continue }
      }
      // sem rótulo: o que tem forma própria
      // CPF sem rótulo só no formato 000.000.000-00: 11 dígitos soltos é celular
      const cpf = linha.match(/\b\d{3}\.\d{3}\.\d{3}-\d{2}\b/)
      if (cpf && !valores[`${pessoa}_cpf`]) por(`${pessoa}_cpf`, cpf[0], m, linha)
      const email = linha.match(/[\w.+-]+@[\w-]+\.[\w.]+/)
      if (email && !valores[`${pessoa}_email`]) por(`${pessoa}_email`, email[0], m, linha)
      const civil = n.match(/\b(solteir[oa]|casad[oa]|divorciad[oa]|separad[oa]|viuv[oa]|uniao estavel)\b/)
      if (civil && !valores[`${pessoa}_estado_civil`]) por(`${pessoa}_estado_civil`, civil[0], m, linha)
    }
  }
  return { valores, origem }
}

/** Os campos de texto que ainda estão vazios (sem os opcionais: PJ, cônjuge, observações). */
export function camposQueFaltam(tipo: TipoChecklist, valores: Record<string, unknown>): string[] {
  return CHECKLISTS[tipo].secoes.flatMap((s) => s.campos)
    .filter((c) => c.tipo !== 'marca' && !/(_pj|_conjuge|^obs)$/.test(c.chave) && c.chave !== 'obs')
    .filter((c) => !String(valores[c.chave] ?? '').trim())
    .map((c) => c.chave)
}
