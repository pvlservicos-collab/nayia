// >>> telefone na frente sem verbo (28/09)
const _UM_CODIGO_DEPOIS_DO_TEL = (x) => {
  const s = String(x == null ? '' : x);
  const m = /^\s*(?:@?nay\b[\s,;:.!?-]*)?((?:55[\s.-]*)?\(?\d{2}\)?[\s.-]*9?\d{4}[\s.-]*\d{4})\b/i.exec(s);
  if (!m) return false;
  const resto = s.slice(m.index + m[0].length);
  if (/\b(post|public|dispar|solt|tir|remov|retir|vende|vendid|aluga|alugad|vaga|lista|agenda|resposta|descart|pendencia|corretor|devolv)\w*\b/i.test(resto)) return false;
  const semTel = resto.replace(/(?:55[\s.-]*)?\(?\d{2}\)?[\s.-]*9?\d{4}[\s.-]*\d{4}/g, ' ');
  const cods = semTel.match(/(?<![\d.,])\d{3,5}(?![\d.,])/g) || [];
  return cods.length === 1;
};
// <<< telefone na frente sem verbo
// >>> segundo numero do Tel (28/09)
const TELS_DO_TEL = ['[telefone …7316]', '[telefone …6408]'];
const _finalDoTel = (x) => String(x == null ? '' : x).replace(/\D/g, '').slice(-8);
const _FINAIS_DO_TEL = TELS_DO_TEL.map(_finalDoTel);
const ehTelDoTel = (x) => _FINAIS_DO_TEL.indexOf(_finalDoTel(x)) !== -1;
// <<< segundo numero do Tel
// LIDO de `regex_liberar.js` pelo patch -- nao editar aqui.
const TAXA_CODIGO = /^(\d{3,5})\s*[-–—:,]?\s*([^\d]{2,40})$/;
const FALA_DE_TAXA = /\b(tx|taxa|condominio|condomínio|cond)\b/i;
const FALA_DE_INCLUSAO = /\b(inclus[ao]|inclu[íi]d[ao]|inclui)\b/i;
const NEGA = /\b(nao|não|sem)\b/i;

function ehComandoDeTaxa(texto) {
  const m = TAXA_CODIGO.exec(String(texto || ''));
  if (!m) return false;
  const resto = m[2];
  if (!FALA_DE_TAXA.test(resto)) return false;
  return FALA_DE_INCLUSAO.test(resto) || NEGA.test(resto);
}

const VOC = '(?:@?nay\\b[\\s,;:.!?-]*)?';

const V_DESCARTA =
  '(?:descarta|descartar|descarte|esquece|esquecer|esqueca|esqueça|' +
  'apaga|apagar|cancela|cancelar|ignora|ignorar)';

const V_RESPOSTA = '(?:resposta|responde|responder)';

const LIGACAO = '(?:\\s+a)?(?:\\s+pend[eê]ncias?)?';

const RE_RESPOSTA = new RegExp(
  '^\\s*' + VOC + V_RESPOSTA + LIGACAO + '\\s+(\\d{1,6})\\s+([\\s\\S]+?)\\s*$', 'i');

const RE_DESCARTA = new RegExp(
  '^\\s*' + VOC + V_DESCARTA + LIGACAO + '\\s+(\\d{1,6})\\s*$', 'i');

const RE_DESCARTA_TUDO = new RegExp(
  '^\\s*' + VOC + V_DESCARTA + '\\s+tudo\\s*$', 'i');

const RE_DESCARTA_TUDO_SIM = new RegExp(
  '^\\s*' + VOC + V_DESCARTA + '\\s+tudo\\s+sim\\s*$', 'i');

const RE_LISTAR = new RegExp(
  '^\\s*' + VOC + '(?:pend[eê]ncias?|pendentes)\\s*$', 'i');

function ehComandoDePendencia(t) {
  const s = String(t || '');
  return RE_DESCARTA_TUDO_SIM.test(s) || RE_DESCARTA_TUDO.test(s) ||
         RE_DESCARTA.test(s) || RE_RESPOSTA.test(s) || RE_LISTAR.test(s);
}

