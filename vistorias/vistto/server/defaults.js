// Valores padrão do sistema (podem ser editados em Configurações > Parâmetros)

const APP_NAME = process.env.APP_NAME || 'Vistto';

const TYPES = {
  entrada: { label: 'Aluguel - Entrada', title: 'TERMO DE VISTORIA DE ENTRADA', short: 'Entrada' },
  saida: { label: 'Aluguel - Saída', title: 'TERMO DE VISTORIA DE SAÍDA', short: 'Saída' },
  temporada: { label: 'Temporada', title: 'TERMO DE VISTORIA - TEMPORADA', short: 'Temporada' },
  compra_venda: { label: 'Compra e Venda', title: 'TERMO DE VISTORIA - COMPRA E VENDA', short: 'Compra e Venda' },
  periodica: { label: 'Vistoria Periódica', title: 'TERMO DE VISTORIA PERIÓDICA', short: 'Periódica' },
  recebimento: { label: 'Recebimento de Imóvel', title: 'TERMO DE RECEBIMENTO DE IMÓVEL', short: 'Recebimento' },
};

const STATUSES = {
  rascunho: { label: 'Em andamento', color: '#94A3B8' },
  enviada: { label: 'Recebida', color: '#38BDF8' },
  em_revisao: { label: 'Em revisão', color: '#F59E0B' },
  aprovada: { label: 'Aprovada', color: '#22C55E' },
  em_assinatura: { label: 'Em assinatura', color: '#A855F7' },
  assinada: { label: 'Assinada', color: '#10B981' },
  cancelada: { label: 'Cancelada', color: '#EF4444' },
};

const CONDITIONS = {
  novo: { label: 'Novo', long: 'Novo', color: '#2563EB' },
  bom: { label: 'Bom', long: 'Em bom estado', color: '#16A34A' },
  regular: { label: 'Regular', long: 'Em estado regular', color: '#EAB308' },
  mau: { label: 'Mau', long: 'Em mau estado', color: '#DC2626' },
};

const FUNCTIONING = {
  funcionando: 'Funcionando',
  nao_funcionando: 'Não funcionando',
  nao_testado: 'Não testado',
};

const ROOM_NAMES = ['Sala', 'Cozinha', 'Quarto', 'Suíte', 'Banheiro', 'Lavabo', 'Área de Serviço', 'Varanda', 'Garagem', 'Corredor', 'Quintal', 'Escritório', 'Chaves', 'Hall de entrada', 'Closet', 'Varanda da sala', 'Banheiro social', 'Banheiro da suíte'];
const ITEM_NAMES = ['Piso', 'Paredes', 'Teto', 'Pintura', 'Porta', 'Janela', 'Lâmpada', 'Lustre', 'Tomadas', 'Interruptores', 'Ar condicionado', 'Condensadora de ar', 'Painel de TV', 'Rack', 'Sofá', 'Armário', 'Armário de baixo da pia', 'Pia', 'Torneira', 'Fogão', 'Cooktop', 'Forno', 'Geladeira', 'Micro-ondas', 'Coifa', 'Cama', 'Guarda-roupa', 'Espelho', 'Box', 'Vaso sanitário', 'Chuveiro', 'Gabinete', 'Varal de roupa', 'Cortina', 'Persiana', 'Rodapé', 'Fechadura', 'Interfone', 'Controle remoto', 'Chave'];

const COMPANY = {
  name: 'IMOB EASY',
  legal_name: 'T A SOBREIRA IMOBILIÁRIA',
  cnpj: '33.597.560/0001-24',
  creci: '482',
  address: 'RUA CALDAS BARBOSA - 05 - MANAUS / AM',
  phones: ['(92) 98492-0974', '(92) 98595-6408'],
  email: 'admdeimoveis@imobeasy.com',
  site: 'www.imobeasy.com',
  logo: '',
  color: '#FF1F7D',
};

