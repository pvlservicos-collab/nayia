/**
 * A BUSCA DO IMÓVEL DA VISITA, pelo código ou pelo nome (Pedro, 03/10/2026):
 * "coloca por nome de condomínio também, ao aparecer a gente ver as opções, porque
 * lembrar do código e ir lá ver no site nos toma tempo".
 *
 * A fonte é a mesma do "Enviar imóvel": /api/imoveis-nay, que repassa a busca para
 * a lista do site (código, condomínio, bairro ou rua). Aqui a busca NÃO esconde o
 * que não está disponível: quem agenda à mão sabe o que está fazendo, e esconder
 * faria a pessoa achar que o imóvel não existe. Os nossos disponíveis vêm
 * primeiro; o resto vem depois, e a tela escreve a situação ao lado.
 *
 * Roda na tela (o componente é o EscolherImovelDaVisita).
 */
export interface ImovelDaBusca {
  codigo: string
  nome: string
  bairro: string | null
  quartos: number | null
  valor: string | null
  status: string | null
  parceiro: boolean
}

const reais = (v: number) => `R$ ${Math.round(v).toLocaleString('pt-BR')}`

function doItem(i: any): ImovelDaBusca {
  // os DOIS valores quando o imóvel tem os dois: a lista do site escreve só um em `valor`
  const precos = [
    Number(i.valorAluguel) > 0 ? `Aluguel ${reais(Number(i.valorAluguel))}` : null,
    Number(i.valorVenda) > 0 ? `Venda ${reais(Number(i.valorVenda))}` : null,
  ].filter(Boolean)
  return {
    codigo: String(i.codigo), nome: String(i.condominio || i.tipo || 'Imóvel').trim(), bairro: i.bairro || null,
    quartos: typeof i.quartos === 'number' && i.quartos > 0 ? i.quartos : null,
    valor: precos.length ? precos.join(' · ') : (i.valor ? String(i.valor) : null),
    status: i.status || null, parceiro: !!i.parceiro,
  }
}

async function pedir(q: string, extra: Record<string, string>, sinal?: AbortSignal): Promise<ImovelDaBusca[]> {
  const p = new URLSearchParams({ q, per: '10', page: '1', ...extra })
  const r = await fetch(`/api/imoveis-nay?${p.toString()}`, { signal: sinal })
  const j = r.ok ? await r.json().catch(() => ({})) : {}
  return (Array.isArray(j?.itens) ? j.itens : []).map(doItem)
}

/** Os nossos disponíveis primeiro; depois o resto do acervo, sem repetir. O código exato vai para o topo. */
export async function buscarImoveisDaVisita(q: string, sinal?: AbortSignal): Promise<ImovelDaBusca[]> {
  const [nossos, todos] = await Promise.all([pedir(q, { status: 'Disponível', parceiro: 'nao' }, sinal), pedir(q, {}, sinal)])
  const vistos = new Set<string>()
  const juntos = [...nossos, ...todos].filter((i) => (vistos.has(i.codigo) ? false : (vistos.add(i.codigo), true)))
  return [...juntos.filter((i) => i.codigo === q), ...juntos.filter((i) => i.codigo !== q)].slice(0, 14)
}

/** O imóvel de um código (para escrever o nome ao lado do #código). */
export async function imovelPeloCodigo(codigo: string, sinal?: AbortSignal): Promise<ImovelDaBusca | null> {
  if (!/^\d{1,6}$/.test(codigo)) return null
  return (await pedir(codigo, { per: '6' }, sinal)).find((i) => i.codigo === codigo) || null
}

/** "Ponta Negra · 2 quartos · Aluguel: R$ 2.600,00" */
export function resumoDoImovel(i: ImovelDaBusca): string {
  return [i.bairro, i.quartos ? `${i.quartos} ${i.quartos === 1 ? 'quarto' : 'quartos'}` : null, i.valor].filter(Boolean).join(' · ')
}
