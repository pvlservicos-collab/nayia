// O JEV DEVOLVE NUMERO, nao prosa: uma probabilidade por pergunta.
// Aqui so se empacota; quem compara com os pisos e o banco, em
// `nai_decidir_com_jev` -- para o Tel poder mexer sem deploy.
//
// SE O JEV CAIR (o no tem onError), nao para nada: vale a reserva
// pelo proprio texto, e a conferencia do banco corrige por cima.
const j = $json || {};
const a = j.answers || {};
const tem = Object.keys(a).length > 0;

if (!tem) {
  const t = String(($('Montar pergunta ao Jev').first().json || {}).texto_lido || '')
    .toLowerCase();
  const deImovel = /(imovel|imóvel|apartamento|casa|aluguel|loca|venda|visita|foto|dispon|c[oó]digo|condom)/.test(t);
  return [{ json: { jev: {}, reserva: true,
                    atendente: deImovel ? 'imoveis' : 'secretaria' } }];
}

return [{ json: { jev: Object.assign({}, a, {
  modelo: j.model || null,
  custo: (j.usage && j.usage.cost) || null,
}), reserva: false } }];
