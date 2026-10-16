/* ANUNCIAR NA OLX, o popup do editar imóvel (Pedro, 16/10/2026: "cria um botão lá nos imóveis em editar imóveis,
   anunciar na OLX, ele cria um popup de anúncio manualmente"; migração 396).

   O botão fica no topo, ao lado do Salvar. O popup lê o anúncio que o sistema monta do cadastro
   (GET /admin/api/imoveis/<código>/olx: título, descrição, preço, CEP e fotos, de venda e de locação), mostra o que já
   está na OLX, e a pessoa mexe no que quiser. "Publicar" pede ao serviço nay-olx (POST), que manda à OLX pela API em
   segundos; o popup acompanha o pedido (GET /admin/api/olx/pedido/<id>) até a OLX aceitar ou recusar. Depois a
   moderação da OLX leva alguns minutos; o serviço confere sozinho. */
(function () {
  "use strict";
  var codigo = new URLSearchParams(window.location.search).get("codigo");
  var cta = document.getElementById("nv-cta");
  if (!codigo || !cta) return;

  var NOME = { venda: "Venda", locacao: "Locação" };
  var ESTADO = { enviado: "enviado, na moderação da OLX", publicado: "publicado", recusado: "recusado pela moderação",
                 erro: "com erro", removendo: "sendo removido", removido: "removido" };
  var dados = null, negocio = null, fotos = [], vigia = null, enviando = false;

  function el(tag, cls, txt) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (txt != null) e.textContent = txt;
    return e;
  }
  function api(caminho, opcoes) {
    opcoes = opcoes || {};
    opcoes.credentials = "same-origin";
    return fetch(caminho, opcoes).then(function (r) {
      return r.json().catch(function () { return {}; }).then(function (j) { return { ok: r.ok, j: j }; });
    });
  }
  function reais(v) {
    var n = Number(String(v || "").replace(/\D/g, ""));
    return n ? "R$ " + n.toLocaleString("pt-BR") : "";
  }

  // ── o botão no topo ──
  var botao = el("button", "olxa__botao", "Anunciar na OLX");
  botao.type = "button";
  // os dois botões na mesma casa da faixa de cima (a grade dela tem três colunas: um quarto filho quebrava a linha)
  var acoes = el("div", "olxa__acoes");
  cta.parentNode.insertBefore(acoes, cta);
  acoes.appendChild(botao);
  acoes.appendChild(cta);

  // ── o popup ──
  var dlg = el("dialog", "olxa");
  dlg.setAttribute("aria-labelledby", "olxa-ttl");
  var inn = el("div", "olxa__in");
  var topo = el("div", "olxa__topo");
  var ttl = el("h2", "olxa__ttl", "Anunciar na OLX");
  ttl.id = "olxa-ttl";
  ttl.appendChild(el("small", null, "#" + codigo));
  var fechar = el("button", "olxa__fechar", "✕");
  fechar.type = "button";
  fechar.setAttribute("aria-label", "Fechar");
  topo.appendChild(ttl);
  topo.appendChild(fechar);

  var corpo = el("div", "olxa__corpo");
  var naOlx = el("div", "olxa__aviso");
  var abas = el("div", "olxa__abas");
  var barrado = el("div", "olxa__aviso olxa__aviso--erro");
  barrado.hidden = true;

  function campo(rotulo, entrada, limite) {
    var c = el("label", "olxa__campo");
    var r = el("span", "olxa__rot", rotulo);
    var conta = el("span", null, "");
    r.appendChild(conta);
    c.appendChild(r);
    c.appendChild(entrada);
    if (limite) {
      var atualizar = function () { conta.textContent = entrada.value.length + " / " + limite; };
      entrada.addEventListener("input", atualizar);
      c._atualizar = atualizar;
    }
    return c;
  }
  var titulo = el("input"); titulo.maxLength = 90;
  var descricao = el("textarea"); descricao.maxLength = 6000;
  var preco = el("input"); preco.inputMode = "numeric";
  var cep = el("input"); cep.inputMode = "numeric"; cep.maxLength = 9;
  var cTitulo = campo("Título", titulo, 90);
  var cDescricao = campo("Descrição", descricao, 6000);
  var dupla = el("div", "olxa__dupla");
  dupla.appendChild(campo("Preço", preco));
  dupla.appendChild(campo("CEP", cep));
  var info = el("div", "olxa__info");
  var rotFotos = el("div", "olxa__rot", "Fotos ");
  var contaFotos = el("span", null, "");
  rotFotos.appendChild(contaFotos);
  var grade = el("div", "olxa__fotos");
  var resultado = el("div", "olxa__aviso");
  resultado.hidden = true;
  var pedidos = el("div", "olxa__pedidos");

  [naOlx, abas, barrado, cTitulo, cDescricao, dupla, info, rotFotos, grade, resultado, pedidos].forEach(function (x) {
    corpo.appendChild(x);
  });

  var pe = el("div", "olxa__pe");
  var cancelar = el("button", "btn-neutro", "Fechar");
  cancelar.type = "button";
  var publicar = el("button", "btn-azul", "Publicar na OLX");
  publicar.type = "button";
  pe.appendChild(cancelar);
  pe.appendChild(publicar);
  inn.appendChild(topo);
  inn.appendChild(corpo);
  inn.appendChild(pe);
  dlg.appendChild(inn);
  document.body.appendChild(dlg);

  preco.addEventListener("input", function () { preco.value = reais(preco.value); });
  cep.addEventListener("input", function () {
    var d = cep.value.replace(/\D/g, "").slice(0, 8);
    cep.value = d.length > 5 ? d.slice(0, 5) + "-" + d.slice(5) : d;
  });

  // ── as fotos: ordem e tirar ──
  function desenharFotos() {
    grade.textContent = "";
    contaFotos.textContent = fotos.length + " (a primeira é a capa)";
    fotos.forEach(function (url, i) {
      var f = el("div", "olxa__foto");
      var img = el("img");
      img.src = url;
      img.alt = "Foto " + (i + 1);
      img.loading = "lazy";
      f.appendChild(img);
      f.appendChild(el("span", "olxa__foto-n", String(i + 1)));
      var bts = el("div", "olxa__foto-bts");
      [["◀", "Para a esquerda", -1], ["▶", "Para a direita", 1], ["✕", "Tirar do anúncio", 0]].forEach(function (b) {
        var bt = el("button", null, b[0]);
        bt.type = "button";
        bt.title = b[1];
        bt.addEventListener("click", function () {
          if (b[2] === 0) { fotos.splice(i, 1); }
          else {
            var j = i + b[2];
            if (j < 0 || j >= fotos.length) return;
            var t = fotos[i]; fotos[i] = fotos[j]; fotos[j] = t;
          }
          desenharFotos();
        });
        bts.appendChild(bt);
      });
      f.appendChild(bts);
      grade.appendChild(f);
    });
  }

  // ── o que veio do servidor ──
  function mostrarNaOlx() {
    var lista = (dados && dados.na_olx) || [];
    naOlx.className = "olxa__aviso";
    naOlx.textContent = "";
    if (!lista.length) { naOlx.textContent = "Este imóvel ainda não tem anúncio na OLX."; return; }
    lista.forEach(function (a, i) {
      if (i) naOlx.appendChild(el("br"));
      naOlx.appendChild(document.createTextNode((NOME[a.negocio] || a.negocio) + ": " + (ESTADO[a.estado] || a.estado)));
      if (a.url) {
        naOlx.appendChild(document.createTextNode(" · "));
        var l = el("a", null, "ver na OLX");
        l.href = a.url; l.target = "_blank"; l.rel = "noopener";
        naOlx.appendChild(l);
      }
      if (a.mensagem && a.estado !== "publicado") naOlx.appendChild(document.createTextNode(" (" + a.mensagem + ")"));
    });
    if (lista.some(function (a) { return a.estado === "publicado"; })) naOlx.className = "olxa__aviso olxa__aviso--ok";
  }
  function mostrarPedidos() {
    pedidos.textContent = "";
    ((dados && dados.pedidos) || []).slice(0, 3).forEach(function (p) {
      var quando = p.criado_em ? new Date(p.criado_em).toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" }) : "";
      pedidos.appendChild(el("div", null, "Pedido " + quando + " (" + (NOME[p.negocio] || p.negocio) + ", " +
        (p.pedido_por || "painel") + "): " + p.estado + (p.resultado ? " — " + p.resultado : "")));
    });
  }
  function escolher(n) {
    negocio = n;
    var m = (dados && dados[n]) || {};
    Array.prototype.forEach.call(abas.children, function (b) { b.setAttribute("aria-pressed", String(b.dataset.n === n)); });
    var ok = !!m.ok;
    barrado.hidden = ok;
    barrado.textContent = ok ? "" : "Não dá para anunciar " + NOME[n].toLowerCase() + ": " +
      (m.barrado || (m.falta || []).join("; ") || "o anúncio não monta") + ".";
    var a = m.anuncio || {};
    titulo.value = a.subject || m.titulo || "";
    descricao.value = a.body || "";
    preco.value = reais(a.price || m.preco);
    var z = String(a.zipcode || "");
    cep.value = z.length === 8 ? z.slice(0, 5) + "-" + z.slice(5) : z;
    fotos = (a.images || []).slice();
    cTitulo._atualizar(); cDescricao._atualizar();
    var p = a.params || {};
    info.textContent = [p.size ? p.size + " m²" : "", p.rooms ? p.rooms + " quartos" : "", p.bathrooms ? p.bathrooms + " banheiros" : "",
      p.garage_spaces ? p.garage_spaces + " vagas" : "", "categoria " + (a.category || "-")].filter(Boolean).join(" · ") +
      " — vêm do cadastro.";
    desenharFotos();
    var ja = ((dados && dados.na_olx) || []).some(function (x) { return x.negocio === n && x.estado !== "removido"; });
    publicar.textContent = ja ? "Atualizar o anúncio na OLX" : "Publicar na OLX";
    publicar.disabled = !ok || enviando;
    [cTitulo, cDescricao, dupla, info, rotFotos, grade].forEach(function (x) { x.hidden = !ok; });
  }
  function montarAbas() {
    abas.textContent = "";
    ["venda", "locacao"].forEach(function (n) {
      var m = (dados && dados[n]) || {};
      var b = el("button", "olxa__aba", NOME[n]);
      b.type = "button";
      b.dataset.n = n;
      var nada = !m.ok && /sem valor/i.test(String(m.barrado || "") + (m.falta || []).join(" "));
      b.disabled = nada;
      b.title = nada ? "Sem valor de " + (n === "venda" ? "venda" : "aluguel") + " no cadastro" : "";
      b.addEventListener("click", function () { escolher(n); });
      abas.appendChild(b);
    });
    var primeiro = ["venda", "locacao"].filter(function (n) { return dados && dados[n] && dados[n].ok; })[0] || "venda";
    escolher(negocio && dados[negocio] && dados[negocio].ok ? negocio : primeiro);
  }
  function carregar(soAsituacao) {
    if (!soAsituacao) {
      naOlx.className = "olxa__aviso";
      naOlx.textContent = "Carregando o anúncio…";
    }
    return api("/admin/api/imoveis/" + encodeURIComponent(codigo) + "/olx").then(function (r) {
      if (!r.ok) throw new Error((r.j && (r.j.detalhe || r.j.erro)) || "não consegui ler o anúncio");
      dados = r.j;
      mostrarNaOlx();
      mostrarPedidos();
      if (soAsituacao) {          // depois de publicar: o que a pessoa escreveu fica na tela
        publicar.disabled = enviando;
        return;
      }
      montarAbas();
    }).catch(function (e) {
      naOlx.className = "olxa__aviso olxa__aviso--erro";
      naOlx.textContent = e.message;
    });
  }

  // ── publicar e acompanhar ──
  function aviso(classe, texto) {
    resultado.hidden = false;
    resultado.className = "olxa__aviso " + classe;
    resultado.textContent = texto;
  }
  function acompanhar(id, desde) {
    clearTimeout(vigia);
    api("/admin/api/olx/pedido/" + id).then(function (r) {
      var p = r.j || {};
      if (p.estado === "enviado") {
        enviando = false;
        aviso("olxa__aviso--ok", "A OLX aceitou o anúncio. Agora passa pela moderação dela (costuma levar alguns minutos); " +
          "o sistema confere sozinho e o link aparece aqui em cima.");
        carregar(true);
        return;
      }
      if (p.estado === "falhou") {
        enviando = false;
        aviso("olxa__aviso--erro", "A OLX não aceitou: " + (p.resultado || "sem motivo") + ".");
        carregar(true);
        return;
      }
      if (Date.now() - desde > 180000) {
        enviando = false;
        aviso("olxa__aviso--vai", "O pedido está na fila do serviço da OLX. Pode fechar: o resultado aparece aqui depois.");
        publicar.disabled = false;
        return;
      }
      vigia = setTimeout(function () { acompanhar(id, desde); }, 3000);
    }).catch(function () { vigia = setTimeout(function () { acompanhar(id, desde); }, 5000); });
  }
  publicar.addEventListener("click", function () {
    if (enviando || !negocio) return;
    if (!fotos.length) { aviso("olxa__aviso--erro", "O anúncio precisa de pelo menos uma foto."); return; }
    enviando = true;
    publicar.disabled = true;
    aviso("olxa__aviso--vai", "Mandando para a OLX…");
    api("/admin/api/imoveis/" + encodeURIComponent(codigo) + "/olx", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ negocio: negocio, subject: titulo.value.trim(), body: descricao.value.trim(),
                             price: preco.value, zipcode: cep.value, images: fotos })
    }).then(function (r) {
      if (!r.ok || !r.j.pedido) throw new Error((r.j && r.j.erro) || "não consegui pedir");
      aviso("olxa__aviso--vai", "Pedido feito: o serviço está mandando à OLX…");
      acompanhar(r.j.pedido, Date.now());
    }).catch(function (e) {
      enviando = false;
      publicar.disabled = false;
      aviso("olxa__aviso--erro", e.message);
    });
  });

  function abrir() {
    resultado.hidden = true;
    if (typeof dlg.showModal === "function") dlg.showModal(); else dlg.setAttribute("open", "");
    carregar();
  }
  function sair() { clearTimeout(vigia); if (dlg.open) dlg.close(); }
  botao.addEventListener("click", abrir);
  fechar.addEventListener("click", sair);
  cancelar.addEventListener("click", sair);
  dlg.addEventListener("click", function (e) { if (e.target === dlg) sair(); });
})();
