/**
 * GUIA DE ATENDIMENTO (Pedro, 31/10/2026): "analise todo atendimento e cria um documento como regras do Tel, um documento
 * de inteligência ... focado em ser um guia de atendimento para aumentar nossa conversão, e analise os imóveis que tiveram
 * a maior visita e veja os componentes das conversas".
 *
 * De onde saiu (31/10): as conversas da Parceria nos 3 dias antes de cada visita (123 visitas reais, sem as de teste),
 * 70 corretores que pediram imóvel e nunca visitaram, os 7 dias antes de cada um dos 27 fechamentos, as 96 conversas de
 * cliente final do 8595, as respostas do Tel às dúvidas da Nay (pergunta_fila) e o que ele contou por imóvel
 * (imovel_conhecimento). Os números de "lift" comparam o que foi visitado com o catálogo disponível.
 * Nada aqui tem nome de cliente nem telefone. Leitura nova = trocar os textos e a DATA_DA_LEITURA.
 */

export interface Regra {
  titulo: string
  quando?: string
  faca: string
  exemplo?: string
  por?: string
  palavras?: string[]
}

export interface Secao {
  id: string
  titulo: string
  resumo: string
  regras: Regra[]
}

export const DATA_DA_LEITURA = '31/10/2026'
export const FONTE_DA_LEITURA = '123 visitas, 27 fechamentos, 70 pedidos que não viraram visita e 96 clientes do 8595, de 10/09 a 31/10.'

export const NUMEROS = [
  { valor: '16%', rotulo: 'dos corretores que pedem visitam', detalhe: '64 de 410 corretores que pediram imóvel desde 10/09' },
  { valor: '27', rotulo: 'fechamentos iniciados', detalhe: '20 concluídos; quase sempre de 2 a 6 dias depois da visita' },
  { valor: '4,5x', rotulo: 'mobiliado puxa visita', detalhe: 'é 9% do catálogo e 38% das visitas; com modulados e ar, 3x' },
  { valor: '2,9x', rotulo: 'prédio novo puxa visita', detalhe: 'entregue de 2018 para cá: 3,5% do catálogo e 10% das visitas' },
  { valor: '2,3x', rotulo: 'locação puxa visita', detalhe: '21% do catálogo é só locação e leva 48% das visitas' },
  { valor: '0,2x', rotulo: 'venda de 300 mil a 1 milhão', detalhe: '46% do catálogo e só 10% das visitas' },
  { valor: '1 em 4', rotulo: 'imóveis visitados já saiu', detalhe: '16 de 60 estão alugados ou vendidos: confirme antes de oferecer' },
  { valor: 'Sábado', rotulo: 'o dia que mais pede visita', detalhe: '30 pedidos no sábado, 5 no domingo; os outros dias, 17 a 24' },
]

export interface MaisVisitado {
  codigo: number
  nome: string
  ficha: string
  bairro: string
  valor: string
  visitas: number
  fechamentos: number
  porque: string
}

