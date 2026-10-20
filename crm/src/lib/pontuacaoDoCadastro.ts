/**
 * A PORCENTAGEM QUE VAI SE PREENCHENDO (Pedro, 01/10/2026): "esse popup de
 * cadastro vai ter ali encima uma porcentagem que vai se preenchendo conforme
 * eu vou adicionando informações sobre esse novo imóvel".
 *
 * É a MESMA RÉGUA da aba Imóveis -- `nai_imovel_pontos`, migração 244. Aqui ela
 * está repetida em TypeScript só para a barra andar enquanto a pessoa digita,
 * sem ida e volta ao banco a cada tecla. Quem vale é o banco: ao salvar, o site
 * devolve a pontuação de verdade e o card passa a mostrar aquela.
 *
 * Se mexer nos pesos da 244, mexa aqui também -- ou a prévia mente.
 *
 *   essencial (50)  tipo 8 · bairro 8 · valor 8 · quartos 6 · área 6 · foto 8 · proprietário 6
 *   importante (35) banheiros 4 · vagas 4 · mobília 5 · condomínio 4 · endereço 4 ·
 *                   características 6 · descrição 4 · taxa de condomínio 4
 *   detalhe (15)    suítes 3 · andar 3 · sol 3 · IPTU 3 · vagas cobertas 3
 *
 * E as mesmas isenções: casa/terreno/galpão não têm andar nem taxa; imóvel de
 * rua não é cobrado de condomínio; só de venda não é cobrado de mobília.
 */

export interface CamposDoCadastro {
  tipo?: string | null
  bairro?: string | null
  condominio?: string | null
  logradouro?: string | null
  /* não entram na régua, mas andam junto no formulário do popup */
  numero?: string | null
  complemento?: string | null
  cidade?: string | null
  estado?: string | null
  quartos?: string | number | null
  suites?: string | number | null
  banheiros?: string | number | null
  vagas?: string | number | null
  vagasCobertas?: string | number | null
  areaUtil?: string | number | null
  areaTotal?: string | number | null
  andar?: string | null
  sol?: string | null
  mobilia?: string | null
  taxaCondominio?: string | number | null
  iptu?: string | number | null
  aluguel?: string | number | null
  venda?: string | number | null
  caracteristicas?: string[] | null
  descricao?: string | null
  inclusoNoAluguel?: string | null
  finoAcabamento?: string | null      // Sim / Não / vazio (pendente), extras."fino acabamento" (20/10)
}

export type BlocoDoPeso = 'essencial' | 'importante' | 'detalhe'
export interface Pontuacao { pct: number; pontos: number; de: number; falta: string[]; faltaEssencial: string[] }

const cheio = (v: unknown) => String(v ?? '').trim() !== ''
const numero = (v: unknown) => {
  const t = String(v ?? '').trim().replace(/\./g, '').replace(',', '.')
  const n = Number(t)
  return t !== '' && Number.isFinite(n) ? n : null
}
const semAcento = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()

/* os nomes de tipo que aparecem na coluna do condomínio e não são condomínio nenhum */
const NAO_E_CONDOMINIO = new Set([
  'casa', 'casa de condominio', 'apartamento', 'apartamento em via publica', 'sala/andar', 'sala',
  'loja', 'loja/ponto', 'galpao/deposito', 'lote', 'lote em condominio', 'flat', 'cobertura',
  'predio', 'terreno', 'condominio nao identificado',
])

