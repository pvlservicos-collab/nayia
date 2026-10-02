const r = $json;
if (!r || !r.codigo) return [{ json: { bloco: 'CODIGO NAO ENCONTRADO NA BASE' } }];
const n = v => (v == null ? 0 : Number(v));
const f = v => Number(v).toLocaleString('pt-BR', { maximumFractionDigits: 0 });
const MOB = {
  'mobiliado (moveis + cama + tudo)': 'mobiliado (móveis + cama + tudo)',
  'semi-mobiliado (moveis planejados + ar)': 'semi-mobiliado (móveis planejados + ar)',
  'so ar-condicionado': 'só ar-condicionado'
};
const apto = /apartamento|cobertura|flat/i.test(r.tipo || '');
const condo = r.condominio_nome && !/n[ãa]o identificado/i.test(r.condominio_nome) ? r.condominio_nome : null;
if (r.e_parceiro) {
  return [{ json: { lead_in: 'Encontrei:', bloco: '📍 ' + (condo || r.tipo) + '\n• esse imovel e de parceria, nao da imob easy.', qtd_fotos: 0, avisos: 'E DE PARCEIRO' } }];
}
const temTx = /condom/i.test(r.incluso_aluguel || '');
const L = [];
L.push('📍 ' + (condo || r.tipo));
if (r.bairro) L.push('• Bairro: ' + r.bairro);
if (apto && r.sol) L.push('• apto ' + String(r.sol).toLowerCase());
if (n(r.area_util)) L.push('• ' + f(r.area_util) + 'm2');
if (n(r.quartos)) L.push('• ' + r.quartos + ' quartos' + (n(r.suites) ? ' sendo ' + r.suites + ' suíte' : ''));
if (n(r.vagas_cobertas)) L.push('• ' + r.vagas_cobertas + ' vagas cobertas');
else if (n(r.vagas)) L.push('• ' + r.vagas + ' vagas');
if (apto && r.mobilia) L.push('• ' + (MOB[r.mobilia] || r.mobilia));
if (n(r.taxa_condominio) && !temTx) L.push('• taxa de condomínio: ' + f(r.taxa_condominio));
if (n(r.valor_venda)) L.push('valor: ' + f(r.valor_venda));
if (n(r.valor_aluguel)) L.push('locação: ' + f(r.valor_aluguel) + (temTx ? ' (incluso a TX)' : ''));
L.push('Código: ' + r.codigo);
const avisos = [];
if (!r.disponivel) avisos.push('NAO DISPONIVEL');
if (r.bloqueado) avisos.push('BLOQUEADO');
if (!Number(r.qtd_fotos)) avisos.push('SEM FOTOS');
return [{ json: { lead_in: 'Encontrei:', bloco: L.join('\n'), qtd_fotos: Number(r.qtd_fotos), avisos: avisos.join(' | ') || 'ok' } }]
