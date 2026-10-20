/* ==========================================================================
   IMÓVEIS › CHECKLIST RÁPIDO (Pedro, 20/10/2026)
   "Quero que você organize os imóveis de locação pra mim em um tinder, ou seja uma lista de todos, e eu vou marcando
   fino acabamento SIM | NÃO manualmente; esse vai ser uma aba 'Checklist rápido' lá na aba Imóveis; vou fazer outros,
   e eles vão ficar em lista lá ... Sempre que for adicionado um imóvel eu vou nesse checklist rápido e ele fica lá:
   Fino acabamento? Pendente, até eu digitar sim ou não."

   A aba é uma LISTA DE CHECKLISTS. Quem diz quais existem é o servidor (CHECKLISTS_RAPIDOS no app.py: id, título,
   pergunta, a chave do `extras`, as opções e o público); aqui só se desenha. Checklist novo = uma entrada lá.
     GET /admin/api/imoveis/checklists              a lista, com quantos faltam
     GET /admin/api/imoveis/checklists/<id>[?todos=1] os imóveis (Disponíveis primeiro; todos=1 traz os demais)
     PUT /admin/api/imoveis/<código> {extras: {<chave>: "Sim" | "Não" | null}}   responder (null = pendente de novo)
   Pendente = o imóvel não tem a chave; imóvel novo aparece sozinho.

   Um imóvel por vez, com todas as fotos numa grade (clique amplia em tela cheia). Teclado: S ou → = Sim, N ou ← = Não,
   ↓ ou P = pular, ↑ ou Z = desfazer o último. No celular: arrastar o cartão para a direita = Sim, para a esquerda = Não.
   ========================================================================== */
