/**
 * TUTORIAIS DO CRM (Pedro, 29/10/2026): "uma pasta no menu Mais, TUTORIAIS, tipo uma documentação, um campo em cima de
 * pesquisar e embaixo tutoriais rápidos das funções do CRM, e o cara pesquisa lá na barra de navegação no topo alguma
 * função e aparece ... com prints das funções, onde ir clicando, bem didático mas sem muitos textões".
 *
 * Cada passo é uma frase curta e um print (crm/public/tutoriais/<foto>.webp, tirados do CRM de verdade, com moldura
 * laranja onde clicar). Quando o print tem números, `itens` diz o que é cada número, na mesma ordem.
 * A tela é /tutoriais; a busca do alto (GlobalSearch) usa `buscarTutoriais` também.
 * Mudou uma tela? Troque o print e a frase aqui.
 */

export interface PassoTutorial {
  texto: string
  foto?: string
  /** o que é cada número laranja do print, na ordem */
  itens?: string[]
}

export interface Tutorial {
  id: string
  titulo: string
  resumo: string
  grupo: string
  /** a tela onde a função mora (o botão "Ir para lá") */
  onde?: string
  palavras: string[]
  passos: PassoTutorial[]
}

export const GRUPOS_DE_TUTORIAL = ['Conversas', 'A Nay', 'Imóveis', 'Clientes e visitas', 'OLX e portais', 'Equipe e números', 'Jeito da tela']

