// CHECK DUPLO, segunda metade: recalcula a chave do destino em JavaScript
// (implementacao independente da do banco) e compara com a que o banco
// mandou. Qualquer divergencia = nao envia.
function chave(p) {
  p = String(p || '');
  if (/@lid$/i.test(p)) { const d = p.replace(/\D/g, ''); return d ? 'lid:' + d : null; }
  let d = p.replace(/\D/g, '');
  if (!d) return null;
  if ((d.length === 10 || d.length === 11) && !d.startsWith('55')) d = '55' + d;
  if (/^55\d{10,11}$/.test(d)) return d.slice(0, 4) + d.slice(-8);
  return d;
}
return $input.all().map(it => {
  const j = it.json || {};
  let motivo = null;
  if (!j.id) motivo = 'sem_id';
  else if (!j.corpo || String(j.corpo.phone) !== String(j.telefone)) motivo = 'telefone_do_corpo_diferente';
  else if (!j.chave_esperada || chave(j.telefone) !== String(j.chave_esperada)) motivo = 'chave_nao_confere_js';
  else if (j.rota !== 'send-text' && j.rota !== 'send-image') motivo = 'rota_invalida';
  // A COLAGEM (12/09) mora no nosso site, nao no do catalogo: sem esta excecao
  // ela saia SEMPRE barrada aqui (foto_sem_codigo) -- visto no teste de 13/09.
  // So passa a colagem DAQUELE imovel: o arquivo tem o numero do codigo.
  else if (j.rota === 'send-image' && !(Number(j.codigo) > 0 && (/^https:\/\/imobeasy\.com\/system\/pictures\//.test(String(j.corpo.image || ''))
           // AS FOTOS DO SITE NOVO (01/10): imovel cadastrado por nos tem a foto em
           // imobeasy.online/fotos/<codigo>/ -- ou em fotos-captacao/<de onde
           // veio>/<codigo>/ (olx, whatsapp, crm). Eram 18 imoveis (5551, 9004...)
           // barrados aqui como foto_sem_codigo, queimando a trava de 24 h sem
           // mandar nada. Aqui o CODIGO no caminho e conferido: /fotos/5551/ so
           // vale para o 5551.
           || new RegExp('^https://imobeasy\\.online/fotos(-captacao/[a-z]+)?/' + Number(j.codigo) + '/').test(String(j.corpo.image || ''))
           || String(j.corpo.image || '') === 'https://imobeasy.online/colagens/' + Number(j.codigo) + '.jpg'))) motivo = 'foto_sem_codigo';
  else if (j.rota === 'send-text' && !String(j.corpo.message || '').trim()) motivo = 'texto_vazio';
  return { json: { ...j, enviar: motivo === null, motivo } };
});