(function () {
  "use strict";
  var aba = document.querySelector('[data-painel-abre="checklist"]');
  var painel = document.querySelector('[data-painel="checklist"]');
  if (!aba || !painel) return;

  var lista = null;          // os checklists, como o servidor mandou
  var atual = null;          // o checklist aberto
  var itens = [];            // os imóveis do checklist aberto
  var todos = false;         // só os Disponíveis (false) ou todos do público (true)
  var revisar = false;       // false: os pendentes; true: os já respondidos (para mudar)
  var fila = [];             // códigos na ordem em que vão aparecer
  var pulados = [];          // pulados nesta volta: vão para o fim
  var historico = [];        // [{codigo, antes, depois}] para o desfazer
  var foto = 0, salvando = 0, nestaVez = 0;

  function esc(t) {
    return String(t == null ? "" : t).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function reais(v) {
    var n = Number(v);
    return v == null || isNaN(n) || !n ? null : "R$ " + n.toLocaleString("pt-BR", { maximumFractionDigits: 0 });
  }
  function json(r) {
    return r.json().catch(function () { return {}; }).then(function (d) {
      if (!r.ok) throw new Error((d.detalhes && [].concat(d.detalhes).join("; ")) || d.erro || ("HTTP " + r.status));
      return d;
    });
  }
  function chamar(metodo, url, corpo) {
    return fetch(url, { method: metodo, credentials: "same-origin", headers: corpo ? { "Content-Type": "application/json" } : {},
                        body: corpo ? JSON.stringify(corpo) : undefined }).then(json);
  }
  function porCodigo(cod) {
    for (var k = 0; k < itens.length; k++) if (itens[k].codigo === cod) return itens[k];
    return null;
  }
  function pendentes() { return itens.filter(function (i) { return !i.resposta; }).length; }
  function visivel() { return !painel.hidden; }

  /* ── a lista de checklists ─────────────────────────────────────────────── */
  function contarNaAba() {
    var n = (lista || []).reduce(function (s, c) { return s + (c.pendentes_disponiveis || 0); }, 0);
    var el = aba.querySelector("[data-ck-conta]");
    if (el) el.textContent = lista ? String(n) : "—";
  }

  function carregarLista() {
    return chamar("GET", "/admin/api/imoveis/checklists").then(function (d) {
      lista = d.checklists || [];
      contarNaAba();
      if (!atual) desenharLista();
    }).catch(function (e) {
      if (!atual) painel.innerHTML = '<p class="ck-erro">Não deu para carregar os checklists: ' + esc(e.message) + "</p>";
    });
  }

  function desenharLista() {
    atual = null;
    painel.innerHTML =
      '<div class="ck-lista-topo"><h2>Checklist rápido</h2>' +
      "<p>Um imóvel por vez, para marcar à mão o que o cadastro não diz. Imóvel novo entra pendente sozinho.</p></div>" +
      '<div class="ck-lista">' + (lista || []).map(function (c) {
        return '<button type="button" class="ck-item" data-ck-abrir="' + esc(c.id) + '">' +
          '<span class="ck-item__titulo">' + esc(c.titulo) + "</span>" +
          '<span class="ck-item__explica">' + esc(c.explica || c.pergunta) + "</span>" +
          '<span class="ck-item__conta"><b>' + (c.pendentes_disponiveis || 0) + "</b> pendentes nos disponíveis · " +
          (c.pendentes || 0) + " em todos (" + (c.total || 0) + ")</span>" +
          '<span class="ck-item__abrir">Abrir →</span></button>';
      }).join("") + "</div>";
  }

  /* ── um checklist aberto ───────────────────────────────────────────────── */
  function abrir(id, comTodos) {
    var c = (lista || []).filter(function (x) { return x.id === id; })[0];
    if (!c) return;
    atual = c; todos = !!comTodos; historico = []; pulados = []; nestaVez = 0;
    painel.innerHTML = '<p class="ck-carregando">Carregando os imóveis…</p>';
    chamar("GET", "/admin/api/imoveis/checklists/" + encodeURIComponent(id) + (todos ? "?todos=1" : "")).then(function (d) {
      if (atual !== c) return;
      itens = d.itens || [];
      montarFila();
      desenhar();
      centrarBotoes(true);
    }).catch(function (e) {
      painel.innerHTML = '<p class="ck-erro">Não deu para carregar: ' + esc(e.message) + "</p>";
    });
  }

  function montarFila() {
    fila = itens.filter(function (i) { return revisar ? !!i.resposta : !i.resposta; }).map(function (i) { return i.codigo; });
    pulados = []; foto = 0;
  }

  function proximo() {
    if (!fila.length && pulados.length) { fila = pulados; pulados = []; }
    return fila.length ? porCodigo(fila[0]) : null;
  }

  function cabecalho() {
    var qDisp = atual.disponiveis || 0, qTodos = atual.total || 0;
    return '<div class="ck-topo">' +
      '<button type="button" class="ck-voltar" data-ck-voltar>← Checklists</button>' +
      '<h2 class="ck-titulo">' + esc(atual.titulo) + "</h2>" +
      '<div class="ck-chips" role="group" aria-label="Quais imóveis">' +
      '<button type="button" class="ck-chip" data-ck-todos="0" aria-pressed="' + !todos + '">Disponíveis (' + qDisp + ")</button>" +
      '<button type="button" class="ck-chip" data-ck-todos="1" aria-pressed="' + todos + '">Todos de ' +
      (atual.publico === "venda" ? "venda" : atual.publico === "locacao" ? "locação" : "todos") + " (" + qTodos + ")</button>" +
      '<button type="button" class="ck-chip" data-ck-revisar aria-pressed="' + revisar + '">Revisar respondidos</button></div>' +
      contaHtml() + "</div>";
  }

  function contaHtml() {
    return '<div class="ck-conta"><b>Faltam ' + pendentes() + "</b>" + (nestaVez ? " · " + nestaVez + " marcados agora" : "") +
      (salvando ? ' · <span class="ck-salvando">salvando…</span>' : "") + "</div>";
  }

  function chipResposta(r) {
    if (!r) return '<span class="ck-resp ck-resp--pend">Pendente</span>';
    return '<span class="ck-resp ' + (/^s/i.test(r) ? "ck-resp--sim" : "ck-resp--nao") + '">' + esc(r) + "</span>";
  }

  function dados(i) {
    var linha = [];
    if (i.quartos) linha.push(i.quartos + " quarto" + (i.quartos > 1 ? "s" : "") + (i.suites ? " (" + i.suites + " suíte" + (i.suites > 1 ? "s" : "") + ")" : ""));
    if (i.banheiros) linha.push(i.banheiros + " banheiro" + (i.banheiros > 1 ? "s" : ""));
    if (i.vagas) linha.push(i.vagas + " vaga" + (i.vagas > 1 ? "s" : ""));
    if (i.area_util) linha.push(String(i.area_util).replace(".", ",") + " m²");
    if (i.andar) linha.push("andar " + i.andar);
    var valores = [];
    if (reais(i.valor_aluguel)) valores.push("Aluguel <b>" + reais(i.valor_aluguel) + "</b>");
    if (reais(i.valor_venda)) valores.push("Venda <b>" + reais(i.valor_venda) + "</b>");
    if (reais(i.taxa_condominio)) valores.push("Condomínio " + reais(i.taxa_condominio));
    return '<div class="ck-dados">' +
      '<div class="ck-dados__linha1"><a class="ck-cod" href="imovel-editar.html?codigo=' + i.codigo + '" target="_blank" rel="noopener" title="Abrir o cadastro">#' + i.codigo + "</a>" +
      '<span class="ck-tipo">' + esc(i.tipo || "Imóvel") + "</span>" +
      '<span class="ck-status">' + esc(i.status || "") + "</span>" + (i.e_parceiro ? '<span class="ck-status">Parceiro</span>' : "") +
      chipResposta(i.resposta) + "</div>" +
      '<div class="ck-nome">' + esc(i.condominio_nome || "Sem condomínio") + "</div>" +
      '<div class="ck-bairro">' + esc(i.bairro || "") + "</div>" +
      (valores.length ? '<div class="ck-valores">' + valores.join(" · ") + "</div>" : "") +
      (linha.length ? '<div class="ck-linha">' + esc(linha.join(" · ")) + "</div>" : "") +
      (i.mobilia ? '<div class="ck-linha">Mobília: ' + esc(i.mobilia) + "</div>" : "") + "</div>";
  }

  /* TODAS AS FOTOS JUNTAS (Pedro, 20/10: "quero já todas as fotos aparecendo juntas em uma galeria adaptativa, não
     quero ter que rolar para o lado, e quando passo o mouse por cima a foto aumenta um pouco"). A grade se ajusta à
     quantidade: poucas fotos ficam grandes, muitas ficam menores, e tudo cabe na largura. Clicar abre em tela cheia. */
  function fotos(i) {
    var f = i.fotos || [];
    if (!f.length) return '<div class="ck-galeria ck-galeria--sem">Sem foto</div>';
    var minimo = f.length <= 2 ? 340 : f.length <= 4 ? 260 : f.length <= 9 ? 200 : 165;
    return '<div class="ck-galeria" style="--ck-min:' + minimo + 'px">' + f.map(function (u, k) {
      return '<button type="button" class="ck-galeria__foto" data-ck-ampliar="' + k + '" aria-label="Ampliar a foto ' + (k + 1) +
        " de " + f.length + '"><img src="' + esc(u) + '" alt="" loading="' + (k < 10 ? "eager" : "lazy") + '" draggable="false"></button>';
    }).join("") + "</div>";
  }

  /* a foto em tela cheia: setas e Esc, sem responder o checklist enquanto está aberta */
  var zoom = null;
  function ampliar(k) {
    var i = fila.length ? porCodigo(fila[0]) : null;
    if (!i || !i.fotos || !i.fotos.length) return;
    if (!zoom) {
      zoom = document.createElement("div");
      zoom.className = "ck-zoom";
      zoom.innerHTML = '<img alt=""><button type="button" class="ck-zoom__seta ck-zoom__seta--ant" data-zoom="-1" aria-label="Foto anterior">‹</button>' +
        '<button type="button" class="ck-zoom__seta ck-zoom__seta--prox" data-zoom="1" aria-label="Próxima foto">›</button>' +
        '<button type="button" class="ck-zoom__fechar" data-zoom="x" aria-label="Fechar">×</button><span class="ck-zoom__n"></span>';
      zoom.addEventListener("click", function (e) {
        var b = e.target.closest("[data-zoom]");
        if (b && b.getAttribute("data-zoom") !== "x") return passarZoom(Number(b.getAttribute("data-zoom")));
        if (b || e.target === zoom) fecharZoom();
      });
      document.body.appendChild(zoom);
    }
    zoom.dataset.k = String(k);
    zoom.hidden = false;
    passarZoom(0);
  }
  function passarZoom(passo) {
    var i = fila.length ? porCodigo(fila[0]) : null;
    if (!zoom || !i || !i.fotos || !i.fotos.length) return;
    var n = i.fotos.length, k = (Number(zoom.dataset.k || 0) + passo + n) % n;
    zoom.dataset.k = String(k);
    zoom.querySelector("img").src = i.fotos[k];
    zoom.querySelector(".ck-zoom__n").textContent = (k + 1) + " / " + n;
  }
  function fecharZoom() { if (zoom) zoom.hidden = true; }
  function zoomAberto() { return zoom && !zoom.hidden; }

  /* OS CONTROLES NO MEIO DA TELA (Pedro, 20/10): ao abrir o checklist a tela desce até os botões, e a cada imóvel
     eles continuam no mesmo lugar (o próximo imóvel pode ter mais ou menos fotos). */
  // a tela desce até o topo do cartão: os dados, todas as fotos e, logo embaixo, os botões
  function centrarBotoes(suave) {
    var c = painel.querySelector(".ck-cartao");
    if (!c || !visivel()) return;
    window.scrollBy({ top: c.getBoundingClientRect().top - 8, behavior: suave ? "smooth" : "auto" });
  }

  function botoes() {
    var op = atual.opcoes || ["Sim", "Não"];
    var simnao = op.length === 2 && /^s/i.test(op[0]) && /^n/i.test(op[1]);
    var meio = '<button type="button" class="ck-btn ck-btn--pular" data-ck-pular title="Pular (↓ ou P)">Pular</button>';
    var resp = simnao
      ? '<button type="button" class="ck-btn ck-btn--nao" data-ck-resp="' + esc(op[1]) + '" title="Não (N ou ←)">✕ ' + esc(op[1].toUpperCase()) + "</button>" + meio +
        '<button type="button" class="ck-btn ck-btn--sim" data-ck-resp="' + esc(op[0]) + '" title="Sim (S ou →)">✓ ' + esc(op[0].toUpperCase()) + "</button>"
      : op.map(function (o, k) {
          return '<button type="button" class="ck-btn ck-btn--op" data-ck-resp="' + esc(o) + '" title="' + (k + 1) + '">' + esc(o) + "</button>";
        }).join("") + meio;
    return '<div class="ck-botoes">' + resp + "</div>" +
      '<div class="ck-rodape"><button type="button" class="ck-desfazer" data-ck-desfazer' + (historico.length ? "" : " disabled") +
      ' title="Desfazer o último (↑ ou Z)">↶ Desfazer o último</button>' +
      '<span class="ck-teclas">S/→ sim · N/← não · ↓ pular · ↑ desfazer · clique na foto para ampliar</span></div>';
  }

  function desenhar() {
    if (!atual) return desenharLista();
    var i = proximo();
    if (!i) {
      var faltamFora = !todos && (atual.pendentes || 0) > 0;
      painel.innerHTML = cabecalho() + '<div class="ck-fim"><p><b>' +
        (revisar ? "Nenhum imóvel respondido aqui ainda." : "Pronto: nenhum pendente " + (todos ? "neste checklist." : "nos disponíveis.")) + "</b></p>" +
        (faltamFora && !revisar ? '<button type="button" class="ck-btn ck-btn--sim" data-ck-todos="1">Continuar com os demais de locação</button>' : "") +
        (historico.length ? '<button type="button" class="ck-desfazer" data-ck-desfazer>↶ Desfazer o último</button>' : "") + "</div>";
      return;
    }
    // a altura muda de um imóvel para o outro: guarda onde os botões estavam e põe de volta no mesmo lugar
    var antes = painel.querySelector(".ck-rodape");          // a linha embaixo dos botões (eles são sticky)
    var topo = antes ? antes.getBoundingClientRect().top : null;
    painel.innerHTML = cabecalho() + '<article class="ck-cartao" data-ck-cartao>' + dados(i) + fotos(i) + "</article>" + botoes();
    var depois = painel.querySelector(".ck-rodape");
    if (topo !== null && depois) window.scrollBy(0, depois.getBoundingClientRect().top - topo);
    // o imóvel novo é mais alto e o topo dele sumiu: o topo do cartão volta para a tela (os botões são sticky)
    var cartao = painel.querySelector(".ck-cartao");
    if (topo !== null && cartao && cartao.getBoundingClientRect().top < 0) centrarBotoes(false);
    preCarregar();
  }

  // as fotos dos próximos já vêm baixando: a grade aparece inteira na hora
  function preCarregar() {
    fila.slice(1, 3).forEach(function (cod) {
      var i = porCodigo(cod);
      (i && i.fotos ? i.fotos.slice(0, 10) : []).forEach(function (u) { var im = new Image(); im.src = u; });
    });
  }

  /* ── responder, pular, desfazer ────────────────────────────────────────── */
  function gravar(i, valor) {
    var corpo = { extras: {} };
    corpo.extras[atual.chave] = valor;
    salvando++;
    return chamar("PUT", "/admin/api/imoveis/" + i.codigo, corpo).then(function () {
      salvando--;
    }, function (e) { salvando--; throw e; });
  }

  function responder(valor) {
    var i = fila.length ? porCodigo(fila[0]) : null;
    if (!i) return;
    var antes = i.resposta || null, ck = atual;
    i.resposta = valor;
    historico.push({ codigo: i.codigo, antes: antes, depois: valor });
    fila.shift(); foto = 0; nestaVez++;
    ajustarConta(ck, i, antes, valor);
    desenhar();
    gravar(i, valor).then(function () { if (atual === ck) atualizarConta(); }).catch(function (e) {
      // não gravou: volta como estava e o imóvel volta para a frente da fila
      i.resposta = antes; nestaVez--;
      ajustarConta(ck, i, valor, antes);
      historico = historico.filter(function (h) { return h.codigo !== i.codigo || h.depois !== valor; });
      if (atual === ck) { fila.unshift(i.codigo); desenhar(); }
      alert("Não salvou o #" + i.codigo + ": " + e.message);
    });
  }

  function pular() {
    if (!fila.length) return;
    pulados.push(fila.shift()); foto = 0;
    desenhar();
  }

  function desfazer() {
    var h = historico.pop();
    if (!h) return;
    var i = porCodigo(h.codigo), ck = atual;
    if (!i) return;
    i.resposta = h.antes; nestaVez = Math.max(0, nestaVez - 1);
    ajustarConta(ck, i, h.depois, h.antes);
    fila = fila.filter(function (c) { return c !== h.codigo; });
    pulados = pulados.filter(function (c) { return c !== h.codigo; });
    fila.unshift(h.codigo); foto = 0;
    desenhar();
    gravar(i, h.antes).then(function () { if (atual === ck) atualizarConta(); })
      .catch(function (e) { alert("Não desfez o #" + i.codigo + ": " + e.message); });
  }

  // a contagem do checklist (lista e aba) acompanha cada resposta sem ir ao servidor
  function ajustarConta(ck, i, de, para) {
    var delta = (!de && para) ? -1 : (de && !para) ? 1 : 0;
    if (!ck || !delta) return;
    ck.pendentes = Math.max(0, (ck.pendentes || 0) + delta);
    if (i.status === "Disponível") ck.pendentes_disponiveis = Math.max(0, (ck.pendentes_disponiveis || 0) + delta);
    contarNaAba();
  }
  function atualizarConta() {
    var el = painel.querySelector(".ck-conta");
    if (el) el.outerHTML = contaHtml();
  }

  /* ── cliques, teclado e arrastar ───────────────────────────────────────── */
  painel.addEventListener("click", function (e) {
    var b = e.target.closest("button");
    if (!b || b.disabled) return;
    if (b.hasAttribute("data-ck-ampliar")) return ampliar(Number(b.getAttribute("data-ck-ampliar")));
    if (b.hasAttribute("data-ck-abrir")) return abrir(b.getAttribute("data-ck-abrir"), false);
    if (b.hasAttribute("data-ck-voltar")) { atual = null; itens = []; carregarLista(); return desenharLista(); }
    if (b.hasAttribute("data-ck-todos")) { var t = b.getAttribute("data-ck-todos") === "1"; if (t !== todos || revisar) { revisar = false; abrir(atual.id, t); } return; }
    if (b.hasAttribute("data-ck-revisar")) { revisar = !revisar; montarFila(); return desenhar(); }
    if (b.hasAttribute("data-ck-resp")) return responder(b.getAttribute("data-ck-resp"));
    if (b.hasAttribute("data-ck-pular")) return pular();
    if (b.hasAttribute("data-ck-desfazer")) return desfazer();
  });

  document.addEventListener("keydown", function (e) {
    if (zoomAberto()) {      // na tela cheia as setas passam a foto; nada responde o checklist
      if (e.key === "Escape") fecharZoom();
      else if (e.key === "ArrowRight") passarZoom(1);
      else if (e.key === "ArrowLeft") passarZoom(-1);
      else return;
      e.preventDefault();
      return;
    }
    if (!visivel() || !atual || e.ctrlKey || e.metaKey || e.altKey) return;
    var alvo = e.target;
    if (alvo && (alvo.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(alvo.tagName))) return;
    var op = atual.opcoes || ["Sim", "Não"], k = e.key;
    var acao = null;
    if (k === "ArrowRight" || k === "s" || k === "S") acao = function () { responder(op[0]); };
    else if (k === "ArrowLeft" || k === "n" || k === "N") acao = function () { responder(op[1] || op[0]); };
    else if (k === "ArrowDown" || k === "p" || k === "P") acao = pular;
    else if (k === "ArrowUp" || k === "z" || k === "Z") acao = desfazer;
    else if (/^[1-9]$/.test(k) && op[Number(k) - 1]) acao = function () { responder(op[Number(k) - 1]); };
    if (!acao) return;
    e.preventDefault();
    acao();
  });

  // arrastar o cartão (celular): para a direita = a 1ª opção (Sim), para a esquerda = a 2ª (Não)
  var arrasto = null;
  painel.addEventListener("pointerdown", function (e) {
    var c = e.target.closest("[data-ck-cartao]");
    // arrastar por cima das fotos também vale (elas são botões só para ampliar)
    if (!c || e.target.closest("button:not(.ck-galeria__foto), a") || e.pointerType === "mouse") return;
    arrasto = { x: e.clientX, y: e.clientY, el: c };
  });
  painel.addEventListener("pointermove", function (e) {
    if (!arrasto) return;
    var dx = e.clientX - arrasto.x;
    arrasto.el.style.transform = "translateX(" + dx + "px) rotate(" + (dx / 30) + "deg)";
    arrasto.el.classList.toggle("ck-cartao--sim", dx > 90);
    arrasto.el.classList.toggle("ck-cartao--nao", dx < -90);
  });
  function soltar(e) {
    if (!arrasto) return;
    var dx = e.clientX - arrasto.x, dy = Math.abs(e.clientY - arrasto.y), el = arrasto.el;
    arrasto = null;
    el.style.transform = "";
    var op = atual && (atual.opcoes || ["Sim", "Não"]);
    if (!op || Math.abs(dx) < 90 || dy > Math.abs(dx)) { el.classList.remove("ck-cartao--sim", "ck-cartao--nao"); return; }
    responder(dx > 0 ? op[0] : (op[1] || op[0]));
  }
  painel.addEventListener("pointerup", soltar);
  painel.addEventListener("pointercancel", function () {
    if (arrasto) { arrasto.el.style.transform = ""; arrasto = null; }
  });

  aba.addEventListener("click", function () { if (!lista) carregarLista(); else if (!atual) desenharLista(); });
  carregarLista();
})();
