// Dados de demonstração usados na aba "Telas" do painel (?demo=1) — nada é gravado no aparelho
const now = Date.now();
const iso = (m) => new Date(now - m * 60000).toISOString();

export const DEMO_BOOT = {
  user: { id: 'demo', name: 'Pedro Henrique', email: 'vistoriador@vistto.app', role: 'vistoriador' },
  app_name: 'Vistto',
  company: { name: 'IMOB EASY', color: '#FF1F7D' },
  types: {
    entrada: { label: 'Aluguel - Entrada', short: 'Entrada' }, saida: { label: 'Aluguel - Saída', short: 'Saída' }, temporada: { label: 'Temporada', short: 'Temporada' },
    compra_venda: { label: 'Compra e Venda', short: 'Compra e Venda' }, periodica: { label: 'Vistoria Periódica', short: 'Periódica' }, recebimento: { label: 'Recebimento de Imóvel', short: 'Recebimento' },
  },
  conditions: { novo: { label: 'Novo', color: '#2563EB' }, bom: { label: 'Bom', color: '#16A34A' }, regular: { label: 'Regular', color: '#EAB308' }, mau: { label: 'Mau', color: '#DC2626' } },
  functioning: { funcionando: 'Funcionando', nao_funcionando: 'Não funcionando', nao_testado: 'Não testado' },
  vocab: {
    rooms: ['Sala', 'Cozinha', 'Quarto', 'Suíte', 'Banheiro', 'Lavabo', 'Área de Serviço', 'Varanda', 'Garagem', 'Corredor', 'Quintal', 'Escritório', 'Chaves', 'Closet'],
    customRooms: ['Varanda gourmet', 'Depósito'],
    items: ['Piso', 'Paredes', 'Teto', 'Porta', 'Janela', 'Lâmpada', 'Lustre', 'Ar condicionado', 'Painel de TV', 'Rack', 'Sofá', 'Armário', 'Pia', 'Torneira', 'Cooktop', 'Box', 'Vaso sanitário', 'Chuveiro'],
  },
  templates: [{ id: 't1', name: 'Apartamento padrão (2 quartos)', rooms: [] }],
  params: { photos_per_room: 50 },
};

export function demoState() {
  const m = (id, n, mins, extra = {}) => ({ id, inspection_id: 'demo', kind: 'photo', url: `/app/demo/p${n}.jpg`, taken_at: iso(mins), markers: [], uploaded: true, ...extra });
  const media = [
    m('m1', 4, 40), m('m2', 7, 39), m('m3', 5, 36), m('m4', 6, 35),
    m('m5', 0, 33, { markers: [{ x: 0.3, y: 0.8, r: 0.1 }] }), m('m6', 1, 32, { markers: [{ x: 0.8, y: 0.6, r: 0.1 }, { x: 0.86, y: 0.86, r: 0.07 }] }),
    m('m7', 3, 30, { markers: [{ x: 0.45, y: 0.55, r: 0.12 }] }), m('m8', 8, 20), m('m9', 10, 19),
    { id: 'a1', inspection_id: 'demo', kind: 'audio', url: '', taken_at: iso(31), transcript: 'Painel em MDF carvalho com a quina inferior lascada.', uploaded: true },
  ];
  const ins = {
    id: 'demo', type: 'entrada', created_at: iso(45), local_status: 'draft', step: 2, code: null,
    property: { type: 'Apartamento', identification: 'SMART TOWER ITAPORANGA - TORRE 2 - APTO 708', cep: '69037-000', street: 'Avenida Sérgio Milliet', number: '85', complement: 'Apto 708, Torre 2', district: 'Ponta Negra', city: 'Manaus', state: 'AM', purpose: 'Residencial', furnished: 'Semimobiliado', area: '64' },
    parties: { locatarios: [{ name: 'WANDERSON FABRICIO DA SILVA E SILVA', cpf: '014.663.502-70', email: 'wanderson@exemplo.com', phone: '' }], locadores: [{ name: 'ADRIANA DIAS DE OLIVEIRA', cpf: '853.303.702-30', email: 'adriana@exemplo.com' }], fiadores: [], testemunhas: [] },
    meters: { energia: { number: '7845120', reading: '04512', media: [] }, agua: { number: '', reading: '', media: [] }, gas: { number: '', reading: '', media: [] } },
    contract: { filename: 'Contrato_Locacao_Smart_Itaporanga_Apto708.pdf', engine: 'regras' },
    rooms: [
      { id: 'r1', name: 'Sala', done: true, notes: 'Piso porcelanato claro em bom estado.', media: ['m1', 'm2'], audios: ['a1'], items: [
        { id: 'i1', name: 'Lustre', condition: 'bom', media: [], ncs: [] },
        { id: 'i2', name: 'Painel de TV', condition: 'regular', notes: 'Painel em MDF carvalho com nicho branco.', media: ['m3', 'm4'], has_nc: true, ncs: [{ id: 'n1', title: 'Painel com avaria', description: 'Quina inferior lascada e furos aparentes.', media: ['m5', 'm6'] }] },
        { id: 'i3', name: 'Rack', condition: 'regular', media: [], has_nc: true, ncs: [{ id: 'n2', title: 'Rack esfarelado na base', description: 'MDF esfarelado por umidade.', media: ['m7'] }] },
        { id: 'i4', name: 'Ar condicionado', condition: 'bom', functioning: 'funcionando', quantity: 1, media: [], ncs: [] },
      ] },
      { id: 'r2', name: 'Varanda da sala', done: true, media: ['m8'], items: [{ id: 'i5', name: 'Condensadora de ar', condition: 'bom', functioning: 'funcionando', media: ['m9'], ncs: [] }] },
      { id: 'r3', name: 'Cozinha', done: false, media: [], items: [] },
      { id: 'r4', name: 'Quarto', done: false, media: [], items: [] },
    ],
    general_notes: '',
  };
  const sent = { id: 'demo2', type: 'saida', created_at: iso(60 * 30), local_status: 'sent', code: 12, server: { id: 'demo2', status: 'aprovada' }, property: { identification: 'ACQUARELLE - TORRE CIANO 1803' }, parties: {}, rooms: [{ id: 'x', name: 'Sala', media: [], items: [] }], meters: {} };
  return { inspections: [ins, sent], media, kv: { onboarded: true } };
}
