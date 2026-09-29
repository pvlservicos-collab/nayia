/**
 * O disparo de imóvel pela tela "Enviar imóvel" (Tel, 28/09/2026).
 *
 * As paredes da Nay moram no banco dela (migração 145), e este arquivo só as
 * chama -- pelo usuário `nay_disparo`, que pode EXECUTAR três funções e nada
 * mais: não lê nem escreve tabela nenhuma. Parceiro não sai, indisponível não
 * sai, e as fotos do mesmo imóvel vão uma vez a cada 24h para cada pessoa,
 * venha o pedido da Nay, do publicador ou daqui.
 *
 *   PARCERIA (Z-API): `enfileirarNaNay` põe o envio na caixa de saída da Nay,
 *   a mesma de todo dia -- o ritmo das fotos que protege o número de
 *   banimento. Quem manda é ela; aqui só se pede.
 *
 *   API OFICIAL: `conferirParaOficial` reserva as 24h e devolve o card e as
 *   fotos; quem manda é o CRM. `liberarReserva` desfaz se o envio falhar.
 */
import { Pool } from 'pg'

let _pool: Pool | null = null

/** A conexão com o banco da Nay (papel `nay_disparo`: só EXECUTA função). Também usada por nayLeitura.ts. */
export function naydb(): Pool {
  if (!_pool) {
    const url = process.env.NAY_DISPARO_DATABASE_URL
    if (!url) throw { status: 500, message: 'NAY_DISPARO_DATABASE_URL não definida no CRM.' }
    _pool = new Pool({ connectionString: url, max: 3, statement_timeout: 20000 })
  }
  return _pool
}

/** Parceria: vai para a caixa de saída da Nay. Devolve o resumo dela ("Mandei para ..."). */
export async function enfileirarNaNay(telefone: string, codigos: number[], quem: string): Promise<string> {
  const r = await naydb().query('SELECT nai_disparo_enfileirar($1, $2::int[], $3) AS resumo',
                                [telefone, codigos, quem])
  return String(r.rows[0]?.resumo || '')
}

/**
 * O checklist de documentos (aluguel ou venda) pela caixa da Nay -- o botão do
 * card do corretor (Pedro, 29/09/2026). Migração 183. Devolve "Mandei ...", ou
 * a pergunta do que faltou.
 */
export async function checklistPelaNay(telefone: string, tipo: 'locacao' | 'venda', quem: string): Promise<string> {
  const r = await naydb().query('SELECT nai_checklist_enfileirar($1, $2, $3) AS resumo', [telefone, tipo, quem])
  return String(r.rows[0]?.resumo || '')
}

export interface Conferido {
  pode: boolean
  motivo: string | null
  card: string | null
  fotos: string[]
}

/** API oficial: confere as paredes e reserva as 24h. Só manda quem recebeu `pode`. */
export async function conferirParaOficial(telefone: string, codigo: number, quem: string): Promise<Conferido> {
  const r = await naydb().query('SELECT * FROM nai_disparo_conferir($1, $2, $3)', [telefone, codigo, quem])
  const l = r.rows[0] || {}
  return { pode: l.pode === true, motivo: l.motivo ?? null, card: l.card ?? null, fotos: l.fotos || [] }
}

/** O envio pela API oficial falhou: a reserva das 24h não vale. */
export async function liberarReserva(telefone: string, codigo: number): Promise<void> {
  await naydb().query('SELECT nai_disparo_liberar($1, $2)', [telefone, codigo])
}

/** Imóveis por disparo. Mais que isso é campanha, não envio. */
export const TETO_POR_ENVIO = 10

/** Cada lista vale "qualquer um deles"; vazia = sem filtro (migração 150). */
export interface FiltroFaixa {
  finalidade: 'aluguel' | 'venda' | null
  vmin: number | null
  vmax: number | null
  bairros: string[]
  mobilias: ('mobiliado' | 'semi')[]
  tipos: string[]
  /** exatos; 4 = 4 ou mais */
  quartos: number[]
}

export interface ImovelAchado {
  codigo: number
  titulo: string
  tipo: string | null
  bairro: string | null
  quartos: number | null
  mobilia: string | null
  valorVenda: number | null
  valorAluguel: number | null
  fotos: number
  capa: string | null
}

/**
 * O disparo por faixa (migração 148): acha os imóveis de uma faixa de valor,
 * bairro, mobília, tipo e quartos -- só o que a caixa de saída aceita mandar
 * (nosso, disponível, no mercado). Do mais barato para o mais caro.
 */
export async function buscarNaNay(f: FiltroFaixa, limite = 60): Promise<ImovelAchado[]> {
  const lista = <T,>(v: T[]) => (v.length ? v : null)
  const r = await naydb().query(
    'SELECT * FROM nai_disparo_buscar($1, $2, $3, $4::text[], $5::text[], $6::text[], $7::int[], $8)',
    [f.finalidade, f.vmin, f.vmax, lista(f.bairros), lista(f.mobilias), lista(f.tipos), lista(f.quartos), limite])
  const n = (v: unknown) => (v === null || v === undefined ? null : Number(v))
  return r.rows.map((l: any) => ({
    codigo: Number(l.codigo), titulo: l.titulo, tipo: l.tipo, bairro: l.bairro,
    quartos: n(l.quartos), mobilia: l.mobilia, valorVenda: n(l.valor_venda),
    valorAluguel: n(l.valor_aluguel), fotos: Number(l.fotos || 0), capa: l.capa,
  }))
}

export interface Opcao { valor: string; n: number }

/** O que existe no nosso banco para cada filtro (só do que pode sair) -- a lista que desce. */
export async function opcoesNaNay(): Promise<{ bairros: Opcao[]; tipos: Opcao[] }> {
  const r = await naydb().query('SELECT campo, valor, n FROM nai_disparo_opcoes()')
  const de = (campo: string) => r.rows.filter((l: any) => l.campo === campo).map((l: any) => ({ valor: l.valor, n: Number(l.n) }))
  return { bairros: de('bairro'), tipos: de('tipo') }
}