const TEXTS = {
  intro: 'As informações constantes nesse relatório, trazem uma descrição fiel do atual estado do imóvel vistoriado. Além das informações escritas, as fotos anexas servem como provas da vistoria realizada e da condição do imóvel. Certifique-se de ter recebido as fotos, se porventura não tenha recebido, faça a solicitação.',
  paint: [
    'Pintura NOVA: Trata-se de uma pintura recente, sem manchas, falhas ou marcas.',
    'Pintura em BOM estado de conservação: Pintura com pequenas manchas, falhas de acabamento, coberturas, recortes e uso.',
    'Pintura em estado REGULAR: Pintura com pequenas manchas, falhas de acabamento, coberturas, recortes, furos, falhas e descascamentos.',
  ].join('\n'),
  cleaning: [
    'Imóvel limpo: Trata-se do imóvel inteiramente faxinado recentemente, sem poeiras ou quaisquer vestígios de sujeira.',
    'Imóvel com poeira superficial: Trata-se do imóvel que está fechado a algum tempo e possui poeira nos vidros e superfícies.',
    'Imóvel sujo: Trata-se do imóvel com poeira e sujeira em banheiros, rejuntes, lixos e resto de obras.',
  ].join('\n'),
  contest: [
    'Caso identifique divergências entre este relatório e o estado atual do imóvel, você poderá abrir contestação mediante os seguintes pré-requisitos:',
    '1) As contestações deverão ser enviadas através do QR CODE que aparece no final do termo da vistoria.',
    '2) Indicar os ambientes de acordo com a descrição do laudo.',
    '3) Indicar apenas os defeitos e contestações que não estejam descritos no laudo ou nas fotos, sem repetir o texto da vistoria.',
    '4) Ao anexar fotos, nomear as fotos de acordo com o ambiente ou nome do item. Se possível, enviar em arquivo compactado (zipado).',
    '5) Itens de manutenção devem enviados diretamente para a imobiliária, através de canal específico.',
    '6) Contestações de vistoria de saída devem ser enviadas diretamente para a imobiliária ou setor de rescisão da mesma.',
    '7) Enviar a contestação em um único chamado. Será considerado apenas o primeiro chamado, excluindo-se os demais.',
    'O retorno será através de email no prazo de 72horas. O locatário tem o prazo firmado no contrato de locação, a partir da data da assinatura deste laudo de vistoria, para se manifestar expressamente sobre a vistoria apresentada pelo Locador. Fluído esse prazo, sem manifestação expressa por parte do Locatário, subentende-se aceita a vistoria na sua integralidade.',
  ].join('\n'),
  observations: [
    'ATENÇÃO: Os azulejos e/ou cerâmicas que forem danificadas e/ou furados, deverão ser substituídos por outros idênticos. É sugerido ao (a) CLIENTE (A), para evitar transtornos futuros, NÃO realizar furos e, caso realmente seja necessário, que adquira antecipadamente as peças para reposição, sob pena de não mais encontra-las, ter que fazer a substituição geral.',
    'Cabe ao CLIENTE (A) e seus FIADORES a inteira responsabilidade por quais danos causados no imóvel no decorrer da locação, os quais serão apurados na vistoria final, devendo às suas expensas ser corrigidos, ficando ainda acertado que só será extinta a relação locatícia após concluídos os reparos necessários.',
    'Declaramos para os devidos fins que estamos cientes que se neste imóvel existir(em) aparelho(s) de eletrodomésticos não novos, caso venham a dar problema ou não estejam funcionando perfeitamente, o(a) LOCADOR(A) fica isento de repor qualquer tipo de aparelho para substituição do(s) mesmo(s), incluindo a despesa com descarte.',
    'Para o bom funcionamento e integridade da vida útil dos aparelhos de ar condicionado e aquecedor d´água, os mesmos deverão ser revisados e limpos a cada 12 meses (ar condicionado) e a cada 6 meses (aquecedor d´água), CASO TENHAM SIDO ENTREGUES FUNCIONANDO NO INÍCIO DA LOCAÇÃO.',
    'Nós, abaixo assinados, DECLARAMOS, para quaisquer fins de direito, estarmos plenamente de acordo com o presente e suas condições.',
  ].join('\n'),
};

