/* ==========================================================================
   Imob Easy — Captação OLX (28/09/2026)

   Pedro: "la na aba captação quero que crie tabs, a atual que tá Captação
   deixa Captação WhatsApp e cria uma outra aba Captação OLX... eu colo um link
   da olx e ele importa as fotos e todos os dados... vai carregar uma barrinha
   e colocar todos os dados que ele conseguiu coletar em um espelho e as fotos,
   e aguardar o gatilho humano clicar em cadastrar, mas quero que isso fique
   pré-cadastrado automaticamente".

   COMO O ANÚNCIO CHEGA: a OLX bloqueia o nosso servidor, e isso não se
   contorna. Quem lê o anúncio é o NAVEGADOR de quem está na página da OLX,
   pelo favorito "Enviar para Imob Easy" (o `botaoDaOlx` abaixo). Ele abre esta
   página com o anúncio no endereço (#olx=...), e daqui vai para a API:
     1. POST api/olx/importar   -> o pré-cadastro (Rascunho, fora do site e da Nay)
     2. POST api/olx/<cod>/foto -> uma foto por vez: é isso que anda a barrinha
     3. Cadastrar = PUT api/imoveis/<cod> {status: "Disponível"} (regra de sempre)
   ========================================================================== */
(function () {
  "use strict";

  function $(id) { return document.getElementById(id); }
  function esc(txt) {
    return String(txt == null ? "" : txt)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }
  function reais(v) {
    if (v == null || v === "") return "";
    return Number(v).toLocaleString("pt-BR", { style: "currency", currency: "BRL", maximumFractionDigits: 0 });
  }
  var COR = {
    "Disponível": ["#2f7d58", "#e8f7f0"], "Rascunho": ["#5d566a", "#efedf3"], "Alugado": ["#6d28d9", "#f1eaff"],
    "Vendido": ["#5d566a", "#efedf3"], "Em revisão": ["#a8662f", "#fdf2ea"], "Removido": ["#b42323", "#fdeef1"],
    "Indisponível": ["#b42323", "#fdeef1"], "Arquivado": ["#5d566a", "#efedf3"]
  };
  function pilula(status) {
    var c = COR[status] || COR.Rascunho;
    var texto = status === "Rascunho" ? "Rascunho · fora do site e da Nay" : status === "Disponível" ? "Disponível · no site e na Nay" : status;
    return '<span class="olx-pilula" style="--sc:' + c[0] + ";--sb:" + c[1] + '">' + esc(texto || "—") + "</span>";
  }

  /* ---- as duas abas do topo ------------------------------------------------ */
  var abas = [$("aba-whatsapp"), $("aba-olx")];
  if (!abas[0] || !abas[1]) return;
  var listaCarregada = false;
  function mostrar(qual) {
    abas.forEach(function (b) {
      var sim = b.id === "aba-" + qual;
      b.setAttribute("aria-selected", sim ? "true" : "false");
      b.tabIndex = sim ? 0 : -1;
      $(b.getAttribute("aria-controls")).hidden = !sim;
    });
    if (qual === "olx" && !listaCarregada) { listaCarregada = true; carregarLista(); }
  }
  abas.forEach(function (b, k) {
    b.addEventListener("click", function () {
      var qual = b.id.slice(4);
      mostrar(qual);
      history.replaceState(null, "", location.pathname + location.search + (qual === "olx" ? "#olx" : ""));
    });
    b.addEventListener("keydown", function (e) {
      if (e.key !== "ArrowRight" && e.key !== "ArrowLeft") return;
      var outra = abas[(k + 1) % 2];
      outra.focus();
      outra.click();
    });
  });

  /* ---- o favorito "Enviar para Imob Easy" ------------------------------------
     Roda NA PÁGINA DA OLX, no navegador de quem clica. Sem comentário dentro da
     função: ela vira o endereço do favorito. Lê o anúncio do próprio HTML da
     página (o bloco `initial-data`, ou o `__NEXT_DATA__` se a OLX mudar) e abre
     esta tela com ele no endereço. */
  function botaoDaOlx(destino) {
    try {
      var fontes = [];
      var a1 = document.getElementById("initial-data");
      if (a1) fontes.push(a1.getAttribute("data-json"));
      var a2 = document.getElementById("__NEXT_DATA__");
      if (a2) fontes.push(a2.textContent);
      var achar = function (n, p) {
        if (p > 9 || !n || typeof n !== "object") return null;
        if (Array.isArray(n)) {
          for (var i = 0; i < n.length && i < 20; i++) { var a = achar(n[i], p + 1); if (a) return a; }
          return null;
        }
        if ("subject" in n && ("images" in n || "properties" in n)) return n;
        for (var k in n) { if (n[k] && typeof n[k] === "object") { var b = achar(n[k], p + 1); if (b) return b; } }
        return null;
      };
      var ad = null;
      for (var f = 0; f < fontes.length && !ad; f++) { try { ad = achar(JSON.parse(fontes[f]), 0); } catch (e) { ad = null; } }
      if (!ad) { alert("Não achei o anúncio nesta página. Abra a página do imóvel na OLX e clique de novo."); return; }
      var o = {
        url: location.href.split("#")[0].split("?")[0],
        anuncio: {
          listId: ad.listId, subject: ad.subject, body: ad.body,
          priceValue: ad.priceValue, priceLabel: ad.priceLabel, location: ad.location,
          properties: (ad.properties || []).map(function (p) { return { name: p.name, label: p.label, value: p.value }; }),
          images: (ad.images || []).map(function (i) { return typeof i === "string" ? i : (i.original || i.originalAlternative || i.url); }).filter(Boolean)
        }
      };
      var alvo = destino + "#olx=" + encodeURIComponent(JSON.stringify(o));
      var janela = window.open(alvo, "_blank");
      if (!janela) location.href = alvo;
    } catch (e) {
      alert("Não consegui ler o anúncio: " + e.message);
    }
  }
  var favorito = $("olx-favorito");
  favorito.href = "javascript:" + encodeURIComponent("(" + botaoDaOlx.toString() + ")(" +
    JSON.stringify(location.origin + location.pathname) + ")");
  favorito.addEventListener("click", function (e) {
    e.preventDefault();
    $("olx-dica").innerHTML = "Esse botão não funciona aqui: <strong>arraste</strong> ele para a barra de favoritos e use na página do anúncio da OLX.";
  });

  /* ---- colar o link: abre o anúncio para o favorito ler ------------------- */
  $("olx-form").addEventListener("submit", function (e) {
    e.preventDefault();
    var link = $("olx-link").value.trim();
    if (!/^https?:\/\/([a-z0-9-]+\.)*olx\.com\.br\//i.test(link)) {
      $("olx-dica").textContent = "Esse link não é de um anúncio da OLX.";
      return;
    }
    // o host regional entrega o anúncio; o www redireciona para a página inicial
    link = link.replace(/^http:/i, "https:").replace(/^https:\/\/www\.olx\.com\.br\//i, "https://am.olx.com.br/");
    window.open(link, "_blank", "noopener");
    $("olx-dica").innerHTML = "Abri o anúncio numa aba nova. Lá, clique em <strong>Enviar para Imob Easy</strong> na barra de favoritos.";
  });

  /* ---- a barrinha ---------------------------------------------------------- */
  function progresso(pct, texto, tipo) {
    var caixa = $("olx-progresso");
    caixa.hidden = false;
    caixa.className = "olx-progresso" + (tipo ? " olx-progresso--" + tipo : "");
    pct = Math.max(3, Math.min(100, pct));
    $("olx-barra").style.width = pct + "%";
    $("olx-barra").parentNode.setAttribute("aria-valuenow", String(Math.round(pct)));
    $("olx-etapa").textContent = texto;
  }

  function enviar(url, metodo, corpo) {
    return fetch(url, {
      method: metodo, credentials: "same-origin",
      headers: { "Content-Type": "application/json" }, body: JSON.stringify(corpo)
    }).then(function (r) {
      if (r.status === 401) throw new Error("a senha do painel não foi aceita — recarregue a página e entre de novo");
      return r.json().catch(function () { return {}; }).then(function (d) { return { ok: r.ok, dados: d }; });
    });
  }

  /* ---- importar: pré-cadastro, depois as fotos uma a uma -------------------- */
  function importar(pacote) {
    $("olx-espelho").innerHTML = "";
    progresso(8, "Lendo o anúncio…");
    enviar("api/olx/importar", "POST", pacote).then(function (res) {
      if (!res.ok) throw new Error(res.dados.erro || "a importação falhou");
      var d = res.dados;
      var fotos = d.fotos || [];
      progresso(20, (d.novo ? "Pré-cadastro gravado (código " + d.codigo + ")." : "Esse anúncio já estava pré-cadastrado (código " + d.codigo + ").") +
        (fotos.length ? " Baixando as fotos…" : ""));
      var baixadas = 0, falhas = 0;
      var fila = Promise.resolve();
      fotos.forEach(function (url, k) {
        fila = fila.then(function () {
          progresso(20 + 78 * k / fotos.length, "Baixando foto " + (k + 1) + " de " + fotos.length + "…");
          return enviar("api/olx/" + d.codigo + "/foto", "POST", { url: url, ordem: k + 1 })
            .then(function (r) { if (r.ok && r.dados.ok) baixadas++; else falhas++; })
            .catch(function () { falhas++; });
        });
      });
      return fila.then(function () {
        var total = baixadas + (d.fotos_ja || 0);
        progresso(100, "Pronto: " + (d.novo ? "pré-cadastrado" : "já estava pré-cadastrado") + " com " + total + " foto" + (total === 1 ? "" : "s") +
          (falhas ? " — " + falhas + " não baixaram" : "") + ". Confira e clique em Cadastrar.", falhas ? "aviso" : "ok");
        desenharEspelho(d.codigo, d);
        carregarLista();
      });
    }).catch(function (erro) {
      progresso(100, "Não deu certo: " + erro.message, "erro");
    });
  }

  /* ---- o proprietário: o último passo (a OLX não traz esses dados) ---------- */
  function campoDono(k, rotulo, tipo) {
    return '<label class="olx-dono__campo">' + rotulo +
      '<input class="entrada" data-dono="' + k + '" type="' + (tipo || "text") + '"' + (tipo === "tel" ? ' inputmode="tel"' : "") + "></label>";
  }
  function donoHtml(codigo) {
    return '<section class="olx-dono">' +
      '<h4>Último passo: o proprietário <small>a OLX não traz esses dados</small></h4>' +
      '<div class="olx-dono__campos">' +
        campoDono("nome", "Nome") + campoDono("telefone", "Telefone / WhatsApp", "tel") + campoDono("email", "E-mail", "email") +
        campoDono("documento", "CPF ou CNPJ") +
        '<label class="olx-dono__campo">Tratamento<select class="entrada" data-dono="tratamento"><option value="">—</option>' +
          "<option>Sr.</option><option>Sra.</option><option>Dr.</option><option>Dra.</option></select></label>" +
      "</div>" +
      '<p class="olx-nota">É por este telefone que a Nay fala com o dono para marcar visita. Se ele já é dono de outro imóvel, o imóvel é ligado a ele.</p>' +
      '<div class="olx-dono__acoes"><button class="btn-neutro" type="button" data-salvar-dono="' + esc(codigo) + '">Salvar proprietário</button>' +
        '<span class="olx-nota" data-dono-status role="status"></span></div>' +
      "</section>";
  }
  function dadosDono(secao) {
    var d = {};
    secao.querySelectorAll("[data-dono]").forEach(function (el) { d[el.getAttribute("data-dono")] = String(el.value || "").trim() || null; });
    return d;
  }
  function preencherDono(secao, p) {
    secao.querySelectorAll("[data-dono]").forEach(function (el) {
      var k = el.getAttribute("data-dono");
      el.value = p && p[k] != null ? p[k] : "";
    });
  }
  function recadoDoDono(p, antes) {
    if (!p) return "";
    var outros = p.outros_imoveis || [];
    return p.id !== antes && outros.length ? " Esse proprietário já era dono de " + outros.join(", ") + ": o imóvel foi ligado a ele." : "";
  }
  function salvarDono(botao) {
    var codigo = botao.getAttribute("data-salvar-dono");
    var secao = botao.closest(".olx-dono");
    var recado = secao.querySelector("[data-dono-status]");
    var antes = secao.getAttribute("data-dono-id");
    botao.disabled = true;
    recado.textContent = "Salvando…";
    enviar("api/imoveis/" + encodeURIComponent(codigo), "PUT", { proprietario: dadosDono(secao) }).then(function (res) {
      botao.disabled = false;
      if (!res.ok) throw new Error([].concat(res.dados.detalhes || []).join("; ") || res.dados.erro || "erro");
      var p = res.dados.proprietario;
      preencherDono(secao, p);
      secao.setAttribute("data-dono-id", p ? p.id : "");
      recado.textContent = (p ? "Proprietário salvo." : "Nada para salvar.") + recadoDoDono(p, antes ? Number(antes) : null);
      carregarLista();
    }).catch(function (erro) {
      botao.disabled = false;
      recado.textContent = "Não salvou: " + erro.message;
    });
  }

  /* ---- o espelho: tudo o que veio, antes do clique -------------------------- */
  // Guardada para o espelho poder se redesenhar sozinho depois de tirar uma
  // foto, sem perder o que veio da importação (título, url, o que falta).
  var ultimaImportacao = null;

  function desenharEspelho(codigo, importacao) {
    ultimaImportacao = importacao || ultimaImportacao;
    var alvo = $("olx-espelho");
    alvo.innerHTML = '<p class="olx-nota">Montando o espelho…</p>';
    Promise.all([
      fetch(window.API_BASE + "/api/imoveis/" + codigo).then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); }),
      fetch(window.API_BASE + "/api/imoveis/" + codigo + "/fotos").then(function (r) { return r.ok ? r.json() : { fotos: [] }; }).catch(function () { return { fotos: [] }; })
    ]).then(function (par) {
      var i = par[0];
      var fotos = (par[1].fotos || []).map(function (f) { return typeof f === "string" ? f : (f.url || f.arquivo); }).filter(Boolean);
      var imp = ultimaImportacao || {};
      var dado = function (rotulo, valor) {
        return valor == null || valor === "" ? "" : '<div class="olx-dado"><dt>' + esc(rotulo) + "</dt><dd>" + esc(valor) + "</dd></div>";
      };
      // as características em dois grupos, como a OLX mostra
      var carac = Array.isArray(i.caracteristicas) ? i.caracteristicas : [];
      var extras = i.extras || {};
      var doCondominio = String(extras["caracteristicas do condominio"] || "").split(",")
        .map(function (x) { return x.trim(); }).filter(function (x) { return x && carac.indexOf(x) >= 0; });
      var doImovel = carac.filter(function (x) { return doCondominio.indexOf(x) < 0; });
      var grupo = function (titulo, itens) {
        return itens.length ? '<div class="olx-espelho__grupo"><h4>' + titulo + '</h4><div class="olx-espelho__carac">' +
          itens.map(function (c) { return '<span class="olx-chip">' + esc(c) + "</span>"; }).join("") + "</div></div>" : "";
      };
      var falta = (imp.falta || []).map(function (f) { return '<span class="olx-falta__item">' + esc(f.rotulo || f.campo) + "</span>"; }).join("");
      var duvidas = (imp.duvidas || []).map(function (d) { return "<li>" + esc(d.aviso) + "</li>"; }).join("");
      var urlOlx = imp.url || "";
      alvo.innerHTML =
        '<article class="olx-espelho">' +
          '<header class="olx-espelho__topo"><div>' +
            '<h3 class="olx-espelho__titulo">Pré-cadastro <span class="olx-codigo">' + esc(i.codigo) + "</span>" +
              (imp.titulo ? " · " + esc(imp.titulo) : "") + "</h3>" +
            pilula(i.status) + "</div></header>" +
          // O X EM CADA FOTO (Tel, 30/09): a OLX manda planta, fachada repetida
          // e foto ruim. Só sai enquanto é Rascunho -- depois de cadastrado o
          // imóvel já está no site e na Nay, e tirar foto ali é na tela de
          // edição, não aqui.
          (fotos.length ? '<div class="olx-espelho__fotos">' + fotos.slice(0, 13).map(function (u, k) {
              return '<figure class="olx-foto' + (k ? "" : " olx-espelho__capa") + '">' +
                '<img src="' + esc(u) + '" alt="' + (k ? "" : "Foto principal") + '" loading="lazy">' +
                (i.status === "Rascunho"
                  ? '<button class="olx-foto__x" type="button" title="Tirar esta foto"' +
                    ' aria-label="Tirar esta foto do cadastro"' +
                    ' data-apagar-foto="' + esc(u) + '" data-codigo="' + esc(i.codigo) + '">&times;</button>'
                  : "") +
                "</figure>";
            }).join("") + (fotos.length > 13 ? '<span class="olx-espelho__mais">+' + (fotos.length - 13) + "</span>" : "") + "</div>"
            : '<p class="olx-nota olx-espelho__semfoto">Nenhuma foto veio.</p>') +
          '<dl class="olx-espelho__dados">' +
            dado("Tipo", i.tipo) + dado("Bairro", i.bairro) + dado("Rua", i.logradouro) + dado("Cidade", i.cidade) +
            dado("Área útil", i.area_util ? i.area_util + " m²" : "") + dado("Quartos", i.quartos) + dado("Suítes", i.suites) +
            dado("Banheiros", i.banheiros) + dado("Vagas", i.vagas) + dado("Aluguel", reais(i.valor_aluguel)) +
            dado("Venda", reais(i.valor_venda)) + dado("Condomínio", reais(i.taxa_condominio)) + dado("IPTU", reais(i.iptu)) +
            dado("Mobília", i.mobilia) + dado("Incluso no aluguel", extras["incluso no aluguel"]) +
          "</dl>" +
          (carac.length ? '<div class="olx-espelho__grupos">' + grupo("Características do imóvel", doImovel) +
            grupo("Características do condomínio", doCondominio) + "</div>" : "") +
          (i.descricao ? '<details class="olx-espelho__desc"><summary>Descrição do anúncio</summary><p>' + esc(i.descricao).replace(/\n/g, "<br>") + "</p></details>" : "") +
          (falta ? '<div class="olx-falta"><b>Falta preencher</b>' + falta + "</div>" : "") +
          (duvidas ? '<div class="olx-duvidas"><b>Confira antes de cadastrar</b><ul>' + duvidas + "</ul></div>" : "") +
          donoHtml(i.codigo) +
          '<div class="olx-espelho__acoes">' +
            (i.status === "Rascunho"
              ? '<button class="btn-azul" type="button" data-cadastrar="' + esc(i.codigo) + '">Cadastrar — vai para o site e para a Nay</button>'
              : "") +
            '<a class="btn-neutro" href="imovel-editar.html?codigo=' + encodeURIComponent(i.codigo) + '">Editar antes</a>' +
            (urlOlx ? '<a class="olx-link-externo" href="' + esc(urlOlx) + '" target="_blank" rel="noopener">Ver na OLX</a>' : "") +
            '<span class="olx-nota" data-cadastro-status role="status"></span>' +
          "</div>" +
        "</article>";
      alvo.scrollIntoView({ behavior: "smooth", block: "start" });
      // o dono que o imóvel já tiver (a parte privada, com a senha do painel)
      fetch("api/imoveis/" + encodeURIComponent(i.codigo) + "/privado", { credentials: "same-origin" })
        .then(function (r) { return r.ok ? r.json() : null; })
        .then(function (d) {
          var secao = alvo.querySelector(".olx-dono");
          if (!secao || !d) return;
          preencherDono(secao, d.proprietario);
          secao.setAttribute("data-dono-id", d.proprietario ? d.proprietario.id : "");
        })
        .catch(function () {});
    }).catch(function () {
      alvo.innerHTML = '<p class="olx-nota olx-nota--erro">Não consegui abrir o pré-cadastro ' + esc(codigo) + ".</p>";
    });
  }

  /* ---- o gatilho humano ----------------------------------------------------- */
  function cadastrar(botao) {
    var codigo = botao.getAttribute("data-cadastrar");
    var recado = botao.parentNode.querySelector("[data-cadastro-status]");
    var cartao = botao.closest(".olx-espelho, .olx-item");
    var secaoDono = cartao && cartao.querySelector(".olx-dono");
    var corpo = { status: "Disponível" };
    // SEM DONO, AVISA (Pedro: "quando clica em salvar ele notifica para pôr os
    // dados do proprietário"): o primeiro clique mostra o que falta; o segundo
    // cadastra assim mesmo.
    var semDono;
    if (secaoDono) {
      var dono = dadosDono(secaoDono);
      semDono = !dono.nome && !dono.telefone;
      if (!semDono) corpo.proprietario = dono;
    } else {
      semDono = botao.getAttribute("data-tem-dono") === "false";
    }
    if (semDono && botao.getAttribute("data-sem-dono-ok") !== "sim") {
      botao.setAttribute("data-sem-dono-ok", "sim");
      botao.textContent = "Cadastrar sem o proprietário";
      if (recado) recado.innerHTML = "<b>Falta o proprietário</b> (a OLX não traz). " +
        (secaoDono ? "Preencha acima" : "Abra o espelho para preencher") + ", ou clique de novo para cadastrar sem ele.";
      if (secaoDono) {
        secaoDono.classList.remove("olx-dono--chamando");
        void secaoDono.offsetWidth;
        secaoDono.classList.add("olx-dono--chamando");
        secaoDono.scrollIntoView({ behavior: "smooth", block: "center" });
        var nome = secaoDono.querySelector('[data-dono="nome"]');
        if (nome) setTimeout(function () { nome.focus({ preventScroll: true }); }, 350);
      }
      return;
    }
    botao.disabled = true;
    botao.textContent = "Cadastrando…";
    enviar("api/imoveis/" + encodeURIComponent(codigo), "PUT", corpo).then(function (res) {
      if (!res.ok) throw new Error([].concat(res.dados.detalhes || []).join("; ") || res.dados.erro || "erro");
      botao.textContent = "Cadastrado";
      if (secaoDono && "proprietario" in res.dados) preencherDono(secaoDono, res.dados.proprietario);
      if (recado) recado.textContent = "Pronto: o " + codigo + " já está no site e na Nay." +
        (secaoDono ? recadoDoDono(res.dados.proprietario, Number(secaoDono.getAttribute("data-dono-id")) || null) : "");
      var topo = botao.closest(".olx-espelho, .olx-item");
      var pill = topo && topo.querySelector(".olx-pilula");
      if (pill) pill.outerHTML = pilula("Disponível");
      carregarLista();
    }).catch(function (erro) {
      botao.disabled = false;
      botao.textContent = cartao && cartao.classList.contains("olx-item") ? "Cadastrar" : "Cadastrar — vai para o site e para a Nay";
      if (recado) recado.textContent = "Não cadastrou: " + erro.message;
    });
  }

  /* ---- a lista dos pré-cadastrados ------------------------------------------ */
  function carregarLista() {
    fetch("api/olx/importados", { credentials: "same-origin" })
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (d) {
        var itens = d.itens || [];
        if (!itens.length) {
          $("olx-lista").innerHTML = '<p class="olx-nota">Nenhum anúncio importado ainda.</p>';
          return;
        }
        $("olx-lista").innerHTML = itens.map(function (i) {
          var valor = i.valor_aluguel ? reais(i.valor_aluguel) + "/mês" : reais(i.valor_venda);
          return '<article class="olx-item">' +
            (i.capa ? '<img class="olx-item__capa" src="' + esc(i.capa) + '" alt="" loading="lazy">' : '<span class="olx-item__capa olx-item__capa--vazia">sem foto</span>') +
            '<div class="olx-item__texto"><b><span class="olx-codigo">' + esc(i.codigo) + "</span> " + esc(i.titulo || "") + "</b>" +
              "<small>" + esc([i.tipo, i.bairro, i.quartos ? i.quartos + " quartos" : "", valor].filter(Boolean).join(" · ")) + "</small>" +
              "<small>" + esc((i.fotos || 0) + " foto" + (i.fotos === 1 ? "" : "s") +
                (i.criado_em ? " · importado em " + new Date(i.criado_em).toLocaleDateString("pt-BR") : "")) + "</small></div>" +
            '<div class="olx-item__selos">' + pilula(i.status) +
              (i.tem_proprietario ? "" : '<span class="olx-sem-dono">sem proprietário</span>') + "</div>" +
            '<div class="olx-item__acoes">' +
              '<button class="btn-neutro" type="button" data-espelho="' + esc(i.codigo) + '" data-url="' + esc(i.olx_url || "") + '" data-titulo="' + esc(i.titulo || "") + '">' +
                (i.tem_proprietario ? "Ver espelho" : "Ver espelho e pôr o proprietário") + "</button>" +
              (i.status === "Rascunho" ? '<button class="btn-azul" type="button" data-cadastrar="' + esc(i.codigo) + '" data-tem-dono="' +
                (i.tem_proprietario ? "true" : "false") + '">Cadastrar</button>' : "") +
              '<a class="btn-neutro" href="imovel-editar.html?codigo=' + encodeURIComponent(i.codigo) + '">Editar</a>' +
              '<span class="olx-nota" data-cadastro-status role="status"></span>' +
            "</div></article>";
        }).join("");
      })
      .catch(function (erro) {
        $("olx-lista").innerHTML = '<p class="olx-nota olx-nota--erro">Não consegui carregar a lista' +
          (erro === 401 ? " (a senha do painel não foi aceita)." : ".") + "</p>";
      });
  }

  /* ---- tirar uma foto que não deve subir ------------------------------------ */
  function apagarFoto(botao) {
    if (botao.disabled) return;
    var url = botao.getAttribute("data-apagar-foto");
    var codigo = botao.getAttribute("data-codigo");
    var figura = botao.closest(".olx-foto");
    botao.disabled = true;
    if (figura) figura.classList.add("olx-foto--saindo");
    enviar("api/olx/" + encodeURIComponent(codigo) + "/foto", "DELETE", { url: url })
      .then(function (res) {
        if (!res.ok) throw new Error(res.dados.erro || "não deu para tirar a foto");
        // Redesenha em vez de só sumir com o elemento: o espelho mostra 13 e um
        // "+N", e tirar uma sem redesenhar deixaria essa conta mentindo.
        desenharEspelho(codigo, ultimaImportacao);
      })
      .catch(function (erro) {
        botao.disabled = false;
        if (!figura) return;
        figura.classList.remove("olx-foto--saindo");
        figura.classList.add("olx-foto--erro");
        figura.title = erro.message;
      });
  }

  document.addEventListener("click", function (e) {
    var af = e.target.closest ? e.target.closest("[data-apagar-foto]") : null;
    if (af) { apagarFoto(af); return; }
    var b = e.target.closest ? e.target.closest("[data-cadastrar]") : null;
    if (b) { cadastrar(b); return; }
    var sd = e.target.closest ? e.target.closest("[data-salvar-dono]") : null;
    if (sd) { salvarDono(sd); return; }
    var v = e.target.closest ? e.target.closest("[data-espelho]") : null;
    if (v) {
      desenharEspelho(v.getAttribute("data-espelho"), { url: v.getAttribute("data-url"), titulo: v.getAttribute("data-titulo") });
    }
  });

  /* ---- chegou pelo favorito? ------------------------------------------------ */
  (function lerDoEndereco() {
    var h = location.hash;
    if (h.indexOf("#olx=") !== 0) {
      if (h === "#olx") mostrar("olx");
      return;
    }
    var pacote = null;
    try { pacote = JSON.parse(decodeURIComponent(h.slice(5))); } catch (erro) { pacote = null; }
    // recarregar a página não importa de novo
    history.replaceState(null, "", location.pathname + location.search + "#olx");
    mostrar("olx");
    if (!pacote || !pacote.anuncio) {
      progresso(100, "O anúncio chegou incompleto. Clique no botão de novo, na página da OLX.", "erro");
      return;
    }
    importar(pacote);
  })();
})();