function interpretarPendencia(t) {
  const s = String(t || '');
  let m;
  if (RE_DESCARTA_TUDO_SIM.test(s)) return { acao: 'DESCARTAR TUDO SIM', p_id: null, p_texto: null };
  if (RE_DESCARTA_TUDO.test(s)) return { acao: 'DESCARTAR TUDO', p_id: null, p_texto: null };
  m = s.match(RE_RESPOSTA);
  if (m) return { acao: 'RESPOSTA', p_id: parseInt(m[1], 10), p_texto: m[2].trim() };
  m = s.match(RE_DESCARTA);
  if (m) return { acao: 'DESCARTAR', p_id: parseInt(m[1], 10), p_texto: null };
  if (RE_LISTAR.test(s)) return { acao: 'PENDENCIAS', p_id: null, p_texto: null };
  return null;
}

const TEL = TELS_DO_TEL[0];
const j = $('Juntar mensagens').first().json;
if (!ehTelDoTel(j.telefone)) return [];
// >>> resposta a pergunta (patch_resposta_ao_tel_n8n.js)
// LIDO de `regex_resposta_ao_tel.js` pelo patch -- nao editar aqui.
const RESPOSTA_SIM_RE = /^\s*(?:@?nay\b[\s,;:.!?-]*)?(?=[\s\S]*\b(?:sim|s|pode|isso|ok|okay|beleza|blz|confirm[oa]|confirmado|quero|bora|manda|posta|postar|poste|reposta|repostar|claro|certo|novamente)\b)(?:(?:sim|s|pode|isso|ok|okay|beleza|blz|confirm[oa]|confirmado|quero|bora|manda|posta|postar|poste|reposta|repostar|claro|certo|mesmo|com\s+certeza|de\s+novo|novamente|outra\s+vez|por\s+favor|pfv|pf|nay)(?:[\s,;.!]+|$)){1,8}$/i;
const RESPOSTA_NAO_RE = /^\s*(?:@?nay\b[\s,;:.!?-]*)?(?:n[aã]o|n|deixa(?:\s+quieto)?|esquece|cancela|agora\s+n[aã]o|melhor\s+n[aã]o)(?:[\s,;.!]+(?:n[aã]o|precisa|posta|postar|obrigad[oa]|nay|por\s+enquanto|agora|quieto))*[\s,;.!]*$/i;
function respostaAoTel(texto) {
  const s = String(texto || '').trim();
  if (RESPOSTA_SIM_RE.test(s)) return 'sim';
  if (RESPOSTA_NAO_RE.test(s)) return 'nao';
  return null;
}
// Só vale com PERGUNTA ABERTA. Sem ela, "sim" é conversa e segue o caminho
// de sempre. Timeout longo: o "sim" pode postar no Easy com todas as fotos.
if (j.perguntaAberta === true && respostaAoTel(j.texto)) {
  try {
    await this.helpers.httpRequest({
      method: 'POST', url: 'http://172.16.0.1:8080/comando',
      headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer <REDIGIDO>' },
      body: { texto: String(j.texto || '').trim() }, json: true, timeout: 600000
    });
  } catch (e) {}
  return [];
}
// <<< resposta a pergunta
// >>> envio de lista + escolha (patch_envio_de_lista_n8n.js)
// LIDO de `regex_envio_de_lista.js` pelo patch -- nao editar aqui.
const ENVIO_RE_LISTA = /^\s*(?:@?nay\b[\s,;:.!?-]*)?(envi|m[a]?nd|repass|encaminh|mostr|post|public|dispar|solt)(?:a|ar|e|ei|ou|o)?\b([\s\S]*)(?:\bpara\b|\bpra\b|\bpro\b|\bp\/)\s*([\s\S]+?)\s*$/i;
const NAO_PESSOA_LISTA = /\b(grupos?|grade|vagas?|easy|anunciar|todos os corretores)\b/i;
const ESCOLHER_CODIGO_RE = /^\s*(?:@?nay\b[\s,;:.!?-]*)?(?:c[óo]digos?|cods?)\b[\s:=-]*((?:\d{3,5}[\s,;]*(?:e\s+)?)+)$/i;
function ehEnvioDeLista(texto) {
  const linhas = String(texto || '').split('\n');
  if (linhas.length < 2) return false;
  if (!linhas.slice(1).some((l) => l.trim())) return false;

  const m = linhas[0].trim().match(ENVIO_RE_LISTA);
  if (!m) return false;
  if (NAO_PESSOA_LISTA.test(m[3])) return false;
  // codigo no corpo -> caminho antigo
  if (/\b\d{1,6}\b/.test(m[2])) return false;
  return true;
}

const ANTES_DA_ESCOLHA =
  '(?:(?:sim|isso|ok|blz|beleza|pode|quero|vai|bora|manda|mande|mandar|' +
  'envia|envie|enviar|pode\\s+mandar|pode\\s+enviar)' +
  '[\\s,;.!]*)*';