export const MAIS_VISITADOS: MaisVisitado[] = [
  { codigo: 5758, nome: 'Kopenhagen', ficha: 'apto 2 quartos (1 suíte), 70 m², 2º andar, modulados e ar', bairro: 'Parque 10', valor: 'venda R$ 270 mil', visitas: 12, fechamentos: 4,
    porque: 'Venda abaixo de 300 mil no Parque 10, financiável com FGTS. Fechou a 265 mil (o piso do dono). Travava na chave: dono viajando.' },
  { codigo: 2228, nome: 'Plaza Del Rey', ficha: 'apto 2 quartos, 59 m², 2º andar, elevador, mobiliado', bairro: 'Flores', valor: 'venda R$ 300 mil', visitas: 7, fechamentos: 3,
    porque: 'Mobiliado e no teto de quem financia até 300 mil. 5 corretores diferentes; ia junto com o Kopenhagen na mesma visita.' },
  { codigo: 3078, nome: 'Smile Parque das Flores', ficha: 'apto 2 quartos, 60 m², elevador, lazer completo', bairro: 'Flores', valor: 'aluguel R$ 3.200', visitas: 6, fechamentos: 0,
    porque: 'Aluguel com água, gás e condomínio inclusos. Perdeu as 3 visitas por causa da dona (desmarcou, imóvel sem energia).' },
  { codigo: 2462, nome: 'Residencial Tapajós', ficha: 'casa de condomínio, 4 quartos, 250 m²', bairro: 'Tarumã', valor: 'aluguel R$ 7.000', visitas: 6, fechamentos: 0,
    porque: 'Casa grande em condomínio por 7 mil. Não fechou: tinha inquilino até o dia 21 e o valor no grupo estava diferente do cadastro.' },
  { codigo: 5725, nome: 'Jardim das Cerejeiras', ficha: 'apto 3 quartos, 62 m², 3º andar, elevador, prédio de 2020', bairro: 'Parque 10', valor: 'aluguel R$ 3.600', visitas: 5, fechamentos: 2,
    porque: '5 corretores diferentes. Prédio novo, 3 quartos abaixo de 4 mil, taxa inclusa. O dono sugeriu outro horário e o corretor aceitou na hora.' },
  { codigo: 5739, nome: 'Life Parque Dez', ficha: 'apto 3 quartos, 85 m², 8º andar, mobiliado, lazer completo', bairro: 'Parque 10', valor: 'aluguel R$ 5.878', visitas: 5, fechamentos: 1,
    porque: 'Mobiliado com lazer completo. Entrou como o "prédio mais novo" para quem achou o Saint Martin antigo.' },
  { codigo: 9045, nome: 'Bosque das Palmas', ficha: 'casa de condomínio, 3 quartos, 190 m², modulados e ar', bairro: 'Ponta Negra', valor: 'aluguel R$ 5.500', visitas: 5, fechamentos: 0,
    porque: 'Chegou como alternativa a casas já alugadas ("procuro outro parecido?"). Hoje está alugado.' },
  { codigo: 2014, nome: 'Rio Amazonas', ficha: 'apto 3 quartos, 130 m², 5º andar, elevador', bairro: 'Aleixo', valor: 'aluguel R$ 4.300', visitas: 5, fechamentos: 0,
    porque: 'Muito espaço por menos de 4.500. A chave fica com a administração do dono, só de segunda a sexta.' },
  { codigo: 5724, nome: 'Conquista Rio Negro', ficha: 'apto 2 quartos, 42 m², 3º andar sem elevador, mobiliado', bairro: 'Ponta Negra', valor: 'aluguel R$ 2.600', visitas: 5, fechamentos: 0,
    porque: 'O mobiliado mais barato de Ponta Negra. O que pesa contra: 3 lances de escada.' },
  { codigo: 2944, nome: 'Maison Rochelle', ficha: 'apto 3 quartos, 78 m², 2º andar, mobiliado', bairro: 'N. S. das Graças', valor: 'aluguel R$ 3.800', visitas: 4, fechamentos: 0,
    porque: 'Mobiliado com 3 quartos abaixo de 4 mil. Travou porque a dona mora fora de Manaus e demorava a confirmar.' },
  { codigo: 9030, nome: 'Park Golf', ficha: 'apto 2 quartos, 2º andar, prédio de 2026', bairro: 'Novo Aleixo', valor: 'aluguel R$ 2.600', visitas: 2, fechamentos: 2,
    porque: 'Prédio novo, 2 visitas e 2 fechamentos. Ia junto com o Estilo Golf no mesmo passeio (13h20 / 14h).' },
  { codigo: 5731, nome: 'Tropical Executive (flat)', ficha: 'flat 1 suíte, 34 m², 12º andar, mobiliado', bairro: 'Ponta Negra', valor: 'aluguel R$ 5.000', visitas: 2, fechamentos: 2,
    porque: 'Cliente executivo ou transferido: pronto para morar. Caução de 6 meses.' },
]