const EMAILS = {
  initial: {
    subject: 'Vistoria de entrada — {{imovel}}',
    body: 'Olá, {{nome}}!\n\nA vistoria de entrada do imóvel {{imovel}} foi concluída e aprovada pela {{empresa}}.\n\nVocê pode consultar o laudo completo, com todas as fotos e inconformidades por cômodo, no link abaixo:\n{{link}}\n\nEm instantes você também receberá, por e-mail, o documento para assinatura digital (ClickSign).\n\nCaso identifique divergências, utilize o link de contestação disponível no final do laudo, dentro do prazo previsto no contrato.\n\nAtenciosamente,\n{{empresa}}',
  },
  final: {
    subject: 'Vistoria de saída — {{imovel}}',
    body: 'Olá, {{nome}}!\n\nA vistoria de saída do imóvel {{imovel}} foi concluída e aprovada pela {{empresa}}.\n\nO laudo completo, com o comparativo do estado do imóvel, fotos e a relação de avarias encontradas, está disponível em:\n{{link}}\n\nEm seguida você receberá o documento para assinatura digital (ClickSign).\n\nAtenciosamente,\n{{empresa}}',
  },
  signed: {
    subject: 'Laudo de vistoria assinado — {{imovel}}',
    body: 'Olá, {{nome}}!\n\nTodas as partes assinaram o laudo de vistoria do imóvel {{imovel}}. O documento assinado segue em anexo e permanece disponível em:\n{{link}}\n\nAtenciosamente,\n{{empresa}}',
  },
};

const PARAMS = {
  app_can_add_vocab: true,
  app_can_create_templates: true,
  photos_per_room: 50,
  require_selfie: false,
  contest_days: 7,
};

const DEFAULT_TEMPLATES = [
  { name: 'Apartamento padrão (2 quartos)', type: 'entrada', rooms: [
    { name: 'Sala', items: ['Piso', 'Paredes', 'Teto', 'Lâmpada', 'Ar condicionado', 'Painel de TV', 'Porta', 'Janela'] },
    { name: 'Varanda da sala', items: ['Piso', 'Lâmpada', 'Varal de roupa', 'Condensadora de ar'] },
    { name: 'Cozinha', items: ['Piso', 'Pia', 'Armário de baixo da pia', 'Torneira', 'Cooktop', 'Lâmpada'] },
    { name: 'Área de Serviço', items: ['Piso', 'Tanque', 'Torneira', 'Lâmpada'] },
    { name: 'Quarto', items: ['Piso', 'Paredes', 'Porta', 'Janela', 'Guarda-roupa', 'Lâmpada', 'Ar condicionado'] },
    { name: 'Suíte', items: ['Piso', 'Paredes', 'Porta', 'Janela', 'Guarda-roupa', 'Lâmpada', 'Ar condicionado'] },
    { name: 'Banheiro da suíte', items: ['Piso', 'Box', 'Vaso sanitário', 'Pia', 'Torneira', 'Chuveiro', 'Gabinete', 'Espelho'] },
    { name: 'Banheiro social', items: ['Piso', 'Box', 'Vaso sanitário', 'Pia', 'Torneira', 'Chuveiro', 'Gabinete', 'Espelho'] },
    { name: 'Chaves', items: ['Chave'] },
  ] },
  { name: 'Sala comercial', type: 'entrada', rooms: [
    { name: 'Recepção', items: ['Piso', 'Paredes', 'Porta', 'Lâmpada', 'Ar condicionado'] },
    { name: 'Sala', items: ['Piso', 'Paredes', 'Janela', 'Lâmpada', 'Ar condicionado', 'Persiana'] },
    { name: 'Banheiro', items: ['Piso', 'Vaso sanitário', 'Pia', 'Torneira', 'Espelho'] },
  ] },
];

module.exports = { APP_NAME, TYPES, STATUSES, CONDITIONS, FUNCTIONING, ROOM_NAMES, ITEM_NAMES, COMPANY, TEXTS, EMAILS, PARAMS, DEFAULT_TEMPLATES };