const ESCOLHA_NATURAL_RE = new RegExp(
  '^\\s*(?:@?nay\\b[\\s,;:.!?-]*)?' + ANTES_DA_ESCOLHA +
  '(?:([oa]s?)\\s+)?' +
  '(?:(ambos|ambas|tod[oa]s)' +
  '|(dois|duas|tr[êe]s|quatro|cinco)' +
  '|([2-5])' +
  '|(primeir[oa]|segund[oa]|terceir[oa]|[úu]ltim[oa]))' +
  '\\b([^\\n]*)$', 'i');

const ESCOLHA_SO_CODIGOS_RE = new RegExp(
  '^\\s*(?:@?nay\\b[\\s,;:.!?-]*)?' + ANTES_DA_ESCOLHA +
  '(?:[oa]s?\\s+)?' +
  '(\\d{3,5}(?:\\s*(?:,|;|\\+|/|e)\\s*(?:[oa]s?\\s+)?\\d{3,5})+)' +
  '[\\s.!]*$', 'i');

const CATEGORIA_NA_CAUDA =
  /\b(apartamentos?|aptos?|coberturas?|flats?|casas?|sobrados?|salas?\s+comerciais?|salas?|lojas?|lotes?|terrenos?|listas?)\b/i;

const CAUDA_COM_DESTINO = /\b(?:para|pra|pro|p\/)\s+/i;

const CAUDA_DE_IMOVEL =
  /\b(?:quartos?|su[íi]tes?|vagas?|dormit[óo]rios?|banheiros?|mobiliad[oa]s?|semi|climatizad[oa]s?|andar|torre|bloco)\b|\d\s*(?:k\b|m2|m²)|r\$|\//i;

const CAUDA_DE_GRUPO =
  /\b(grupos?|grade|vagas?|easy|anunciar|todos os corretores)\b/i;

function ehEscolhaNatural(texto) {
  const t = String(texto || '');
  if (ESCOLHA_SO_CODIGOS_RE.test(t)) return true;
  const m = t.match(ESCOLHA_NATURAL_RE);
  if (!m) return false;
  // "os 2" e escolha; "2" sozinho nao e nada. O artigo e o que separa.
  if (m[4] && !m[1]) return false;
  const cauda = m[6] || '';
  return !CATEGORIA_NA_CAUDA.test(cauda) && !CAUDA_COM_DESTINO.test(cauda)
      && !CAUDA_DE_IMOVEL.test(cauda) && !CAUDA_DE_GRUPO.test(cauda);
}

// A LISTA COLADA VAI INTEIRA (Tel, 11/09). O laco abaixo manda so a
// linha que casou, e para a lista isso entrega ao publicador um comando
// sem imovel nenhum: os codigos estao nas linhas de baixo. Medido, a
// resposta era "nao entendi qual imovel mandar para Tel Sobreira".
//
// A escolha de codigo ("Nay codigo 5719") entra no MESMO ramo porque e
// ela que dispara o envio da lista que ficou segurada -- e por isso
// tambem precisa do tempo longo.
//
// TIMEOUT DE 10 MINUTOS: o envio roda dentro da requisicao e leva ~50-60s
// por imovel com fotos; quatro imoveis passam dos 120s dos outros ramos.
// Estourar aqui faria o Tel nao receber confirmacao e reenviar -- e a
// trava de 12h em `envios` e que segura o imovel de sair duas vezes.
const textoInteiro = String(j.texto || '');
if (ehEnvioDeLista(textoInteiro)
    || ESCOLHER_CODIGO_RE.test(textoInteiro.trim())
    // "os dois" (12/09): ele respondeu isso e a frase caiu no agente,
    // que devolveu uma lista sem nexo. A propria pergunta dela dizia
    // "ou os dois".
    || ehEscolhaNatural(textoInteiro.trim())) {
  try {
    await this.helpers.httpRequest({
      method: 'POST', url: 'http://172.16.0.1:8080/comando',
      headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer <REDIGIDO>' },
      body: { texto: textoInteiro }, json: true, timeout: 600000
    });
  } catch (e) {}
  return [];
}
// <<< envio de lista + escolha

// >>> escolha do posta (patch_escolha_do_posta_n8n.js)
// LIDO de `regex_escolha_do_posta.js` pelo patch -- nao editar aqui.
const PREFIXO_DA_ESCOLHA =
  '(?:@?nay\\b[\\s,;:.!?-]*)?(?:(?:[eé]|eh|para|pra|pro|de|do|o|a|no|na|esse|essa|c[óo]digo|cod|por)\\s+)*';

