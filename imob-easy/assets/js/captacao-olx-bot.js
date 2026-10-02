/* ==========================================================================
   Imob Easy — Imóveis da OLX Bot (02/10/2026)

   Pedro: "esses imóveis vão vir para uma nova aba no site... criando uma aba ao
   lado de Captação OLX, Imóveis da OLX Bot... vai armazenar esses imóveis para
   aprovação manual humana".

   O grokbot manda o imóvel pelo CRM (/api/public/imovel-cadastro) com o
   corretor, o link e a autorização do proprietário; o envio fica numa caixa de
   espera e aparece aqui. Nada vira imóvel sozinho:

     Aprovar   -> POST api/olx-bot/<id>/aprovar: cria o PRÉ-CADASTRO (Rascunho,
                  fora do site e da Nay). Depois esta tela grava o proprietário
                  (PUT api/imoveis/<cod>) e baixa as fotos uma a uma
                  (POST api/olx/<cod>/foto) -- as mesmas rotas da Captação OLX.
                  O imóvel passa a aparecer em Captação OLX › Pré-cadastrados,
                  onde está o botão Cadastrar. Aprovar NÃO publica.
     Descartar -> POST api/olx-bot/<id>/descartar, com o motivo. Se o bot mandar
                  o mesmo anúncio de novo, recebe o motivo de volta.

   Quem troca de aba é o captacao-olx.js; ele avisa por "olxbot:mostrar".
   ========================================================================== */