export const SECOES: Secao[] = [
  {
    id: 'regras-do-tel', titulo: 'Regras do Tel',
    resumo: 'Como o Tel responde. Valem para a Nay e para quem digita à mão, no WhatsApp Parceria e no Leads.',
    regras: [
      { titulo: 'Filtro antes do imóvel, uma pergunta por vez',
        faca: 'Perguntar nesta ordem: alugar ou comprar, até que valor, quais bairros, apartamento ou casa e, só na locação, mobiliado ou semi. Uma pergunta por mensagem. Só depois mandar a lista.',
        por: 'Corretor que recebeu imóvel sem filtro ganhou oferta fora do pedido (11 dos 70 que não visitaram).',
        palavras: ['filtro', 'perguntas', 'ordem', 'lista'] },
      { titulo: 'O que o corretor já disse não se pergunta de novo',
        faca: 'Antes de perguntar, ler a conversa. Se ele colou o card ou citou o código ou o condomínio, ir direto ao que ele quer.',
        exemplo: 'O corretor cola o card do 2944 e pergunta "tá disponível?" → "Sim, está disponível. Qual dia e horário fica bom para a visita?"',
        por: '"De qual imóvel você fala?" repetido derrubou conversas ("Não quero falar com a IA"; "Você é difícil de falar"). Apareceu em ~15 conversas.',
        palavras: ['robô', 'IA', 'repetida', 'código', 'card'] },
      { titulo: 'Faixa de valor firme',
        faca: 'Oferecer de 20% abaixo a 10% acima do teto do cliente. Venda e locação não se misturam.',
        por: 'Casa de 9 mil para teto de 7 mil, venda de 2 milhões para quem queria alugar: o corretor some ou reclama.',
        palavras: ['valor', 'teto', 'faixa', 'venda', 'locação'] },
      { titulo: 'Card e fotos para quem pede; "sim" para quem só pergunta',
        quando: 'O corretor pergunta se está disponível.',
        faca: 'Responder "Sim, está disponível. Quer que eu te mande o card e as fotos?". Se ele pede o imóvel, mandar card + fotos na hora e já perguntar o horário.',
        exemplo: '"Aqui as fotos. Se quiser, me diz o dia e o horário que fica bom pro seu cliente e eu vejo a visita."',
        palavras: ['disponível', 'fotos', 'card'] },
      { titulo: 'Andar: primeiro a faixa',
        faca: 'Na primeira vez, dizer andar baixo, médio ou alto (até o 3º é baixo, até o 7º é médio, acima é alto). Prédio sem elevador: dizer os lances de escada. Se ele insistir e o prédio tiver elevador, dizer o número.',
        palavras: ['andar', 'escada', 'elevador', 'térreo'] },
      { titulo: 'Localização: bairro e condomínio',
        faca: 'Ao corretor, só bairro e nome do condomínio. Rua, número, bloco e apartamento vêm da equipe depois da visita confirmada.',
        palavras: ['endereço', 'localização', 'rua', 'bloco', 'apartamento'] },
      { titulo: 'Pet: perguntar o porte, nunca recusar de cara',
        faca: 'Quem decide é o dono. Responder "depende do proprietário; qual é o porte?" e levar a resposta. Porte pequeno costuma passar.',
        exemplo: 'Tel: "ela não aceita pet, mas qual é o porte? podemos tentar."',
        palavras: ['pet', 'cachorro', 'gato', 'animal', 'porte'] },
      { titulo: 'Mobília: o que o dono diz vale mais que a foto',
        faca: 'Mobiliado é mobiliado, semi é com modulados e ar. Na dúvida, perguntar ao dono o que fica. Nunca dizer "semi" e depois "mobiliado" na mesma conversa.',
        exemplo: 'Tel: "o proprietário só aluga todo mobiliado" / "vem com modulados e ar" / "só armário na cozinha, sem ar".',
        palavras: ['mobília', 'mobiliado', 'semi', 'modulados', 'ar'] },
      { titulo: 'Taxa de condomínio: valor e o que entra',
        faca: 'Dar o número e dizer o que está incluso e o que é à parte (água, gás, energia, IPTU). O que não se sabe, não afirmar.',
        exemplo: '"O aluguel é R$ 3.200, com água, gás e condomínio inclusos. A energia é à parte."',
        por: '"Gás incluso" e depois "é botija" desmentiu a Nay na frente do cliente.',
        palavras: ['taxa', 'condomínio', 'IPTU', 'água', 'gás', 'energia', 'incluso'] },
      { titulo: 'Valor: visita antes da proposta',
        quando: 'O corretor pede desconto antes de o cliente ver o imóvel.',
        faca: 'Puxar para a visita; se gostar, a gente leva a proposta ao dono. Depois da visita, devolver o piso do dono com número.',
        exemplo: 'Tel: "vamos levar ele para visitar; caso o cliente se interesse a gente faz a proposta, creio que conseguimos."',
        palavras: ['desconto', 'negociar', 'proposta', 'menor valor', 'margem'] },
      { titulo: 'Garantia: caução, não fiador',
        faca: 'Caução (em geral 2 aluguéis). Parcelar é decisão do dono, e é a primeira concessão a oferecer, antes de baixar o aluguel. Contrato mínimo de 12 meses.',
        exemplo: '"O proprietário aceita parcelar a caução; o aluguel de R$ 1.900 ele mantém."',
        palavras: ['caução', 'fiador', 'garantia', 'parcelar', 'contrato', 'prazo', '12 meses'] },
      { titulo: 'Análise do locatário: renda de 3x e nome limpo',
        faca: 'Avisar cedo: renda de pelo menos 3 vezes o aluguel, sem restrição que comprometa. Pedir o check-list completo de uma vez. A análise é do locatário, com documentos atuais.',
        por: 'Exigência que aparece aos poucos (holerite de 2025, renda mínima no meio da conversa) foi lida como surpresa e travou fechamentos.',
        palavras: ['renda', 'análise', 'documentos', 'check-list', 'restrição', 'SPC', 'serasa'] },
      { titulo: 'Visita: regras fixas',
        faca: 'Sem visita à noite. Pedido com menos de 3 horas vai ao Tel. Pedir nome e CPF de quem vai, para a portaria, avisando o porquê. O acompanhante só é chamado depois do sim do proprietário.',
        palavras: ['visita', 'horário', 'noite', 'portaria', 'CPF', 'acompanhante', 'Diego'] },
      { titulo: 'Disponibilidade: confirmar antes de prometer',
        faca: 'Imóvel com dúvida de status, inquilino saindo ou dono que demora: confirmar com o dono antes de oferecer horário. Imóvel que só fica livre em dezembro não serve para quem quer "imediato".',
        palavras: ['disponível', 'alugado', 'vendido', 'livre', 'desocupado', 'inquilino'] },
      { titulo: 'Quem fala com o dono é a Rayssa',
        faca: 'A Nay só faz a 1ª solicitação de visita e tira dúvida pontual. Negociação, fechamento e conversa com proprietário são da Rayssa.',
        palavras: ['proprietário', 'dono', 'Rayssa'] },
      { titulo: 'Não sabe? Diga e volte com a resposta',
        faca: '"Essa eu vou confirmar com o proprietário e te respondo por aqui." Depois voltar citando a pergunta e a fonte ("O proprietário confirmou que..."). Se o dono não responde, avisar o corretor em vez de deixar no vácuo.',
        palavras: ['vou confirmar', 'não sei', 'dúvida', 'resposta'] },
      { titulo: 'Jeito de falar',
        faca: 'Primeiro nome, nunca sigla. Curto, português de gente, sem jogar culpa no dono ("essa proprietária foi..." nunca). A Nay é uma só.',
        palavras: ['tom', 'nome', 'voz', 'educação'] },
    ],
  },
  {
    id: 'o-que-converte', titulo: 'O que vira visita',
    resumo: 'O que se repetiu nas conversas que viraram visita e fechamento.',
    regras: [
      { titulo: 'Card, fotos e horário na mesma resposta',
        faca: 'Card e fotos em 1 a 3 minutos e, colado neles, "qual dia e horário fica bom?". O corretor responde com dia e hora.',
        por: 'É a abertura de ~22 das 30 conversas do último lote que viraram visita.',
        palavras: ['velocidade', 'card', 'fotos', 'horário'] },
      { titulo: 'Confirmação em bloco',
        quando: 'O corretor deu dia e hora.',
        faca: 'Mandar "Só para confirmar a solicitação de visita: código, data, horário". Ele responde "sim" e a visita fica anotada. Conferir a data e a hora antes de enviar.',
        por: 'Fechou visita em segundos em ~25 conversas. Bloco com hora errada ("14h49", dia trocado) obrigou a refazer.',
        palavras: ['confirmação', 'visita', 'agendar'] },
      { titulo: 'Poucas opções, perto do teto',
        faca: '2 ou 3 imóveis bem escolhidos. 4 a 6 cards seguidos quase nunca viraram visita: o corretor acaba escolhendo um só.',
        exemplo: 'Venda até 400 mil no Parque 10: Plaza 300 mil, Estilo Golf 389 mil, Parque dos Ingleses 400 mil → 2 visitas marcadas.',
        palavras: ['opções', 'quantos', 'lista', 'muitos'] },
      { titulo: 'Alugou? Ofereça o parecido na hora',
        faca: '"Esse não está mais disponível. Quer que eu procure outro parecido?" e mandar o parecido (mesmo bairro, valor e tipo).',
        exemplo: 'Casa alugada → a Nay trouxe outra casa no mesmo perfil; visita marcada em 20 minutos, para o mesmo dia.',
        palavras: ['alugado', 'parecido', 'alternativa', 'substituto'] },
      { titulo: 'Juntar visitas do mesmo bairro',
        faca: 'Dois imóveis próximos no mesmo passeio, com horários colados (13h20 num, 14h no outro).',
        por: 'Park Golf + Estilo Golf e Kopenhagen + Plaza: os pares que mais fecharam.',
        palavras: ['duas visitas', 'agrupar', 'mesmo dia'] },
      { titulo: 'Horário do dono como contraproposta',
        faca: 'Em vez de "não dá", levar o horário que o dono pode: "o proprietário não consegue às 10h, mas sugeriu 11h. Funciona?".',
        palavras: ['horário', 'proprietário', 'remarcar'] },
      { titulo: 'Cliente na porta: resposta em minutos',
        quando: 'O corretor diz "hoje", "agora" ou "já estamos aqui".',
        faca: 'Tratar como urgente: confirmar dono e chave na hora; se não der, avisar logo e propor o próximo horário. Mais de 3 horas até a visita vai ao Tel.',
        por: 'Cliente esperando 47 a 55 minutos sem retorno foi embora ("não consegue mais esperar").',
        palavras: ['urgente', 'hoje', 'agora', 'pressa'] },
      { titulo: 'Retomar quem sumiu',
        faca: 'No dia seguinte: "seu cliente gostou? quer ver outro parecido?". Quem disse "vou mandar ao cliente" e sumiu (9 dos 70 perdidos) estava interessado.',
        exemplo: 'Tel: "seu cliente, ou outro cliente seu, também está precisando de imóvel para venda?" → nova busca.',
        palavras: ['follow-up', 'retomar', 'sumiu', 'silêncio'] },
      { titulo: 'Sincero sobre o defeito',
        faca: 'Dizer o limite antes da visita (escada, só carta de quitação, dono que falha). A confiança segura o corretor.',
        exemplo: '"Só temos a carta de quitação: o valor para financiar é 390 mil, à vista 370 mil." → visita realizada.',
        palavras: ['honestidade', 'defeito', 'financiamento'] },
    ],
  },
  {
    id: 'preferencias', titulo: 'O que o cliente quer sem dizer',
    resumo: 'Preferências que aparecem no meio da conversa. Respeitar = mais visita. Na dúvida, uma pergunta resolve.',
    regras: [
      { titulo: 'Pediu condomínio novo → só prédio novo',
        quando: 'Ele fala em "novo", "moderno", "recém-entregue", ou recusou um imóvel por ser antigo.',
        faca: 'Dar preferência a prédio entregue de 2018 para cá (Park Golf, Jardim das Cerejeiras, Mirante das Flores). Não insistir em prédio antigo, mesmo dentro do valor.',
        exemplo: '"Tá bonito e bem cuidado, mas prefiro prédio mais novo" → visitou o Cerejeiras (2020) e o Park Golf (2026) no mesmo dia.',
        por: 'Prédio novo é 3,5% do catálogo e 10% das visitas (2,9x). Casa "muito antiga" foi o motivo de 2 desistências.',
        palavras: ['novo', 'moderno', 'antigo', 'recém', 'entregue', 'condomínio novo', 'prédio novo'] },
      { titulo: 'Mobília exata',
        faca: 'Quem pede mobiliado quer mobiliado (nunca mande semi). Quem pede "só modulados e ar" não quer mobiliado. Há também quem quer "sem nada, só as lâmpadas".',
        por: 'Mobiliado é 4,5x e semi 3x nas visitas. Mobília errada foi motivo de recusa em 6 conversas.',
        palavras: ['mobiliado', 'semi', 'modulados', 'sem mobília'] },
      { titulo: 'Elevador e andar pesam mais que o bairro',
        faca: 'Quem tem idoso, criança pequena ou mudança grande pergunta escada e elevador. Mandar já com "andar baixo, com elevador" ou "3 lances de escada" no texto. Térreo e garden são pedidos à parte.',
        exemplo: '"O importante é o elevador": a cliente saiu do bairro que queria para ter elevador.',
        palavras: ['elevador', 'escada', 'térreo', 'garden', 'andar'] },
      { titulo: 'Gerador no prédio',
        faca: 'Para quem pergunta de gerador, dizer quais têm (elevador com gerador). "Nesse valor nenhum tem gerador 100%" + a melhor alternativa.',
        palavras: ['gerador', 'energia', 'queda de luz'] },
      { titulo: 'Perto da vida dele',
        faca: 'Perguntar onde trabalha ou mora a família quando o bairro é amplo. "Perto do Manauara", "trabalha na Djalma", "a mãe mora no Efigênio Sales" decidem mais que o bairro.',
        palavras: ['perto', 'trabalho', 'região', 'longe'] },
      { titulo: 'Casa: térrea, quintal, piscina, condomínio ou rua',
        faca: 'Em pedido de casa, confirmar: térrea? quintal ou piscina? condomínio fechado ou rua pública? Cada um é um cliente diferente.',
        palavras: ['casa', 'térrea', 'quintal', 'piscina', 'rua pública', 'condomínio fechado'] },
      { titulo: 'Prazo de mudança',
        faca: 'Perguntar "para quando?". Imóvel livre só em dezembro não serve para quem está "desesperado, vendendo a casa". Quem chega dia 10 volta a falar perto do dia 10.',
        palavras: ['prazo', 'mudança', 'quando', 'imediato', 'urgente'] },
      { titulo: 'Quem paga e como',
        faca: 'Empresa pagando o aluguel (teto de 2.800 a 3.000, contrato PJ, extrato), FGTS ou financiamento (Caixa, Itaú, Inter): perguntar cedo e só mandar imóvel que aceita aquilo.',
        palavras: ['financiamento', 'FGTS', 'empresa', 'PJ', 'à vista', 'Caixa'] },
      { titulo: 'Metragem e vagas',
        faca: 'Quando ele diz "acima de 60 m²" ou "2 vagas", tratar como filtro firme.',
        palavras: ['metragem', 'm²', 'vagas', 'garagem'] },
    ],
  },
  {
    id: 'perguntas', titulo: 'Perguntas que sempre vêm',
    resumo: 'As perguntas mais repetidas dos corretores e a resposta que funcionou. Ter a resposta na hora segura a conversa.',
    regras: [
      { titulo: '"Ainda está disponível?"', faca: 'Responder em menos de 1 minuto: "Sim, está disponível" + nome, quartos e valor + "quer as fotos?".', palavras: ['disponível'] },
      { titulo: '"Qual o andar? Tem elevador?"', faca: 'Faixa (baixo/médio/alto) ou lances de escada; o número se insistir e tiver elevador.', palavras: ['andar', 'elevador'] },
      { titulo: '"Quanto é o condomínio? O que inclui?"', faca: 'O valor e o que entra (água, gás, IPTU). IPTU com o ano: "R$ 429,67 (valor de 2025)".', palavras: ['condomínio', 'IPTU', 'taxa'] },
      { titulo: '"Aceita pet?"', faca: '"Depende do proprietário. Qual é o porte?" e voltar com a resposta dele.', palavras: ['pet'] },
      { titulo: '"Fica como nas fotos? O que fica de móvel?"', faca: 'O que a ficha diz; o que não diz, perguntar ao dono, junto com as fotos dos quartos.', palavras: ['mobília', 'fotos', 'quartos'] },
      { titulo: '"Tem margem? Qual o menor valor?"', faca: 'Antes da visita: "leva o cliente para ver e a gente leva a proposta". Depois: o piso do dono, com número.', palavras: ['negociar', 'margem', 'desconto'] },
      { titulo: '"Caução ou fiador? Parcela?"', faca: 'Caução (em geral 2 aluguéis); parcelar depende do dono e costuma sair. Contrato de 12 meses.', palavras: ['caução', 'fiador'] },
      { titulo: '"Quais documentos?"', faca: 'O check-list completo de uma vez. PJ: IR com recibo ou 6 meses de extrato. Renda de 3x o aluguel.', palavras: ['documentos', 'check-list'] },
      { titulo: '"Quem abre? Como entra?"', faca: 'Quem acompanha (o Diego), se a chave está conosco ou é fechadura, e o nome e CPF do visitante para a portaria.', palavras: ['chave', 'acompanhante', 'portaria'] },
      { titulo: '"Vocês fazem parceria?"', faca: '"Sim, aceitamos parceria em todos os nossos imóveis." Honorários: a regra do Tel; dúvida vai a ele.', palavras: ['parceria', 'comissão', 'honorários'] },
    ],
  },
  {
    id: 'o-que-perde', titulo: 'O que perde o cliente',
    resumo: 'Dos 70 corretores que pediram e nunca visitaram, 46 eram pedidos reais. Os motivos, do maior para o menor.',
    regras: [
      { titulo: 'Não tínhamos o perfil (13)',
        faca: 'Dizer uma vez, com a alternativa mais próxima, e anotar a falta para a captação. Nunca repetir "não tenho" em loop.',
        por: 'O que mais faltou: casa de locação com quintal ou piscina, 3 quartos até 2,3 a 3 mil, sala comercial, lote em Alphaville, garden na Zona Leste.',
        palavras: ['não tenho', 'sem perfil', 'falta', 'captação'] },
      { titulo: 'Oferta fora do pedido (11)',
        faca: 'Conferir antes de mandar: venda ou locação, teto, quartos e tipo. 9 cards de venda para quem queria alugar acabam a conversa.',
        palavras: ['fora do pedido', 'errado', 'venda', 'locação', 'quartos'] },
      { titulo: 'Corretor sumiu depois de "vou mandar ao cliente" (9)',
        faca: 'Retomar no dia seguinte com uma pergunta curta. É interesse, não recusa.',
        palavras: ['sumiu', 'silêncio', 'retomar'] },
      { titulo: 'Pergunta sem resposta (7)',
        faca: 'Nenhuma pergunta fica sem retorno. "Me envia as fotos" 6 vezes sem resposta, ou 2 dias sem dizer o que o Park Golf tem, perdem o corretor.',
        palavras: ['sem resposta', 'vácuo', 'ignorado'] },
      { titulo: 'Demora de horas (6)',
        faca: 'A pergunta decisiva (andar, caução, taxa) responde em minutos. Andar respondido em 7 horas e caução em 21 horas perderam clientes prontos para visitar.',
        palavras: ['demora', 'lento', 'horas'] },
      { titulo: 'Repetir o que já foi enviado',
        faca: 'Nunca reenviar o mesmo card nem responder "já te mandei hoje" quando ele pergunta outra coisa. Se ele pede foto dos quartos, mandar as dos quartos.',
        por: '"Vc virou um robô? Já enviou essas fotos 4x."',
        palavras: ['repetido', 'já enviei', 'robô'] },
      { titulo: 'Informação errada ou que muda',
        faca: 'Valor do grupo igual ao do cadastro; mobília, gás e área externa conferidos antes. Errou? Corrigir na hora e atualizar a ficha.',
        palavras: ['erro', 'contradição', 'cadastro', 'grupo', 'valor diferente'] },
      { titulo: 'Dono que trava a visita',
        faca: 'Imóvel com dono difícil (sem chave, viajando, desmarca) entra com aviso e com um plano B no mesmo bairro. Três falhas: o Tel decide se o imóvel continua sendo oferecido.',
        por: 'O Kopenhagen, o mais visitado, perdeu visitas por falta de chave; o Smile Flores perdeu as 3.',
        palavras: ['proprietário', 'chave', 'desmarcou', 'dono difícil'] },
    ],
  },
  {
    id: 'mais-visitados', titulo: 'Imóveis mais visitados',
    resumo: 'Os que mais tiveram visita e o que eles têm em comum. Use como régua para escolher o que oferecer primeiro.',
    regras: [
      { titulo: 'O perfil que mais visita',
        faca: 'Apartamento de 2 ou 3 quartos, mobiliado ou com modulados e ar, em condomínio com lazer, no Parque 10, em Flores ou em Ponta Negra. Aluguel de 2,5 a 6 mil ou venda até 300 mil.',
        por: 'Aluguel de 4 a 6 mil é 5% do catálogo e 25% das visitas (4,7x). Dois quartos: 1,6x.',
        palavras: ['perfil', 'parque 10', 'flores', 'ponta negra', 'dois quartos'] },
      { titulo: 'Venda de entrada vende',
        faca: 'Para quem financia, oferecer primeiro os de até 300 mil com FGTS (Kopenhagen, Plaza Del Rey, Villa Suíça). São os que mais fecharam venda.',
        palavras: ['venda', 'financiamento', 'FGTS', 'entrada'] },
      { titulo: 'O imóvel campeão vem pedido pelo código',
        faca: 'Os mais visitados chegaram quase sempre pelo card no grupo: o corretor já vem com o código. Manter o card do grupo igual ao cadastro (valor, mobília) e responder na hora.',
        palavras: ['grupo', 'código', 'card'] },
      { titulo: 'Visitado muito e fechado pouco = dono',
        faca: 'Smile Flores (6 visitas, 0), Tapajós (6, 0) e Rio Amazonas (5, 0) perderam pelo lado do dono: chave, inquilino ou horário. Confirmar dono e chave antes de prometer o horário.',
        palavras: ['dono', 'chave', 'inquilino'] },
    ],
  },
  {
    id: 'leads', titulo: 'Cliente final (Leads)',
    resumo: 'WhatsApp Leads (8595): OLX, orgânico e Chaves na Mão. Das 96 conversas, ~50 eram de gente buscando imóvel; 13 viraram visita ou fechamento.',
    regras: [
      { titulo: 'Veio de um anúncio: responda e ofereça a visita',
        faca: 'Na 1ª mensagem, responder o que ele perguntou sobre aquele imóvel e já perguntar "qual dia e horário o senhor gostaria de visitar?". Os filtros ficam para depois.',
        por: '8 das 13 visitas nasceram assim. Quem teve de responder mais de 4 perguntas antes do 1º imóvel não chegou à visita.',
        palavras: ['anúncio', 'OLX', 'abertura', 'primeira mensagem'] },
      { titulo: 'Fato concreto e custo total',
        faca: 'Dizer tudo de uma vez: mobília, quartos, valor com o que inclui e a garantia. Mostrar a conta: "R$ 3.200 + R$ 416 de condomínio = R$ 3.616".',
        exemplo: '"Mobiliado, 3 quartos, R$ 5.000 com água, gás e condomínio, garantia caução."',
        palavras: ['valor total', 'custo', 'condomínio'] },
      { titulo: '"Vou confirmar" tem prazo',
        faca: 'Voltar no mesmo dia, com a resposta ou com "ainda estou esperando o proprietário". Promessa de foto ou de andar sem retorno foi o motivo nº 1 de perda (15 conversas).',
        exemplo: 'A cliente disse que as fotos dos roupeiros eram "fator determinante"; foram prometidas 4 vezes em 8 dias e nunca chegaram.',
        palavras: ['vou confirmar', 'promessa', 'demora', 'retorno'] },
      { titulo: 'Resposta do Tel vai traduzida ao cliente',
        faca: 'Nunca repassar a frase interna crua ("Ela passa a atender", "Ah sim"). Reescrever para o cliente, e nada de honorários, comissão ou assunto interno.',
        palavras: ['tel', 'resposta interna', 'honorários'] },
      { titulo: 'Sem código? Ache pelo nome ou pelo link',
        faca: 'Cliente de portal não sabe o código. Achar pelo anúncio, pelo nome do condomínio ou pelo link; perguntar o código trava a visita.',
        palavras: ['código', 'link', 'anúncio', 'condomínio'] },
      { titulo: 'Respeitar teto, região e condomínio citado',
        faca: 'O que ele citou é filtro: "máximo 7" é 7, "Parque 10 e Flores" não é Lago Azul, condomínio pelo nome vem antes de qualquer outro. 2 ou 3 cartões, não 10.',
        por: '11 conversas receberam imóvel fora do teto, da região ou do tipo, e o cliente respondeu "longe", "passa do valor" ou só "não".',
        palavras: ['teto', 'região', 'longe', 'condomínio', 'muitos cartões'] },
      { titulo: 'Quem decide é o cônjuge',
        quando: '"Vou falar com meu esposo/esposa."',
        faca: 'Mandar um resumo fácil de encaminhar (fotos, valor total, bairro) e oferecer a visita para os dois. Retomar em 1 ou 2 dias.',
        palavras: ['esposo', 'esposa', 'família', 'decidir'] },
      { titulo: 'Visita: dizer quem vai receber',
        faca: 'Na confirmação, o nome de quem acompanha e onde encontrar. Cliente sem saber "com quem eu vou" fica inseguro.',
        palavras: ['acompanhante', 'visita', 'confirmação'] },
      { titulo: 'Reengajar quem parou',
        faca: 'Depois de 7 a 10 dias, "Encontrei essa opção, caso ainda tenha interesse" com um imóvel no perfil.',
        por: 'Em 28/10 foi mandado a ~14 conversas paradas e ~6 responderam.',
        palavras: ['reengajar', 'parado', 'follow-up'] },
    ],
  },
  {
    id: 'fechamento', titulo: 'Da visita ao fechamento',
    resumo: 'O que aconteceu nos 7 dias antes de cada um dos 27 fechamentos.',
    regras: [
      { titulo: 'Depois da visita, perguntar e propor',
        faca: '"Como foi a visita? O cliente gostou?" Se gostou: "se ele já quer, podemos iniciar a minuta". Se veio proposta, levar ao dono e voltar com o piso.',
        exemplo: 'Proposta de 250 a 280 mil no Kopenhagen → "o menor valor é 265 mil" → fechou com sinal, FGTS e financiamento.',
        palavras: ['pós-visita', 'proposta', 'minuta'] },
      { titulo: 'Check-list no primeiro sinal',
        faca: 'Assim que o corretor diz "vai fechar", mandar o check-list completo de locatário e locador, e-mails dos dois lados e os dados do corretor parceiro (CRECI e PIX).',
        por: 'Com o check-list cedo, de aprovado a minuta levou 1 a 3 dias.',
        palavras: ['check-list', 'documentos', 'fechar'] },
      { titulo: 'Aprovação rápida e clara',
        faca: 'Comunicar em uma linha: "CLIENTE APROVADO, sem restrições, renda passa de 3x o valor". Restrição baixa: apresentar ao dono e deixar ele decidir.',
        palavras: ['aprovado', 'análise', 'restrição'] },
      { titulo: 'Flexibilizar a garantia antes do valor',
        faca: 'A primeira concessão é parcelar a caução (15 + 15 dias, 2 cauções em vez de 1 sem fiador), não baixar o aluguel.',
        palavras: ['caução', 'concessão', 'negociação'] },
      { titulo: 'Avisar o que depende do dono',
        faca: 'Antes de o corretor tirar aprovação no banco, deixar claro o que o dono ainda não autorizou (valor, prazo).',
        por: 'Um corretor aprovou 275 mil num imóvel de 230 mil achando que o dono já tinha concordado, e desistiu.',
        palavras: ['banco', 'aprovação', 'expectativa'] },
    ],
  },
]

/** A busca da página: título, quando, faça, exemplo, por quê e as palavras de cada regra. */
export function buscarNoGuia(termo: string): { secao: Secao; regras: Regra[] }[] {
  const tira = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()
  const t = tira(termo.trim())
  if (t.length < 2) return []
  return SECOES.map((secao) => ({
    secao,
    regras: secao.regras.filter((r) =>
      tira([r.titulo, r.quando, r.faca, r.exemplo, r.por, ...(r.palavras || [])].filter(Boolean).join(' ')).includes(t)),
  })).filter((x) => x.regras.length)
}