export const TUTORIAIS: Tutorial[] = [
  // ── Conversas ──
  {
    id: 'responder', grupo: 'Conversas', onde: '/chat/parceria',
    titulo: 'Responder uma conversa',
    resumo: 'Abrir o WhatsApp certo, a conversa e escrever.',
    palavras: ['whatsapp', 'mensagem', 'escrever', 'responder', 'parceria', 'leads', 'oficial', 'chat', 'conversa', 'enviar mensagem'],
    passos: [
      { texto: 'Escolha o WhatsApp no alto.', foto: 'responder-1', itens: ['Oficial', 'Parceria', 'Leads'] },
      { texto: 'Clique na conversa da lista.', foto: 'responder-2' },
      { texto: 'Escreva embaixo e aperte Enter.', foto: 'responder-3', itens: ['Caixa de mensagem', 'Microfone: grava áudio'] },
    ],
  },
  {
    id: 'contato-novo', grupo: 'Conversas',
    titulo: 'Falar com um número novo',
    resumo: 'Criar a conversa com quem ainda não está no CRM.',
    palavras: ['contato novo', 'número novo', 'criar conversa', 'iniciar conversa', 'novo contato', 'adicionar contato', 'chamar cliente', 'primeira mensagem'],
    passos: [
      { texto: 'Clique no botão da pessoa com +, no alto.', foto: 'contato-1' },
      { texto: 'Digite o número com DDD e clique em Criar conversa.', foto: 'contato-2', itens: ['Número com DDD', 'Cria a conversa e já abre'] },
      { texto: 'Ela nasce no WhatsApp da tela em que você está (fora das conversas, no Leads). O link embaixo troca o número.' },
    ],
  },
  {
    id: 'pesquisar', grupo: 'Conversas',
    titulo: 'Achar uma conversa',
    resumo: 'Pesquisar por nome ou número.',
    palavras: ['pesquisar', 'procurar', 'buscar', 'lupa', 'nome', 'número', 'telefone', 'achar conversa', 'buscar leads'],
    passos: [
      { texto: 'Clique na lupa, em cima da lista.', foto: 'busca-1' },
      { texto: 'Digite o nome ou o número.', foto: 'busca-2' },
      { texto: 'Ou use Buscar leads, no alto: procura em todos os números e mostra os tutoriais também.', foto: 'busca-3' },
    ],
  },
  {
    id: 'filtros', grupo: 'Conversas', onde: '/chat/parceria',
    titulo: 'Filtrar as conversas',
    resumo: 'Hoje, Essa semana e as abas de etapa.',
    palavras: ['hoje', 'essa semana', 'abas', 'filtro', 'filtrar', 'visitas', 'proprietários', 'fechamento', 'todos'],
    passos: [
      { texto: 'Em cima da lista:', foto: 'filtros-1', itens: ['Hoje / Essa semana: só as que se mexeram. Clique de novo para ver todas', 'Abas: cada etapa (Visitas, Proprietários, Fechamento...)'] },
    ],
  },
  {
    id: 'etiquetas', grupo: 'Conversas', onde: '/chat/parceria',
    titulo: 'Etiquetas e etapa do contato',
    resumo: 'Marcar, filtrar e mudar a etapa.',
    palavras: ['etiqueta', 'tag', 'prancheta', 'etapa', 'marcar contato', 'cor', 'classificar'],
    passos: [
      { texto: 'Clique na prancheta e marque uma etiqueta para filtrar. Em Editar, muda nome e cor.', foto: 'etiquetas-1' },
      { texto: 'No card do contato (à direita), escolha a etapa e clique em Salvar.', foto: 'etapa-1' },
    ],
  },
  {
    id: 'mensagem', grupo: 'Conversas',
    titulo: 'Responder, encaminhar ou fixar uma mensagem',
    resumo: 'Os botões que aparecem em cima da mensagem.',
    palavras: ['responder mensagem', 'citar', 'encaminhar', 'fixar', 'marcar mensagem', 'reply', 'apagar mensagem'],
    passos: [
      { texto: 'Passe o mouse em cima da mensagem.', foto: 'mensagem-1', itens: ['Fixar no alto da conversa', 'Responder citando', 'Encaminhar para outra conversa'] },
      { texto: 'Nas mensagens que você mandou, aparece também a lixeira para apagar.' },
    ],
  },
  {
    id: 'anexar', grupo: 'Conversas',
    titulo: 'Mandar foto, arquivo, áudio ou resposta rápida',
    resumo: 'Os botões da caixa de mensagem.',
    palavras: ['anexo', 'anexar', 'foto', 'vídeo', 'documento', 'pdf', 'arquivo', 'resposta rápida', 'emoji', 'áudio', 'gravar', 'atalho'],
    passos: [
      { texto: 'Embaixo da conversa:', foto: 'compositor-1', itens: ['Foto, vídeo, áudio ou documento', 'Respostas rápidas (ou digite / na caixa)', 'Emoji', 'Gravar áudio'] },
    ],
  },
  // ── A Nay ──
  {
    id: 'parar-nay', grupo: 'A Nay',
    titulo: 'Parar a Nay ou devolver a conversa a ela',
    resumo: 'Assumir um contato e depois soltar.',
    palavras: ['parar nay', 'pausar', 'pausar ia', 'robô', 'ia', 'assumir', 'voltar a atender', 'nay voltar', 'desligar nay'],
    passos: [
      { texto: 'Abra a conversa. No card da direita, em "A Nay nesta conversa":', foto: 'nay-1', itens: ['Parar Nay sempre: ela não responde mais essa pessoa até alguém soltar', 'Nay voltar a atender: ela volta e responde a última mensagem que ficou sem resposta'] },
    ],
  },
  {
    id: 'respostas-tel', grupo: 'A Nay', onde: '/respostas-tel',
    titulo: 'Responder as dúvidas da Nay (Respostas Tel)',
    resumo: 'O que a Nay não sabe e espera o Tel.',
    palavras: ['respostas tel', 'dúvida', 'duvidas', 'pergunta da nay', 'tinder', 'tel', 'responder dúvida'],
    passos: [
      { texto: 'Clique no botão roxo, no alto. O número é quantas esperam.', foto: 'respostas-1' },
      { texto: 'Ou no menu do seu nome.', foto: 'respostas-3' },
      { texto: 'Uma dúvida por vez:', foto: 'respostas-2', itens: ['Escreva a resposta', 'Enviar (ou arraste o cartão para a direita): vai ao cliente pela Nay', 'Pular (ou arraste para a esquerda)', 'Lixeira: descarta'] },
    ],
  },
  // ── Imóveis ──
  {
    id: 'enviar-imovel', grupo: 'Imóveis', onde: '/disparo',
    titulo: 'Enviar um imóvel',
    resumo: 'Mandar o card e as fotos para um número.',
    palavras: ['enviar imóvel', 'mandar imóvel', 'card', 'fotos', 'disparo', 'oferecer imóvel'],
    passos: [
      { texto: 'Clique em Enviar imóvel, no alto.', foto: 'enviar-1' },
      { texto: 'Preencha e envie:', foto: 'enviar-2', itens: ['Número de quem recebe', 'Por qual WhatsApp', 'Código, condomínio, bairro ou rua; marque o imóvel', 'Enviar'] },
      { texto: 'Imóvel de parceiro e indisponível não saem. As fotos do mesmo imóvel vão uma vez a cada 24 h para cada número.' },
    ],
  },
  {
    id: 'achar-imovel', grupo: 'Imóveis', onde: '/imoveis',
    titulo: 'Achar um imóvel',
    resumo: 'Busca, filtros, ver e editar.',
    palavras: ['imóveis', 'imovel', 'procurar imóvel', 'código', 'condomínio', 'filtro', 'ver', 'editar', 'ficha', 'acervo'],
    passos: [
      { texto: 'Na aba Imóveis:', foto: 'imoveis-1', itens: ['Código, condomínio, bairro, rua ou proprietário', 'Filtros: situação, tipo, quartos, bairro, valor'] },
      { texto: 'Na linha do imóvel:', foto: 'imoveis-2', itens: ['VER: a ficha', 'EDITAR: muda o cadastro'] },
    ],
  },
  {
    id: 'cadastrar-imovel', grupo: 'Imóveis', onde: '/imoveis',
    titulo: 'Cadastrar um imóvel',
    resumo: 'Cadastro completo ou rápido.',
    palavras: ['novo imóvel', 'cadastro', 'cadastrar', 'cadastro rápido', 'incluir imóvel'],
    passos: [
      { texto: 'Na aba Imóveis:', foto: 'imoveis-3', itens: ['NOVO IMÓVEL: o cadastro completo', 'CADASTRO RÁPIDO: o curto'] },
    ],
  },
  // ── Clientes e visitas ──
  {
    id: 'pipeline', grupo: 'Clientes e visitas', onde: '/pipeline',
    titulo: 'Pipeline',
    resumo: 'Os leads em colunas, por etapa.',
    palavras: ['pipeline', 'funil', 'kanban', 'etapa', 'card', 'coluna', 'mover lead', 'adicionar lead'],
    passos: [
      { texto: 'No alto do Pipeline:', foto: 'pipeline-1', itens: ['Qual número', 'Filtros: etapa, etiqueta e data', 'Adicionar lead'] },
      { texto: 'Arraste o card para outra coluna para mudar a etapa.', foto: 'pipeline-2', itens: ['O card', 'A coluna de destino'] },
    ],
  },
  {
    id: 'visitas', grupo: 'Clientes e visitas', onde: '/chat/parceria',
    titulo: 'Ver e agendar visitas',
    resumo: 'A agenda de todos os números.',
    palavras: ['visita', 'visitas', 'agenda', 'agendar', 'calendário', 'visitas agendadas', 'visita realizada', 'horário'],
    passos: [
      { texto: 'Nas conversas, clique em Visitas agendadas.', foto: 'visitas-1' },
      { texto: 'A Nay preenche as dela sozinha. Para agendar à mão:', foto: 'visitas-2', itens: ['Agendar visita', 'Procurar imóvel, código, corretor ou proprietário', 'Ver por mês, 5 dias, dia ou lista'] },
    ],
  },
  {
    id: 'fechamento', grupo: 'Clientes e visitas', onde: '/chat/parceria',
    titulo: 'Checklist do fechamento',
    resumo: 'Os dados do contrato de aluguel ou venda.',
    palavras: ['fechamento', 'contrato', 'checklist', 'aluguel', 'venda', 'documentos', 'modelos', 'locação'],
    passos: [
      { texto: 'Nas conversas, clique em Fechamento.', foto: 'fechamento-1', itens: ['Checklist ou Modelos (textos para copiar); Aluguel ou Venda', 'Escolha quem mandou os dados: o checklist se preenche sozinho'] },
    ],
  },
  // ── OLX e portais ──
  {
    id: 'buscar-olx', grupo: 'OLX e portais', onde: '/buscar-imovel-olx',
    titulo: 'Buscar imóvel na OLX para um cliente',
    resumo: 'À mão ou as buscas que a Nay faz sozinha.',
    palavras: ['buscar imóvel olx', 'busca', 'olx', 'procurar para cliente', 'buscas dos clientes', 'anúncios olx', 'pedido do cliente'],
    passos: [
      { texto: 'Mais › Buscar imóvel OLX.', foto: 'buscas-1', itens: ['Manual ou Automático (Nay)', 'Busca por lead: digite o nome ou número e os filtros se preenchem', 'Ou filtre à mão'] },
      { texto: 'Em Automático, as buscas da Nay:', foto: 'buscas-2', itens: ['Situação das buscas', 'Ver passos, Pausar ou Encerrar'] },
    ],
  },
  {
    id: 'chat-olx', grupo: 'OLX e portais', onde: '/chat/olx',
    titulo: 'Chat OLX',
    resumo: 'Responder quem chama nos anúncios da OLX.',
    palavras: ['olx', 'chat olx', 'anúncios', 'conta olx', 'proprietários', 'corretores'],
    passos: [
      { texto: 'No alto do Chat OLX:', foto: 'olx-1', itens: ['Conta proprietários', 'Conta corretores', 'Chat: o que você responde sai na OLX', 'Anúncios', 'Informações da conta'] },
    ],
  },
  {
    id: 'chaves-na-mao', grupo: 'OLX e portais', onde: '/chat/chavesnamao',
    titulo: 'Chaves na Mão',
    resumo: 'Os leads do portal.',
    palavras: ['chaves na mão', 'chaves', 'portal', 'leads do portal'],
    passos: [
      { texto: 'No alto do Chaves:', foto: 'chaves-1', itens: ['Chat: os leads que pediram contato', 'Anúncios', 'Informações'] },
      { texto: 'O portal não tem chat: a resposta vai pelo WhatsApp Leads.' },
    ],
  },
  // ── Equipe e números ──
  {
    id: 'grupos', grupo: 'Equipe e números', onde: '/chat/grupos',
    titulo: 'Grupos do WhatsApp',
    resumo: 'Mensagens, participantes e configurações.',
    palavras: ['grupos', 'grupo', 'grupo whatsapp', 'participantes', 'admin', 'disparo'],
    passos: [
      { texto: 'Mais › Grupos.', foto: 'mais-1' },
      { texto: 'Ache o grupo e clique nele.', foto: 'grupos-1', itens: ['Procurar grupo', 'Filtros: Sou admin, Disparo, Corretores'] },
      { texto: 'Editar nome, descrição e participantes só nos grupos em que a Parceria é admin.' },
    ],
  },
  {
    id: 'visitantes', grupo: 'Equipe e números', onde: '/visitantes',
    titulo: 'Visitantes',
    resumo: 'Quem já visitou imóvel com a gente.',
    palavras: ['visitantes', 'quem visitou', 'lista', 'csv', 'exportar', 'baixar lista'],
    passos: [
      { texto: 'Mais › Visitantes.', foto: 'visitantes-1', itens: ['Período', 'Corretores ou Clientes; procurar', 'Baixar a lista'] },
    ],
  },
  {
    id: 'corretores', grupo: 'Equipe e números', onde: '/corretores',
    titulo: 'Corretores',
    resumo: 'O que cada corretor parceiro fez.',
    palavras: ['corretores', 'corretor', 'ranking', 'métricas', 'creci', 'parceiros'],
    passos: [
      { texto: 'Mais › Corretores.', foto: 'corretores-1', itens: ['Período', 'Procurar por nome, CRECI ou número', 'Filtros'] },
    ],
  },
  // ── Jeito da tela ──
  {
    id: 'tela', grupo: 'Jeito da tela',
    titulo: 'Tamanho das conversas e modo escuro',
    resumo: 'Deixar a tela do seu jeito.',
    palavras: ['tamanho', 'zoom', 'letra', 'fonte', 'maior', 'menor', 'escuro', 'claro', 'tema', 'modo escuro'],
    passos: [
      { texto: 'No alto, à direita:', foto: 'tema-1', itens: ['− e +: tamanho das conversas', 'Sol / lua: claro ou escuro'] },
    ],
  },
  {
    id: 'tutoriais', grupo: 'Jeito da tela', onde: '/tutoriais',
    titulo: 'Achar um tutorial',
    resumo: 'Pelo menu ou pela busca do alto.',
    palavras: ['tutorial', 'tutoriais', 'ajuda', 'como fazer', 'documentação', 'manual'],
    passos: [
      { texto: 'Mais › Tutoriais.', foto: 'tutoriais-1' },
      { texto: 'Ou escreva em Buscar leads o que quer fazer: os tutoriais aparecem em cima.', foto: 'tutoriais-2' },
    ],
  },
]

const normal = (s: string) => s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').trim()

/** Os tutoriais que casam com o texto: título primeiro, depois palavras, resumo e passos. Todas as palavras têm de casar. */
export function buscarTutoriais(texto: string, limite = 50): Tutorial[] {
  const termos = normal(texto).split(/\s+/).filter((t) => t.length >= 2)
  if (!termos.length) return TUTORIAIS.slice(0, limite)
  const nota = (t: Tutorial) => {
    const titulo = normal(t.titulo)
    const palavras = normal(t.palavras.join(' | '))
    const resto = normal([t.resumo, t.grupo, ...t.passos.flatMap((p) => [p.texto, ...(p.itens || [])])].join(' | '))
    let n = 0
    for (const termo of termos) {
      if (titulo.includes(termo)) n += 3
      else if (palavras.includes(termo)) n += 2
      else if (resto.includes(termo)) n += 1
      else return 0
    }
    return n
  }
  return TUTORIAIS.map((t) => ({ t, n: nota(t) }))
    .filter((x) => x.n > 0)
    .sort((a, b) => b.n - a.n)
    .slice(0, limite)
    .map((x) => x.t)
}
