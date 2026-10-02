// CHECAGEM DUPLA DAS FOTOS (camada 2). A tabela nao tinha foto deste
// imovel: le o anuncio AO VIVO no site, como o publicador faz, e o banco
// grava antes de responder. Caso Regiane (01/09): 2014 com 24 fotos no
// anuncio e zero na tabela -- ela disse que nao tinha.
const r = $('Achar codigo na resposta').first().json;
const falt = (($input.first().json || {}).faltando || []).slice(0, 3);
const lidas = [];
for (const c of falt) {
  try {
    const html = String(await this.helpers.httpRequest({ method: 'GET', url: 'https://imobeasy.com/anuncios/' + c, timeout: 15000, json: false }) || '');
    const ini = html.indexOf('id="imagens"');
    if (ini < 0) continue;
    const fim = html.indexOf('</ul>', ini);
    const trecho = html.slice(ini, fim > ini ? fim : ini + 300000);
    const urls = [];
    for (const m of trecho.matchAll(/<a\b[^>]*>/g)) {
      const tag = m[0];
      if (!/class="[^"]*gallery-item/.test(tag)) continue;
      const h = tag.match(/href="([^"]+)"/);
      if (!h) continue;
      const u = h[1].startsWith('http') ? h[1] : 'https://imobeasy.com' + h[1];
      if (!urls.includes(u)) urls.push(u);
    }
    lidas.push({ codigo: Number(c), urls });
  } catch (e) { /* site fora: segue; a guarda de promessa avisa o Tel */ }
}
return [{ json: { texto: r.texto, codigos: r.codigos, escreveu: r.escreveu, fotos_site: lidas } }];
