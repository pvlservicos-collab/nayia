/* O VERIFICADOR DE SEO DO BLOG (406, Pedro 17/10/2026: "uma ferramenta que checa meus posts ... checa meu SEO por boas
   práticas ... otimizado tanto para o Google quanto para o SEO para IA tipo GPT").
   Puro JavaScript, roda enquanto se escreve. Devolve a nota (0-100) e a lista de checagens em três grupos:
   Google (título, descrição, palavra-chave, estrutura), IAs (resposta direta, FAQ, dados concretos) e Leitura.
   Cada checagem tem peso; ok vale o peso, aviso metade, erro zero. */
window.BlogSEO = (function () {
  "use strict";
  function normalizar(s) { return String(s || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, ""); }
  function palavras(s) { return normalizar(s).replace(/[^a-z0-9\s]/g, " ").split(/\s+/).filter(Boolean); }
  function textoPuro(md) {
    return String(md || "").replace(/!\[[^\]]*\]\([^)]*\)/g, " ").replace(/\[([^\]]*)\]\([^)]*\)/g, "$1")
      .replace(/^#+\s*/gm, "").replace(/[*_`>~]/g, "").replace(/\|/g, " ");
  }

  function avaliar(d) {
    var itens = [];
    function add(grupo, peso, estado, texto, dica) { itens.push({ grupo: grupo, peso: peso, estado: estado, texto: texto, dica: dica || "" }); }
    var titulo = String(d.titulo || "").trim(), tl = titulo.length;
    var resumo = String(d.resumo || "").trim(), rl = resumo.length;
    var pc = normalizar(String(d.palavra_chave || "").trim());
    var md = String(d.corpo || "");
    var puro = textoPuro(md), ps = palavras(puro), total = ps.length;
    var linhas = md.split("\n");
    var h2 = linhas.filter(function (l) { return /^##\s/.test(l); }), h3 = linhas.filter(function (l) { return /^###\s/.test(l); }), h1 = linhas.filter(function (l) { return /^#\s/.test(l); });
    var paragrafos = md.split(/\n\s*\n/).map(function (p) { return p.trim(); }).filter(function (p) { return p && !/^#/.test(p) && !/^[-*]\s|^\d+\.\s|^>|^!\[|^\|/.test(p); });
    var primeiro = palavras(textoPuro(paragrafos[0] || "")), primeiros2 = palavras(textoPuro(paragrafos.slice(0, 2).join(" ")));
    var faq = (d.faq || []).filter(function (f) { return f && String(f.pergunta || "").trim() && String(f.resposta || "").trim(); });
    var temPc = function (s) { return pc && normalizar(s).indexOf(pc) >= 0; };

    /* ---- Google ---- */
    add("google", 10, !tl ? "erro" : (tl < 30 || tl > 65) ? "aviso" : "ok",
        "Título entre 30 e 65 caracteres (" + tl + ")", tl > 65 ? "o Google corta o que passa de ~65" : "título curto demais passa pouca informação");
    add("google", 10, !rl ? "erro" : (rl < 70 || rl > 160) ? "aviso" : "ok",
        "Resumo (meta descrição) entre 70 e 160 caracteres (" + rl + ")", "é o texto embaixo do título no Google e o que a IA cita");
    add("google", 6, !pc ? "erro" : "ok", "Palavra-chave principal definida", "a frase que a pessoa digitaria no Google");
    if (pc) {
      add("google", 6, temPc(titulo) ? "ok" : "aviso", "Palavra-chave no título");
      add("google", 5, temPc(paragrafos[0] || "") ? "ok" : "aviso", "Palavra-chave no primeiro parágrafo");
      add("google", 4, h2.some(temPc) ? "ok" : "aviso", "Palavra-chave em um subtítulo (H2)");
      var ocorr = (normalizar(puro).match(new RegExp(pc.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "g")) || []).length;
      var dens = total ? ocorr * pc.split(" ").length / total : 0;
      add("google", 3, !total ? "erro" : (ocorr === 0 ? "aviso" : (total >= 150 && dens > 0.03) ? "aviso" : "ok"),
          "Palavra-chave aparece " + ocorr + "x no texto" + (total >= 150 ? " (" + (dens * 100).toFixed(1) + "%)" : ""),
          ocorr === 0 ? "use ao menos 2 ou 3 vezes, com naturalidade" : "acima de 3% parece repetição forçada");
      var slug = normalizar(d.slug || "");
      add("google", 4, !slug ? "aviso" : (slug.length > 75 ? "aviso" : (slug.indexOf(pc.replace(/\s+/g, "-")) >= 0 || pc.split(" ").slice(0, 2).every(function (w) { return slug.indexOf(w) >= 0; })) ? "ok" : "aviso"),
          "Endereço curto e com a palavra-chave", "o slug nasce do título; se quiser, encurte");
    }
    add("google", 10, total < 150 ? "erro" : total < 400 ? "aviso" : "ok",
        "Texto com " + total + " palavras", total < 400 ? "artigos com 600 a 1.200 palavras costumam ranquear melhor" : "");
    add("google", 6, h2.length >= 2 ? "ok" : h2.length === 1 ? "aviso" : "erro", h2.length + " subtítulo(s) H2", "quebre o texto em partes: um ## a cada 200-300 palavras");
    add("google", 3, h1.length ? "aviso" : "ok", "Sem H1 no texto (o título já é o H1)", "troque # por ##");
    add("google", 3, (h3.length && !h2.length) ? "aviso" : "ok", "Hierarquia dos subtítulos (H3 só depois de um H2)");
    add("google", 6, !d.capa_url ? "erro" : !String(d.capa_alt || "").trim() ? "aviso" : "ok", "Capa com texto alternativo",
        !d.capa_url ? "artigo sem imagem perde o destaque no Google e nas redes" : "descreva a foto no campo de texto alternativo");
    var linksInternos = (md.match(/\]\((https?:\/\/(www\.)?imobeasy\.online[^)]*|https?:\/\/blog\.imobeasy\.online[^)]*|\/imovel\/\d+)\)/g) || []).length
      + (d.tipo === "imovel" && d.codigo ? 1 : 0) + ((d.imoveis_relacionados || []).length ? 1 : 0);
    add("google", 5, linksInternos ? "ok" : "aviso", "Link para o site ou para outro artigo (" + linksInternos + ")", "linke um imóvel, a página de comprar/alugar ou outro post");
    var imgs = md.match(/!\[([^\]]*)\]\([^)]*\)/g) || [], semAlt = imgs.filter(function (i) { return /^!\[\s*\]/.test(i); }).length;
    if (imgs.length) add("google", 3, semAlt ? "aviso" : "ok", "Imagens do texto com descrição (" + (imgs.length - semAlt) + " de " + imgs.length + ")", "![descrição](url)");

    /* ---- IAs ---- */
    add("ia", 7, primeiros2.length < 30 ? (total ? "aviso" : "erro") : primeiro.length > 110 ? "aviso" : "ok",
        "Resposta direta no começo (" + primeiro.length + " palavras no 1º parágrafo)",
        "as IAs citam quem responde a pergunta logo nas primeiras linhas; 40 a 90 palavras é o ideal");
    add("ia", 8, faq.length >= 2 ? "ok" : faq.length === 1 ? "aviso" : "erro", faq.length + " pergunta(s) frequente(s)",
        "duas ou três perguntas com resposta curta viram FAQ no Google e resposta pronta para a IA");
    if (faq.length) {
      var curtas = faq.filter(function (f) { var n = String(f.resposta).trim().length; return n < 40 || n > 400; }).length;
      add("ia", 3, curtas ? "aviso" : "ok", "Respostas da FAQ entre 40 e 400 caracteres", curtas + " fora da faixa");
    }
    add("ia", 3, /^(\s*[-*]\s|\s*\d+\.\s|\|)/m.test(md) ? "ok" : "aviso", "Lista ou tabela no texto", "listas e tabelas são o que a IA mais aproveita");
    var numeros = (puro.match(/\d+/g) || []).length;
    add("ia", 4, numeros >= 4 ? "ok" : numeros >= 1 ? "aviso" : "erro", "Dados concretos: " + numeros + " número(s) (valores, m², prazos, bairros)",
        "R$, metragem, quantos quartos, quantos dias: é o que diferencia de texto genérico");
    add("ia", 3, /manaus/i.test(puro + " " + titulo) ? "ok" : "aviso", "Diz que é em Manaus", "a IA e o Google precisam do lugar explícito");
    if (d.tipo === "imovel") add("ia", 5, d.codigo ? (d.imovel_no_ar === false ? "aviso" : "ok") : "erro", "Post de imóvel com o imóvel ligado", d.imovel_no_ar === false ? "o imóvel não está no ar: o card não aparece" : "digite o código do imóvel");

    /* ---- Leitura ---- */
    var longos = paragrafos.filter(function (p) { return palavras(textoPuro(p)).length > 120; }).length;
    add("leitura", 5, longos ? "aviso" : "ok", "Parágrafos até 120 palavras" + (longos ? " (" + longos + " acima)" : ""), "quebre em dois: no celular um parágrafo longo vira uma parede");
    var frases = puro.split(/[.!?]+\s/).map(function (f) { return palavras(f).length; }).filter(Boolean);
    var media = frases.length ? frases.reduce(function (a, b) { return a + b; }, 0) / frases.length : 0;
    add("leitura", 4, media > 26 ? "aviso" : "ok", "Frases curtas (média " + media.toFixed(0) + " palavras)", "até ~22 por frase lê bem");
    if (total > 350) add("leitura", 3, (total / Math.max(1, h2.length + h3.length)) > 350 ? "aviso" : "ok", "Um subtítulo a cada ~300 palavras");
    add("leitura", 2, d.categoria ? "ok" : "erro", "Categoria escolhida");
    add("leitura", 2, /\b(whatsapp|fale com|entre em contato|peça|veja o imóvel|clique)/i.test(puro) || (d.tipo === "imovel") ? "ok" : "aviso",
        "Chamada para ação (falar no WhatsApp, ver o imóvel)", "feche dizendo o próximo passo");

    var soma = 0, max = 0;
    itens.forEach(function (i) { max += i.peso; soma += i.peso * (i.estado === "ok" ? 1 : i.estado === "aviso" ? 0.5 : 0); });
    var nota = max ? Math.round(soma / max * 100) : 0;
    return { nota: nota, itens: itens, palavras: total,
             frase: nota >= 85 ? "Pronto para publicar" : nota >= 70 ? "Bom: ajuste os avisos" : nota >= 50 ? "Dá para melhorar" : "Falta o básico" };
  }

  function pintar(res, alvoLista, alvoNota, alvoAnel, alvoFrase) {
    var grupos = { google: "Google", ia: "IAs (ChatGPT, Perplexity…)", leitura: "Leitura" };
    alvoNota.textContent = res.nota;
    alvoAnel.style.setProperty("--p", res.nota);
    alvoAnel.style.setProperty("--cor", res.nota >= 80 ? "#3f9c6d" : res.nota >= 55 ? "#c4762f" : "#b42323");
    alvoFrase.textContent = res.frase;
    alvoLista.innerHTML = Object.keys(grupos).map(function (g) {
      var its = res.itens.filter(function (i) { return i.grupo === g; });
      if (!its.length) return "";
      var ok = its.filter(function (i) { return i.estado === "ok"; }).length;
      return '<div class="seo__grupo"><h3><span>' + grupos[g] + "</span><span>" + ok + "/" + its.length + "</span></h3>" +
        its.map(function (i) {
          return '<div class="seo__item seo__item--' + i.estado + '"><i>' + (i.estado === "ok" ? "✓" : i.estado === "aviso" ? "!" : "✕") + "</i><div>" +
            i.texto + (i.dica ? "<small>" + i.dica + "</small>" : "") + "</div></div>";
        }).join("") + "</div>";
    }).join("");
  }

  return { avaliar: avaliar, pintar: pintar };
})();