(function () {
  "use strict";

  function $(id) { return document.getElementById(id); }
  var lista = $("bot-lista");
  if (!lista) return;

  function esc(txt) {
    return String(txt == null ? "" : txt)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }
  function reais(v) {
    if (v == null || v === "" || isNaN(Number(v))) return "";
    return Number(v).toLocaleString("pt-BR", { style: "currency", currency: "BRL", maximumFractionDigits: 0 });
  }
  function numero(v) {
    if (v == null || v === "") return null;
    if (typeof v === "number") return v;
    var t = String(v).replace(/[^0-9.,]/g, "");
    if (/^\d+(\.\d{1,2})?$/.test(t)) return Number(t);
    if (/^(\d{1,3}(\.\d{3})+|\d+)(,\d{1,2})?$/.test(t)) return Number(t.replace(/\./g, "").replace(",", "."));
    return null;
  }
  function quando(iso) {
    if (!iso) return "";
    var d = new Date(iso);
    return isNaN(d) ? "" : d.toLocaleDateString("pt-BR") + " " + d.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" });
  }
  function linkSeguro(url) { return /^https?:\/\//i.test(String(url || "")) ? String(url) : ""; }

  function enviar(url, metodo, corpo) {
    return fetch(url, {
      method: metodo, credentials: "same-origin",
      headers: { "Content-Type": "application/json" }, body: JSON.stringify(corpo || {})
    }).then(function (r) {
      if (r.status === 401) throw new Error("a senha do painel não foi aceita — recarregue a página e entre de novo");
      return r.json().catch(function () { return {}; }).then(function (d) { return { ok: r.ok, dados: d }; });
    });
  }

  var estado = "pendente";


  function campo(rotulo, valor) {
    return valor == null || valor === "" ? "" : "<div><span>" + esc(rotulo) + ":</span> " + esc(valor) + "</div>";
  }

  function cartao(i) {
    var d = i.dados || {};
    var venda = numero(d.preco_venda), aluguel = numero(d.preco_aluguel), preco = numero(d.preco);
    var fin = String(d.finalidade || "").toLowerCase();
    var valores = [venda ? reais(venda) + " (venda)" : "", aluguel ? reais(aluguel) + "/mês" : "",
                   !venda && !aluguel && preco ? reais(preco) + (fin.indexOf("alug") >= 0 || fin.indexOf("loca") >= 0 ? "/mês" : fin ? " (" + fin + ")" : "") : ""]
      .filter(Boolean).join(" · ");
    var titulo = d.titulo || [d.tipo, d.condominio_nome, d.bairro].filter(Boolean).join(" · ") || "Imóvel sem título";
    var link = linkSeguro(i.link);
    var carac = [].concat(Array.isArray(d.caracteristicas) ? d.caracteristicas : [], Array.isArray(d.caracteristicas_condominio) ? d.caracteristicas_condominio : []);
    var fotos = (i.fotos || []).filter(linkSeguro);
    var parecidos = (i.candidatos || []).filter(function (c) { return Number(c.score) >= 45; });

    var decisao = "";
    if (i.estado === "pendente") {
      decisao =
        '<button class="btn-azul" type="button" data-bot-aprovar="' + esc(i.id) + '">Aprovar (vira pré-cadastro)</button>' +
        '<input class="entrada bot-motivo" type="text" maxlength="300" placeholder="Motivo, se for descartar" aria-label="Motivo do descarte" data-bot-motivo>' +
        '<button class="btn-neutro" type="button" data-bot-descartar="' + esc(i.id) + '">Descartar</button>';
    } else if (i.estado === "aprovado") {
      decisao = '<span class="olx-nota">Aprovado em ' + esc(quando(i.decidido_em)) + (i.codigo ? " · virou o imóvel <b>" + esc(i.codigo) + "</b>" : "") + "</span>" +
        (i.codigo ? '<a class="btn-neutro" href="imovel-editar.html?codigo=' + encodeURIComponent(i.codigo) + '">Abrir no editor</a>' : "");
    } else {
      decisao = '<span class="olx-nota">Descartado em ' + esc(quando(i.decidido_em)) + (i.motivo ? " · " + esc(i.motivo) : "") + "</span>";
    }

    return '<article class="olx-item bot-item" data-bot-item="' + esc(i.id) + '">' +
      '<div class="bot-item__topo"><b>' + esc(titulo) + "</b>" +
        (link ? '<a href="' + esc(link) + '" target="_blank" rel="noopener noreferrer">Ver o anúncio na OLX ↗</a>' : "") + "</div>" +
      '<div class="bot-grade">' +
        campo("Valor", valores) + campo("Tipo", d.tipo) + campo("Bairro", d.bairro) + campo("Condomínio", d.condominio_nome) +
        campo("Endereço", [d.endereco, d.numero, d.complemento].filter(Boolean).join(", ")) + campo("CEP", d.cep) +
        campo("Área", d.area_m2 ? d.area_m2 + " m²" : "") + campo("Quartos", d.quartos) + campo("Suítes", d.suites) +
        campo("Banheiros", d.banheiros) + campo("Vagas", d.vagas) + campo("Andar", d.andar) +
        campo("Condomínio (taxa)", reais(numero(d.valor_condominio))) + campo("IPTU", reais(numero(d.iptu))) + campo("Mobília", d.mobilia) +
      "</div>" +
      (carac.length ? '<div class="olx-nota">' + esc(carac.join(" · ")) + "</div>" : "") +
      (d.descricao ? '<div class="bot-descricao">' + esc(d.descricao) + "</div>" : "") +
      (fotos.length ? '<div class="bot-fotos">' + fotos.slice(0, 12).map(function (u) {
        return '<img src="' + esc(u) + '" alt="" loading="lazy" referrerpolicy="no-referrer">';
      }).join("") + "</div>" : "") +
      '<div class="bot-bloco"><b>Corretor</b>' + esc(i.corretor_nome || "—") + " · " + esc(i.corretor_telefone || "sem telefone") +
        (i.proprietario_nome || i.proprietario_telefone
          ? "<br><b>Proprietário</b>" + esc(i.proprietario_nome || "sem nome") + (i.proprietario_telefone ? " · " + esc(i.proprietario_telefone) : "")
          : "<br><b>Proprietário</b>o bot não mandou — entra depois, antes do Cadastrar") + "</div>" +
      '<div class="bot-bloco bot-bloco--autoriza"><b>Autorização do proprietário (como o bot contou)</b>' + esc(i.autorizacao_como || "") + "</div>" +
      (d.observacoes ? '<div class="bot-bloco"><b>Observações do bot</b>' + esc(d.observacoes) + "</div>" : "") +
      (parecidos.length ? '<div class="bot-bloco bot-bloco--parecido"><b>Parece com imóvel que já é nosso — confira antes de aprovar</b>' +
        parecidos.map(function (c) {
          return '<a href="imovel-editar.html?codigo=' + encodeURIComponent(c.id_imovel) + '" target="_blank" rel="noopener">' + esc(c.id_imovel) + "</a> " +
            esc([c.titulo, c.status, "nota " + c.score + " (" + c.confianca + ")", (c.bateu || []).join(", ")].filter(Boolean).join(" · "));
        }).join("<br>") + "</div>" : "") +
      '<div class="olx-nota">Recebido em ' + esc(quando(i.recebido_em)) + (i.envios > 1 ? " · o bot mandou " + esc(i.envios) + " vezes (a última em " + esc(quando(i.atualizado_em)) + ")" : "") +
        " · " + esc(fotos.length) + " foto" + (fotos.length === 1 ? "" : "s") + "</div>" +
      '<div class="olx-item__acoes">' + decisao + '<span class="olx-nota" data-bot-status role="status"></span></div>' +
      "</article>";
  }

  function contar(contagem) {
    var n = (contagem && contagem.pendente) || 0;
    var selo = $("bot-conta");
    if (selo) { selo.hidden = !n; selo.textContent = n ? String(n) : ""; }
  }

  function carregar() {
    lista.innerHTML = '<p class="olx-nota">Carregando…</p>';
    fetch("api/olx-bot?estado=" + encodeURIComponent(estado), { credentials: "same-origin" })
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (d) {
        contar(d.contagem);
        var itens = d.itens || [];
        if (!itens.length) {
          lista.innerHTML = '<p class="olx-nota">' + (estado === "pendente" ? "Nenhum imóvel esperando aprovação."
            : estado === "aprovado" ? "Nenhum envio aprovado ainda." : "Nenhum envio descartado.") + "</p>";
          return;
        }
        lista.innerHTML = itens.map(cartao).join("");
      })
      .catch(function (erro) {
        lista.innerHTML = '<p class="olx-nota olx-nota--erro">Não consegui carregar os envios do bot' +
          (erro === 401 ? ": a senha do painel não foi aceita." : ".") + "</p>";
      });
  }

  /* Depois de aprovado: o dono (se o bot mandou) e as fotos, uma por vez -- é o
     que a Captação OLX já faz, e a foto só entra se for do anúncio (img.olx.com.br). */
  function completar(codigo, resposta, aviso) {
    var dono = resposta.proprietario || {};
    var passo = Promise.resolve();
    var notas = [];
    if (dono.nome || dono.telefone) {
      passo = passo.then(function () {
        aviso("Pré-cadastro " + codigo + " criado. Gravando o proprietário…");
        return enviar("api/imoveis/" + encodeURIComponent(codigo), "PUT", { proprietario: { nome: dono.nome || null, telefone: dono.telefone || null } })
          .then(function (res) { if (!res.ok) notas.push("o proprietário não gravou — ponha pelo espelho"); })
          .catch(function () { notas.push("o proprietário não gravou — ponha pelo espelho"); });
      });
    }
    var fotos = resposta.fotos || [];
    var baixadas = 0, falhas = 0;
    fotos.forEach(function (url, k) {
      passo = passo.then(function () {
        aviso("Pré-cadastro " + codigo + " criado. Baixando as fotos: " + (k + 1) + " de " + fotos.length + "…");
        return enviar("api/olx/" + encodeURIComponent(codigo) + "/foto", "POST", { url: url, ordem: k + 1 })
          .then(function (r) { if (r.ok && r.dados.ok) baixadas++; else falhas++; })
          .catch(function () { falhas++; });
      });
    });
    return passo.then(function () {
      if (fotos.length) notas.push(baixadas + " foto" + (baixadas === 1 ? "" : "s") + " baixada" + (baixadas === 1 ? "" : "s") + (falhas ? ", " + falhas + " não veio" + (falhas === 1 ? "" : "ram") : ""));
      return notas;
    });
  }

  lista.addEventListener("click", function (e) {
    var aprovar = e.target.closest("[data-bot-aprovar]");
    var descartar = e.target.closest("[data-bot-descartar]");
    var botao = aprovar || descartar;
    if (!botao) return;
    var item = botao.closest("[data-bot-item]");
    var status = item.querySelector("[data-bot-status]");
    var aviso = function (texto, erro) { status.textContent = texto; status.classList.toggle("olx-nota--erro", !!erro); };
    var botoes = item.querySelectorAll("button");
    var travar = function (sim) { botoes.forEach(function (b) { b.disabled = sim; }); };
    var id = botao.getAttribute(aprovar ? "data-bot-aprovar" : "data-bot-descartar");

    if (descartar) {
      var motivo = (item.querySelector("[data-bot-motivo]").value || "").trim();
      if (!motivo) { aviso("Escreva o motivo antes de descartar: o bot recebe se mandar de novo.", true); item.querySelector("[data-bot-motivo]").focus(); return; }
      travar(true);
      enviar("api/olx-bot/" + encodeURIComponent(id) + "/descartar", "POST", { motivo: motivo }).then(function (res) {
        if (!res.ok || !res.dados.ok) { travar(false); aviso("Não descartou: " + (res.dados.erro || "erro"), true); return; }
        carregar();
      }).catch(function (erro) { travar(false); aviso("Não descartou: " + erro.message, true); });
      return;
    }

    travar(true);
    aviso("Criando o pré-cadastro…");
    enviar("api/olx-bot/" + encodeURIComponent(id) + "/aprovar", "POST", {}).then(function (res) {
      if (!res.ok || !res.dados.ok) { travar(false); aviso("Não aprovou: " + (res.dados.erro || res.dados.detalhe || "erro"), true); return; }
      var codigo = res.dados.codigo;
      return completar(codigo, res.dados, aviso).then(function (notas) {
        document.dispatchEvent(new CustomEvent("olx:recarregar"));
        item.querySelector(".olx-item__acoes").innerHTML =
          '<span class="olx-nota"><b>Aprovado: pré-cadastro ' + esc(codigo) + "</b>" + (res.dados.novo ? "" : " (esse anúncio já estava importado; liguei a ele)") +
          (notas.length ? " · " + esc(notas.join(" · ")) : "") + ". Ainda é rascunho, fora do site e da Nay.</span>" +
          '<a class="btn-azul" href="imovel-editar.html?codigo=' + encodeURIComponent(codigo) + '">Abrir no editor</a>' +
          '<a class="btn-neutro" href="#olx" data-bot-ir-olx>Ver em Pré-cadastrados da OLX</a>';
        fetch("api/olx-bot?estado=pendente", { credentials: "same-origin" })
          .then(function (r) { return r.ok ? r.json() : null; }).then(function (d) { if (d) contar(d.contagem); }).catch(function () {});
      });
    }).catch(function (erro) { travar(false); aviso("Não aprovou: " + erro.message, true); });
  });

  // "Ver em Pré-cadastrados": troca de aba pelo botão da própria página
  lista.addEventListener("click", function (e) {
    if (!e.target.closest("[data-bot-ir-olx]")) return;
    e.preventDefault();
    var aba = $("aba-olx");
    if (aba) aba.click();
  });

  document.querySelectorAll("[data-bot-estado]").forEach(function (b) {
    b.addEventListener("click", function () {
      estado = b.getAttribute("data-bot-estado");
      document.querySelectorAll("[data-bot-estado]").forEach(function (o) {
        if (o === b) o.setAttribute("aria-current", "true"); else o.removeAttribute("aria-current");
      });
      carregar();
    });
  });

  document.addEventListener("olxbot:mostrar", carregar);

  /* Quem chega pelo endereço (#olxbot) já encontra o painel aberto: o
     captacao-olx.js roda ANTES deste arquivo e o aviso dele passa sem ninguém
     ouvindo. Painel aberto na carga = carrega aqui. Fechado = só o número da
     aba, para quem entra em Captação ver que há envio esperando. */
  if (!$("painel-olxbot").hidden) {
    carregar();
  } else {
    fetch("api/olx-bot?estado=pendente", { credentials: "same-origin" })
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (d) { if (d) contar(d.contagem); })
      .catch(function () {});
  }
})();
