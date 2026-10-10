/* ==========================================================================
   Imob Easy — ler a CONVERSA EXPORTADA do WhatsApp (o arquivo .txt, ou o .zip
   que o iPhone gera) e devolver as mensagens de texto.

   Para a aba Grupos › Captação ativa (09/10/2026): a Z-API não devolve o
   histórico dos grupos, então os pedidos "dos últimos 2 dias" só existem no
   celular. Exportar a conversa (grupo › Mais › Exportar conversa › Sem mídia)
   traz tudo em texto.

   Os dois formatos:
     Android   09/10/2026 14:32 - Fulano: mensagem
     iPhone    [09/10/2026, 14:32:15] Fulano: mensagem
   Mensagem de várias linhas continua nas linhas seguintes (sem data na
   frente). Aviso do sistema (entrou, saiu, mudou o nome) não tem "Nome: " e
   fica de fora, assim como mídia oculta e mensagem apagada.

   As datas são dia/mês/ano, na hora de Manaus (-04:00).
   ========================================================================== */
(function (raiz) {
  "use strict";

  var INICIO = /^[‎‏﻿]*\[?(\d{1,2})\/(\d{1,2})\/(\d{2,4}),?\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([AaPp]\.?\s?[Mm]\.?)?\]?\s*(?:-\s*)?(.*)$/;
  var SEM_CONTEUDO = /^[‎‏]*(<[^>]*(m[íi]dia|media|anexado|attached)[^>]*>|(imagem|v[íi]deo|[áa]udio|figurinha|documento|GIF|sticker|image|video|audio)\s+(ocultad[oa]|omitted|omitid[oa])|mensagem apagada|esta mensagem foi apagada|voc[êe] apagou esta mensagem|this message was deleted|you deleted this message|aguardando mensagem|waiting for this message)[.\s]*$/i;

  function doisDigitos(n) { return (n < 10 ? "0" : "") + n; }

  /** texto: o conteúdo do .txt. desdeMs: ignora o que for mais antigo (opcional). */
  function lerConversaExportada(texto, desdeMs) {
    var linhas = String(texto || "").replace(/\r\n?/g, "\n").split("\n"), mensagens = [], atual = null, avisos = 0, total = 0;
    function fechar() {
      if (!atual) return;
      var corpo = atual.texto.replace(/[‎‏]/g, "").trim();
      total += 1;
      if (corpo && !SEM_CONTEUDO.test(corpo) && (!desdeMs || atual.ms >= desdeMs)) {
        mensagens.push({ quando: atual.iso, autor: atual.autor, texto: corpo.slice(0, 8000) });
      }
      atual = null;
    }
    linhas.forEach(function (linha) {
      var m = INICIO.exec(linha);
      if (!m) {                                   // continuação da mensagem anterior
        if (atual) atual.texto += "\n" + linha;
        return;
      }
      fechar();
      var dia = +m[1], mes = +m[2], ano = +m[3], hora = +m[4], minuto = +m[5], segundo = +(m[6] || 0), periodo = (m[7] || "").toLowerCase().replace(/[.\s]/g, "");
      if (ano < 100) ano += 2000;
      if (periodo === "pm" && hora < 12) hora += 12;
      if (periodo === "am" && hora === 12) hora = 0;
      if (mes > 12 || dia > 31 || hora > 23) return;
      var resto = m[8], corte = resto.indexOf(": ");
      if (corte < 1 || corte > 80) { avisos += 1; return; }      // "Fulano entrou usando o link": aviso do sistema
      var iso = ano + "-" + doisDigitos(mes) + "-" + doisDigitos(dia) + "T" + doisDigitos(hora) + ":" + doisDigitos(minuto) + ":" + doisDigitos(segundo) + "-04:00";
      atual = { iso: iso, ms: Date.parse(iso), autor: resto.slice(0, corte).replace(/[‎‏‪-‮]/g, "").trim(), texto: resto.slice(corte + 2) };
    });
    fechar();
    return { mensagens: mensagens, lidas: total, avisos: avisos };
  }

  /** "Conversa do WhatsApp com NOME.txt" / "WhatsApp Chat - NOME.zip" -> NOME */
  function grupoDoArquivo(nome) {
    return String(nome || "").replace(/\.(txt|zip)$/i, "")
      .replace(/^(conversa do whatsapp com|conversa com|whatsapp chat with|whatsapp chat -|chat do whatsapp com)\s*/i, "")
      .replace(/\s*\(\d+\)$/, "").replace(/^_chat$/i, "").trim();
  }

  /** O .zip do iPhone: acha o primeiro .txt lá dentro e devolve o texto dele (Promise). */
  function textoDoZip(buffer) {
    var v = new DataView(buffer), fim = -1, i;
    for (i = buffer.byteLength - 22; i >= Math.max(0, buffer.byteLength - 70000); i--) {
      if (v.getUint32(i, true) === 0x06054b50) { fim = i; break; }
    }
    if (fim < 0) return Promise.reject(new Error("o arquivo .zip não abriu"));
    var qtd = v.getUint16(fim + 10, true), p = v.getUint32(fim + 16, true), utf8 = new TextDecoder("utf-8");
    for (i = 0; i < qtd && p + 46 <= buffer.byteLength; i++) {
      if (v.getUint32(p, true) !== 0x02014b50) break;
      var metodo = v.getUint16(p + 10, true), comprimido = v.getUint32(p + 20, true), nomeTam = v.getUint16(p + 28, true),
          extraTam = v.getUint16(p + 30, true), comentTam = v.getUint16(p + 32, true), local = v.getUint32(p + 42, true),
          nome = utf8.decode(new Uint8Array(buffer, p + 46, nomeTam));
      if (/\.txt$/i.test(nome)) {
        var inicio = local + 30 + v.getUint16(local + 26, true) + v.getUint16(local + 28, true);
        var dados = new Uint8Array(buffer, inicio, comprimido);
        if (metodo === 0) return Promise.resolve(utf8.decode(dados));
        if (metodo !== 8 || typeof DecompressionStream === "undefined") return Promise.reject(new Error("este navegador não abre o .zip: extraia o .txt e escolha ele"));
        var fluxo = new Blob([dados]).stream().pipeThrough(new DecompressionStream("deflate-raw"));
        return new Response(fluxo).arrayBuffer().then(function (b) { return utf8.decode(b); });
      }
      p += 46 + nomeTam + extraTam + comentTam;
    }
    return Promise.reject(new Error("não achei a conversa (.txt) dentro do .zip"));
  }

  var api = { lerConversaExportada: lerConversaExportada, grupoDoArquivo: grupoDoArquivo, textoDoZip: textoDoZip };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else raiz.WhatsAppExportado = api;
})(typeof window !== "undefined" ? window : this);
