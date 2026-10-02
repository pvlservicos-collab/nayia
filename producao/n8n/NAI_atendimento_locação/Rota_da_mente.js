// Devolve o MESMO item que o roteador montou, so trocando a rota: os nos
// de baixo leem campos dele.
const base = $('Rotear pelo cabeçalho').first().json;
const d = $('Decidir quem responde').first().json || {};
const at = d.atendente === 'secretaria' ? 'secretaria' : 'agente';
return [{ json: Object.assign({}, base, { rota: at, atendente: d.atendente }) }];