const ESCOLHA_DO_POSTA_RE = new RegExp(
  '^\\s*' + PREFIXO_DA_ESCOLHA
  + '(?:loca[çc][ãaoõ]\\w*|alug\\w*|arrend\\w*|vend[ae]s?|vender'
  + '|r\\$\\s*\\d[\\d.,]*'
  + '|\\d[\\d.,]*\\s*(?:milh\\w*|mil|mi|k|m)'
  + '|\\d{1,3}[.,]\\d{3}'
  + '|\\d{3,5})'
  + '[\\s.!,;]*$', 'i');
// TIMEOUT LONGO: a resposta dele DISPARA a postagem nos grupos, com
// foto -- e o ramo de comando curto (8s) estouraria no meio.
const respostaDoPosta = String(j.texto || '').trim();
if (j.perguntaAberta === true && ESCOLHA_DO_POSTA_RE.test(respostaDoPosta)) {
  try {
    await this.helpers.httpRequest({
      method: 'POST', url: 'http://172.16.0.1:8080/comando',
      headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer <REDIGIDO>' },
      body: { texto: respostaDoPosta }, json: true, timeout: 600000
    });
  } catch (e) {}
  return [];
}
// <<< escolha do posta
// >>> telefone na frente (patch 23/09)
const ENVIO_TEL_FRENTE = /^\s*(?:@?nay\b[\s,;:.!?-]*)?(envi|m[a]?nd|repass|encaminh)(?:a|ar|e|ei|ou|o)?\b\s*(?:para\s+|pra\s+|pro\s+|p\/\s*)?((?:55[\s.-]*)?\(?\d{2}\)?[\s.-]*\d{4,5}[\s.-]*\d{4})\s+(c[o\u00f3]d(?:igo)?s?\b[\s:=.-]*\d{2,5}(?:[\s,;]+(?:e\s+)?(?:o|os)?\s*\d{2,5})*|(?:o|os|a|as)?\s*\d{3,5}(?:[\s,;]+(?:e\s+)?(?:o|os)?\s*\d{3,5})*)\s*$/i;
const ENVIO_TEL_ANTES = /^\s*(?:55[\s.-]*)?\(?\d{2}\)?[\s.-]*\d{4,5}[\s.-]*\d{4}[\s,;:.-]+(?:@?nay\b[\s,;:.!?-]*)?(?:en+vi|m[a]?n+d|repass+|encaminh)(?:a|ar|e|ei|ou|o)?\b/i;
const ALTO_PADRAO_GRUPO = /^\s*(?:@?nay\b[\s,;:.!?-]*)?(?:envi|m[a]?n+d|repass+|encaminh)(?:a|ar|e|ei|ou|o)?\b(?=[\s\S]*\balto[\s\-]*padr[a\u00e3]o\b)(?=[\s\S]*\b(?:grupo|easy|anunciar)\b)/i;
const EH_ENVIO_TEL = (x) => ENVIO_TEL_FRENTE.test(x) || ENVIO_TEL_ANTES.test(x) || ALTO_PADRAO_GRUPO.test(x) || _UM_CODIGO_DEPOIS_DO_TEL(x);
// <<< telefone na frente
const linhas = String(j.texto || '').split('\n');
for (const bruta of linhas) {
  const linha = bruta.trim();
  if (!linha) continue;
  const up = linha.toUpperCase();
  // A gramatica de pendencia mora em regex_pendencia.js, com 45 casos
  // em casos_comando_pendencia.json. 'descarta 47' e 'esquece 47' sao
  // formas que o Tel usa de verdade.
  const pend = interpretarPendencia(linha);
  if (pend) return [{ json: { acao: pend.acao, p_id: pend.p_id, p_texto: pend.p_texto, tel_tel: TEL } }];
  if (up === 'PENDENCIAS' || up === 'PEND\u00caNCIAS') return [{ json: { acao: 'PENDENCIAS', p_id: null, p_texto: null, tel_tel: TEL } }];
  // ENVIO PRIVADO (31/08): mesma regex do interpretar_comando.py. Vem
  // ANTES dos verbos antigos porque "posta o 5750 pro Sergio" precisa
  // chegar ao Python para ser RECUSADO, em vez de virar postagem em 14
  // grupos. Timeout maior: um envio com fotos leva mais que 8s.
  const ENVIO_RE = /^\s*(?:@?nay\b[\s,;:.!?-]*)?(envi|m[a]?nd|repass|encaminh|mostr|post|public|dispar|solt)(?:a|ar|e|ei|ou|o)?\b([\s\S]*)(?:\bpara\b|\bpra\b|\bpro\b|\bp\/)\s*([\s\S]+?)\s*$/i;
  const NAO_PESSOA_RE = /\b(grupos?|grade|vagas?|easy|anunciar|todos os corretores)\b/i;
  const mEnv = linha.match(ENVIO_RE);
  const mTelFrente = EH_ENVIO_TEL(linha);
  if (mTelFrente || (mEnv && !NAO_PESSOA_RE.test(mEnv[3]))) {
    try {
      await this.helpers.httpRequest({
        method: 'POST', url: 'http://172.16.0.1:8080/comando',
        headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer <REDIGIDO>' },
        body: { texto: linha }, json: true, timeout: 120000
      });
    } catch (e) {}
    return [];
  }
// >>> pedido sem destinatario (patch_pedido_sem_destino_n8n.js)
  // LIDO de `regex_envio_de_lista.js` pelo patch -- nao editar aqui.
  const VALOR_ESCRITO = '(?:\\d+[.,]?\\d*\\s*(?:k|mil|milh\\w*|mi)\\b|\\d{1,3}\\.\\d{3}\\b'
    + '|\\b(?:at[eé]|a\\s+partir\\s+de|acima\\s+de|no\\s+m[aá]ximo|m[aá]ximo\\s+de)\\s+r?\\$?\\s*\\d)';
  
  const PEDIDO_SEM_DESTINO_RE = new RegExp(
    '^\\s*@?nay\\b[\\s,;:.!?-]*'
    + '(?:envi|m[a]?nd|repass|encaminh|mostr|dispar|solt)\\w*\\b\\s+'
    + '[\\s\\S]*' + VALOR_ESCRITO, 'i');
  if (PEDIDO_SEM_DESTINO_RE.test(linha)) {
    try {
      await this.helpers.httpRequest({
        method: 'POST', url: 'http://172.16.0.1:8080/comando',
        headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer <REDIGIDO>' },
        body: { texto: linha }, json: true, timeout: 120000
      });
    } catch (e) {}
    return [];
  }
// <<< pedido sem destinatario
  if (/^(@?NAY\b[\s,:;.!\-]*)?((POSTA|POSTAR|PUBLICA|PUBLICAR|DISPARA|DISPARAR|SOLTA|TIRA|TIRAR|REMOVE|REMOVER|RETIRA|RETIRAR|VENDEU|VENDIDO|VENDIDA|ALUGOU|ALUGADO|ALUGADA|VAGAS|VAGA|LISTA)\b|AGENDA\s+DE\s+VISITAS?\b|VISITAS?\s+(AGENDADAS?|DO\s+DIA|DE\s+HOJE)\b|AGENDA\b|(MANDA|MANDAR|MANDE|ENVIA|ENVIAR|ENVIE)\s+(AS?\s+|OS?\s+)?(LISTA|APARTAMENTOS?|APTOS?|COBERTURAS?|FLATS?|CASAS?|SOBRADOS?|SALAS?|LOJAS?|LOTES?|TERRENOS?)\b)/i.test(up)
      // "5712 Alugado" -- o codigo na frente (Tel, 09/09). Mesmo literal
      // de `regex_liberar.js`, exercitado por `casos_comando_liberar.json`.
      || /^(?:@?NAY\b[\s,:;.!\-]*)?(\d{3,5})\s*[-–—:,]?\s*(?:JA|JÁ)?\s*(VENDEU|VENDIDO|VENDIDA|ALUGOU|ALUGADO|ALUGADA)\b/i.test(up)
      || ehComandoDeTaxa(up)
      // "5712 Alugado" -- o codigo na frente (Tel, 09/09). Mesmo literal
      // de `regex_liberar.js`, exercitado por `casos_comando_liberar.json`.
      || /^(?:@?NAY\b[\s,:;.!\-]*)?(\d{3,5})\s*[-–—:,]?\s*(?:JA|JÁ)?\s*(VENDEU|VENDIDO|VENDIDA|ALUGOU|ALUGADO|ALUGADA)\b/i.test(up)) {
    try {
      await this.helpers.httpRequest({
        method: 'POST',
        url: 'http://172.16.0.1:8080/comando',
        headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer <REDIGIDO>' },
        body: { texto: linha },
        json: true,
        timeout: 8000
      });
    } catch (e) {}
    return [];
  }
}
return []
