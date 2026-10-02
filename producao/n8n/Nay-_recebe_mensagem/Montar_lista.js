// >>> segundo numero do Tel (28/09)
const TELS_DO_TEL = ['[telefone …7316]', '[telefone …6408]'];
const _finalDoTel = (x) => String(x == null ? '' : x).replace(/\D/g, '').slice(-8);
const _FINAIS_DO_TEL = TELS_DO_TEL.map(_finalDoTel);
const ehTelDoTel = (x) => _FINAIS_DO_TEL.indexOf(_finalDoTel(x)) !== -1;
// <<< segundo numero do Tel
const f = $('Achar condominio').first().json;
const rows = $input.all().map(i => i.json).filter(r => r && r.codigo);
const n = v => (v == null ? 0 : Number(v));
const fmt = v => Number(v).toLocaleString('pt-BR', { maximumFractionDigits: 0 });
let lista = rows;
if (f.quartos) lista = lista.filter(r => n(r.quartos) === f.quartos);
if (f.modo === 1) lista = lista.filter(r => n(r.valor_aluguel) > 0);
if (f.modo === 2) lista = lista.filter(r => n(r.valor_venda) > 0);
const total = lista.length;
const MAX = 8;
const mostra = lista.slice(0, MAX);
let msg;
if (total === 0) {
  msg = 'no ' + f.condominio + ' não tenho nada disponível com esse perfil no momento';
} else {
  const linhas = mostra.map(r => {
    const preco = f.modo === 1 ? (n(r.valor_aluguel) ? 'locação ' + fmt(r.valor_aluguel) : 'consultar') : (n(r.valor_venda) ? fmt(r.valor_venda) : (n(r.valor_aluguel) ? 'locação ' + fmt(r.valor_aluguel) : 'consultar'));
    const q = n(r.quartos) ? r.quartos + ' quartos' : (r.tipo || '');
    const a = n(r.area_util) ? ' — ' + fmt(r.area_util) + 'm2' : '';
    return '• ' + r.codigo + ' — ' + q + a + ' — ' + preco;
  });
  const cab = 'no ' + f.condominio + ' tenho ' + total + (total === 1 ? ' opção:' : ' opções:');
  const rodape = total > MAX ? '\n\nesses são os ' + MAX + ' primeiros. me diz quantos quartos ou o valor que eu filtro' : '\n\nme manda o código do que interessar que eu mando as fotos';
  msg = cab + '\n' + linhas.join('\n') + rodape;
}
// TESTE virou pergunta: ver ehTelDoTel.
const tel = $('Juntar mensagens').first().json.telefone;
if (!ehTelDoTel(tel)) return [];
return [{ json: { corpo: { phone: tel, message: msg } } }];