function regua(c: CamposDoCadastro, fotos: number, temDono: boolean): Array<[string, number, boolean, boolean, BlocoDoPeso]> {
  const tipo = semAcento(String(c.tipo || ''))
  const condoNome = semAcento(String(c.condominio || '').trim())
  const emCondominio = condoNome !== '' && !NAO_E_CONDOMINIO.has(condoNome)
  const vertical = /^(apartamento|flat|cobertura|sala|kitnet|studio)/.test(tipo)
  const aluga = (numero(c.aluguel) || 0) > 0
  const incluso = semAcento(String(c.inclusoNoAluguel || ''))
  return [
    ['tipo', 8, cheio(c.tipo), true, 'essencial'],
    ['bairro', 8, cheio(c.bairro), true, 'essencial'],
    ['valor', 8, (numero(c.aluguel) || 0) > 0 || (numero(c.venda) || 0) > 0, true, 'essencial'],
    ['quartos', 6, numero(c.quartos) !== null, !/^(lote|terreno|galp|loja|sala|pr)/.test(tipo), 'essencial'],
    ['área', 6, (numero(c.areaUtil) || 0) > 0 || (numero(c.areaTotal) || 0) > 0, true, 'essencial'],
    ['fotos', 8, fotos > 0, true, 'essencial'],
    ['proprietário', 6, temDono, true, 'essencial'],
    ['banheiros', 4, numero(c.banheiros) !== null, !/^(lote|terreno)/.test(tipo), 'importante'],
    ['vagas', 4, numero(c.vagas) !== null, !/^(lote|terreno)/.test(tipo), 'importante'],
    ['mobília', 5, cheio(c.mobilia), aluga && /^(apartamento|casa|flat|cobertura|kitnet|studio)/.test(tipo), 'importante'],
    ['condomínio', 4, emCondominio, /condomin/.test(tipo) || /^(apartamento|flat|cobertura)/.test(tipo), 'importante'],
    ['endereço', 4, cheio(c.logradouro), true, 'importante'],
    ['características', 6, (c.caracteristicas || []).length > 0, true, 'importante'],
    ['descrição', 4, cheio(c.descricao), true, 'importante'],
    ['taxa de condomínio', 4, numero(c.taxaCondominio) !== null || /condom/.test(incluso), emCondominio && aluga, 'importante'],
    ['suítes', 3, numero(c.suites) !== null, !/^(lote|terreno|galp|loja|sala)/.test(tipo), 'detalhe'],
    ['sol', 3, cheio(c.sol), true, 'detalhe'],
    ['IPTU', 3, numero(c.iptu) !== null || /iptu/.test(incluso), true, 'detalhe'],
    ['vagas cobertas', 3, numero(c.vagasCobertas) !== null, !/^(lote|terreno)/.test(tipo), 'detalhe'],
  ]
}

export interface CampoDaRegua { campo: string; peso: number; tem: boolean; bloco: BlocoDoPeso }

/**
 * A régua aberta, campo por campo (só o que SE APLICA a este imóvel). O popup
 * do CRM usa isto para a barra de cada seção -- assim não existe uma segunda
 * tabela de pesos andando por aí, que um dia discordaria desta.
 */
export function detalheDoCadastro(c: CamposDoCadastro, fotos: number, temDono: boolean): CampoDaRegua[] {
  return regua(c, fotos, temDono)
    .filter(([, , , aplica]) => aplica)
    .map(([campo, peso, tem, , bloco]) => ({ campo, peso, tem, bloco }))
}

export function pontuacaoDoCadastro(c: CamposDoCadastro, fotos: number, temDono: boolean): Pontuacao {
  const lista = regua(c, fotos, temDono)

  let pontos = 0
  let de = 0
  const falta: string[] = []
  const faltaEssencial: string[] = []
  for (const [campo, peso, tem, aplica, bloco] of lista) {
    if (!aplica) continue
    de += peso
    if (tem) pontos += peso
    else {
      falta.push(campo)
      if (bloco === 'essencial') faltaEssencial.push(campo)
    }
  }
  return { pct: de > 0 ? Math.round((100 * pontos) / de) : 0, pontos, de, falta, faltaEssencial }
}

/** A cor da barra, a mesma da aba Imóveis: verde do 90, âmbar até 50, vermelho abaixo. */
export function corDaPontuacao(pct: number): string {
  return pct >= 90 ? '#3f9c6d' : pct >= 50 ? '#c4762f' : '#b42323'
}
