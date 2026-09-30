/**
 * OS DOIS CHECKLISTS PREENCHÍVEIS DO FECHAMENTO (Pedro, 30/09/2026: "cria lá em
 * cima, do lado da agenda, uma aba Fechamento antes do painel, deixa lá os 2
 * checklists preenchíveis para fazermos um contrato; ao preencher, o checklist
 * é enviado ao Tel no número pessoal dele, por enquanto").
 *
 * Os documentos são os mesmos da lista que a Nay manda ao corretor
 * (nai_config: documentos_locacao / documentos_venda); os dados são os que o
 * contrato pede. A tela e a rota leem daqui, e o texto que chega ao Tel é
 * montado aqui (montarTexto) -- um lugar só.
 */
export type TipoChecklist = 'locacao' | 'venda'
export type Campo = { chave: string; rotulo: string; tipo?: 'texto' | 'marca' | 'longo' }
export type Secao = { titulo: string; campos: Campo[] }

const pessoa = (p: string): Campo[] => [
  { chave: `${p}_nome`, rotulo: 'Nome completo' },
  { chave: `${p}_cpf`, rotulo: 'CPF' },
  { chave: `${p}_rg`, rotulo: 'RG ou CNH' },
  { chave: `${p}_nacionalidade`, rotulo: 'Nacionalidade' },
  { chave: `${p}_profissao`, rotulo: 'Profissão' },
  { chave: `${p}_estado_civil`, rotulo: 'Estado civil' },
  { chave: `${p}_telefone`, rotulo: 'Telefone/WhatsApp' },
  { chave: `${p}_email`, rotulo: 'E-mail' },
  { chave: `${p}_endereco`, rotulo: 'Endereço completo com CEP' },
]
const marca = (chave: string, rotulo: string): Campo => ({ chave, rotulo, tipo: 'marca' })

export const CHECKLISTS: Record<TipoChecklist, { titulo: string; secoes: Secao[] }> = {
  locacao: {
    titulo: 'Checklist de aluguel',
    secoes: [
      { titulo: 'Imóvel e contrato', campos: [
        { chave: 'imovel_codigo', rotulo: 'Código do imóvel' },
        { chave: 'imovel_endereco', rotulo: 'Condomínio / endereço' },
        { chave: 'valor', rotulo: 'Valor do aluguel' },
        { chave: 'inicio', rotulo: 'Data de início da locação' },
        { chave: 'prazo', rotulo: 'Prazo (meses)' },
        { chave: 'garantia', rotulo: 'Garantia (caução, fiador, seguro-fiança)' },
      ] },
      { titulo: 'Corretor', campos: [
        { chave: 'corretor_nome', rotulo: 'Nome' }, { chave: 'corretor_telefone', rotulo: 'Telefone' },
      ] },
      { titulo: 'Inquilino (locatário)', campos: [
        ...pessoa('inquilino'),
        { chave: 'inquilino_pj', rotulo: 'Se PJ: razão social e CNPJ' },
      ] },
      { titulo: 'Documentos recebidos', campos: [
        marca('doc_rg', 'RG e CPF ou CNH (frente e verso, legível)'),
        marca('doc_residencia', 'Comprovante de residência'),
        marca('doc_renda', 'Comprovante de renda (3 contracheques ou 6 extratos, se autônomo)'),
        marca('doc_pj', 'Se PJ: contrato social, CNPJ e documentos dos sócios'),
      ] },
      { titulo: 'Observações', campos: [{ chave: 'obs', rotulo: 'Outras pessoas que assinam, combinados, pendências', tipo: 'longo' }] },
    ],
  },
  venda: {
    titulo: 'Checklist de venda',
    secoes: [
      { titulo: 'Imóvel e negócio', campos: [
        { chave: 'imovel_codigo', rotulo: 'Código do imóvel' },
        { chave: 'imovel_matricula', rotulo: 'Matrícula / cartório' },
        { chave: 'valor', rotulo: 'Valor da venda' },
        { chave: 'pagamento', rotulo: 'Forma de pagamento (à vista, financiamento, FGTS)' },
      ] },
      { titulo: 'Corretor', campos: [
        { chave: 'corretor_nome', rotulo: 'Nome' }, { chave: 'corretor_telefone', rotulo: 'Telefone' },
      ] },
      { titulo: 'Vendedor (proprietário)', campos: [
        ...pessoa('vendedor'),
        { chave: 'vendedor_conjuge', rotulo: 'Cônjuge (nome e CPF), se casado' },
      ] },
      { titulo: 'Comprador', campos: [
        ...pessoa('comprador'),
        { chave: 'comprador_pj', rotulo: 'Se PJ: razão social e CNPJ' },
      ] },
      { titulo: 'Documentos do vendedor', campos: [
        marca('doc_v_rg', 'RG e CPF ou CNH (e do cônjuge)'),
        marca('doc_v_certidao', 'Certidão de casamento ou nascimento atualizada'),
        marca('doc_v_residencia', 'Comprovante de residência'),
        marca('doc_v_matricula', 'Matrícula atualizada do imóvel'),
        marca('doc_v_iptu', 'Carnê do IPTU do ano ou certidão negativa'),
        marca('doc_v_condominio', 'Declaração de quitação do condomínio'),
        marca('doc_v_certidoes', 'Certidões negativas (federais, trabalhistas, protestos, cíveis)'),
      ] },
      { titulo: 'Documentos do comprador', campos: [
        marca('doc_c_rg', 'RG e CPF ou CNH (frente e verso, legível)'),
        marca('doc_c_certidao', 'Certidão de casamento ou nascimento'),
        marca('doc_c_residencia', 'Comprovante de residência'),
        marca('doc_c_renda', 'Se financiar: renda (3 contracheques ou IR) e extrato do FGTS'),
        marca('doc_c_pj', 'Se PJ: contrato social, CNPJ e documentos dos sócios'),
      ] },
      { titulo: 'Observações', campos: [{ chave: 'obs', rotulo: 'Outras pessoas que assinam, combinados, pendências', tipo: 'longo' }] },
    ],
  },
}

/** O texto que vai ao WhatsApp do Tel: só o que foi preenchido, seção por seção. */
export function montarTexto(tipo: TipoChecklist, valores: Record<string, unknown>, quem: string): string {
  const def = CHECKLISTS[tipo]
  const linhas = [`📋 *${def.titulo.toUpperCase()}* (preenchido no CRM por ${quem})`]
  for (const s of def.secoes) {
    const itens = s.campos.flatMap((c) => {
      const v = valores[c.chave]
      if (c.tipo === 'marca') return [`${v === true ? '✅' : '⬜'} ${c.rotulo}`]
      const t = String(v ?? '').trim().slice(0, 600)
      return t ? [`• ${c.rotulo}: ${t}`] : []
    })
    if (itens.length) linhas.push('', `*${s.titulo}*`, ...itens)
  }
  return linhas.join('\n').slice(0, 3800)
}
