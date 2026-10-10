/* ==========================================================================
   Imob Easy — admin › Grupos › CAPTAÇÃO ATIVA

   Pedro, 09/10/2026: "Ler solicitações de corretores nos grupos de WhatsApp
   (imóveis que eles procuram para clientes), comparar com o MEU catálogo e dar
   uma nota de 0 a 100 de semelhança. Lista vertical, uma solicitação embaixo
   da outra, mais recente primeiro. ESQUERDA: texto original do corretor,
   grupo, nome/telefone, data/hora e a ficha extraída. DIREITA: o melhor imóvel
   meu (foto, endereço, preço, quartos), nota % e o detalhamento da nota."

   Quem lê, extrai e pontua é o serviço nay-grupos (Python, na VPS). Esta tela
   só mostra o que ele gravou e guarda o que o Pedro julga: "Leitura correta /
   errada", rejeitar, os testes colados e os apelidos. Tudo por
   /admin/api/grupos/captacao (senha do painel).

   MODO TREINO: nada é enviado. O botão "Aprovar e enviar" fica desligado, e
   mesmo que alguém o ligasse o banco recusa (site_captacao_grupos_estado, 336)
   e o serviço não tem por onde enviar.
   ========================================================================== */
(function () {
  "use strict";

  var API = window.API_BASE || "https://api.imobeasy.online";
  var FUSO = "America/Manaus";
  var painel = document.querySelector('[data-painel="captacao"]');
  if (!painel) return;

  var $ = function (id) { return document.getElementById(id); };
  var estado = { filtro: "todos", dados: null, pedido: 0, carregou: false, fotos: {}, demandaDias: 30 };

  var ROTULO = { operacao: "Operação", tipo: "Tipo", bairros: "Bairros", condominio: "Condomínio", quartos: "Quartos",
                 preco_max: "Teto", mobiliado: "Mobiliado", andar: "Andar", suite: "Suíte", vagas: "Vagas", pet: "Pet", contato: "Contato" };
  var ORDEM = ["operacao", "tipo", "bairros", "condominio", "quartos", "preco_max", "mobiliado", "andar", "suite", "vagas", "pet", "contato"];
  var CRITERIO = { preco: "Preço", local: "Local", quartos: "Quartos", mobiliado: "Mobília", andar: "Andar", extras: "Extras" };
  var COMO = { apelido: "pelo apelido", exato: "", lugar: "conjunto/região", parecido: "parecido", pedaco: "pedaço do nome" };
  var ETAPA = { operacao: "para a operação", tipo: "do tipo", local: "no local", quartos: "com os quartos", preco: "no preço", confirmado: "confirmados" };

  function esc(v) {
    return String(v == null ? "" : v).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }
  function pedir(url, opcoes) {
    return fetch(url, Object.assign({ credentials: "same-origin", headers: { "Content-Type": "application/json" } }, opcoes || {}))
      .then(function (r) {
        return r.json().catch(function () { return {}; }).then(function (d) {
          if (r.status === 401) throw new Error("a senha do painel não foi aceita: recarregue a página e entre de novo");
          if (!r.ok) throw new Error(d.erro || ("HTTP " + r.status));
          return d;
        });
      });
  }
  function reais(n) { return n == null ? "" : "R$ " + Number(n).toLocaleString("pt-BR", { maximumFractionDigits: 0 }); }
  function quando(iso) {
    if (!iso) return "";
    var d = new Date(iso);
    return d.toLocaleString("pt-BR", { timeZone: FUSO, day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });
  }
  function fone(t) {
    var d = String(t || "").replace(/\D/g, "").replace(/^55/, "");
    if (d.length < 10) return t || "";
    return "(" + d.slice(0, 2) + ") " + d.slice(2, d.length - 4) + "-" + d.slice(-4);
  }

  /* ── o topo: modo, serviço, de onde vêm as mensagens, taxa de acerto ── */
  function desenharTopo(d) {
    var h = [];
    h.push('<span class="gc-selo gc-selo--treino" title="O serviço lê, extrai, pontua e mostra. Não existe envio nesta versão.">MODO TREINO · nada é enviado</span>');
    h.push(d.servico_vivo
      ? '<span class="gc-selo gc-selo--ok" title="Última passada: ' + esc(quando(d.batimento)) + '">leitor ligado</span>'
      : '<span class="gc-selo gc-selo--ruim">leitor parado' + (d.batimento ? " desde " + esc(quando(d.batimento)) : "") + "</span>");
    var c = d.contagem || {};
    h.push('<span class="gc-selo">' + (c.todos || 0) + " solicitações nas últimas " + d.horas + " h</span>");
    var a = d.acerto || {};
    if (a.julgados) {
      h.push('<span class="gc-selo" title="Só o último julgamento de cada solicitação conta">leitura certa em ' + a.corretas + " de " + a.julgados +
             " julgadas (" + Math.round(a.corretas * 100 / a.julgados) + "%)</span>");
    }
    var f = d.fonte || {};
    if (!f.com_texto) {
      h.push('<div class="gc-aviso"><b>Os grupos não estão entregando o texto das mensagens.</b> Nas últimas ' + d.horas + " h chegaram " +
             (f.mensagens || 0) + " avisos de " + (f.grupos || 0) + " grupos (entrou, saiu, apagou) e nenhuma mensagem com texto: a Z-API da Parceria não está " +
             "repassando o conteúdo dos grupos. Enquanto isso não for ligado, só aparecem aqui as mensagens coladas em <b>Testar uma mensagem</b>.</div>");
    } else {
      h.push('<span class="gc-selo">' + f.com_texto + " mensagens com texto de " + f.grupos + " grupos · " + (f.lidas || 0) + " lidas</span>");
    }
    if (d.aviso) h.push('<div class="gc-aviso"><b>Configuração:</b> ' + esc(d.aviso) + "</div>");
    $("gc-topo").innerHTML = h.join("");

    var botoes = $("gc-filtros").querySelectorAll("[data-filtro]");
    var conta = { todos: c.todos, verde: c.verde, amarelo: c.amarelo, sem_match: c.sem_match, teste: c.teste };
    var cortes = (d.config && d.config.cortes) || { verde: 90, amarelo: 70 };
    var nome = { todos: "Todas", verde: "Nota ≥ " + cortes.verde, amarelo: cortes.amarelo + " a " + (cortes.verde - 1), sem_match: "Sem match", teste: "Testes" };
    Array.prototype.forEach.call(botoes, function (b) {
      var k = b.getAttribute("data-filtro");
      b.textContent = nome[k] + " (" + (conta[k] || 0) + ")";
      b.setAttribute("aria-pressed", k === estado.filtro ? "true" : "false");
    });
  }

  /* ── a ficha extraída ── */
  function valorDoCampo(campo, v) {
    if (v == null || (Array.isArray(v) && !v.length)) return null;
    if (campo === "preco_max") return "até " + reais(v);
    if (campo === "bairros") return v.join(" ou ");
    if (campo === "andar") return v.map(function (a) { return { terreo: "térreo", "1_andar": "1º andar", qualquer: "qualquer" }[a] || a; }).join(" ou ");
    if (campo === "mobiliado") return v ? "sim" : "não (cru)";
    if (campo === "suite" || campo === "pet") return v ? "sim" : "não";
    return String(v);
  }
  function desenharFicha(p) {
    var ficha = p.ficha || {}, duvidosos = p.duvidosos || [], h = ['<ul class="gc-ficha">'], algum = false;
    ORDEM.forEach(function (campo) {
      var v = valorDoCampo(campo, ficha[campo]);
      if (v == null) return;
      algum = true;
      h.push('<li class="gc-campo' + (duvidosos.indexOf(campo) >= 0 ? " gc-campo--duvidoso" : "") + '"><span>' + ROTULO[campo] + "</span><b>" + esc(v) + "</b></li>");
    });
    h.push("</ul>");
    if (!algum) h.push('<p class="gc-lugar">A IA não achou nenhum campo nesta mensagem.</p>');
    var local = p.local || {};
    if (local.operacao && local.operacao_origem === "nome do grupo") {
      h.push('<p class="gc-lugar">Operação <b>' + esc(local.operacao) + "</b> tirada do nome do grupo (a mensagem não disse).</p>");
    }
    (local.itens || []).forEach(function (it) {
      var tipo = it.tipo === "condominio" ? "condomínio" : "bairro";
      if (!it.como) {
        h.push('<p class="gc-lugar gc-lugar--duvida">Não reconheci o ' + tipo + " <b>" + esc(it.escrito) + "</b>" +
               (it.sugestao ? " (o mais parecido: " + esc(it.sugestao) + ")" : "") +
               ' <button type="button" class="btn-mini" data-apelido="' + esc(it.escrito) + '" data-tipo="' + esc(it.tipo) + '" data-oficial="' + esc(it.sugestao || "") + '">criar apelido</button></p>');
      } else if (it.como !== "exato" || (it.oficiais || []).join("|").toLowerCase() !== String(it.escrito).toLowerCase()) {
        h.push('<p class="gc-lugar' + (it.como === "parecido" || it.como === "pedaco" ? " gc-lugar--duvida" : "") + '">' + esc(it.escrito) + " → <b>" +
               esc((it.oficiais || []).slice(0, 4).join(", ")) + ((it.oficiais || []).length > 4 ? " e mais " + (it.oficiais.length - 4) : "") + "</b>" +
               (COMO[it.como] ? " (" + COMO[it.como] + ")" : "") +
               (it.como === "parecido" || it.como === "pedaco"
                 ? ' <button type="button" class="btn-mini" data-apelido="' + esc(it.escrito) + '" data-tipo="' + esc(it.tipo) + '" data-oficial="' + esc((it.oficiais || [])[0] || "") + '">confirmar como apelido</button>'
                 : "") + "</p>");
      }
    });
    if (ficha.observacao) h.push('<p class="gc-obs">Também pediu: ' + esc(ficha.observacao) + "</p>");
    return h.join("");
  }

  /* ── o lado do imóvel ── */
  function valorDoImovel(im, operacao) { return operacao === "venda" ? im.valor_venda : im.valor_aluguel; }
  function linhaDoImovel(im) {
    var partes = [];
    if (im.quartos != null) partes.push(im.quartos + (im.quartos === 1 ? " quarto" : " quartos") + (im.suites ? " (" + im.suites + (im.suites === 1 ? " suíte)" : " suítes)") : ""));
    if (im.vagas != null) partes.push(im.vagas + (im.vagas === 1 ? " vaga" : " vagas"));
    if (im.area) partes.push(Math.round(im.area) + " m²");
    if (im.andar_cadastro) partes.push("andar: " + im.andar_cadastro);
    if (im.mobilia_cadastro) partes.push(im.mobilia_cadastro);
    return partes.join(" · ");
  }
  function desenharDetalhe(par) {
    var h = ['<table class="gc-detalhe"><thead><tr><th>Critério</th><th class="num">Peso</th><th>Rendeu</th><th class="num">Pontos</th><th>Por quê</th></tr></thead><tbody>'];
    (par.detalhe || []).forEach(function (d) {
      h.push("<tr><td><b>" + esc(CRITERIO[d.criterio] || d.criterio) + '</b></td><td class="num">' + esc(d.peso) + '</td><td><span class="gc-barra"><i style="width:' +
             Math.max(0, Math.min(100, d.rendimento)) + '%"></i></span>' + Math.round(d.rendimento) + '%</td><td class="num">' + esc(d.pontos) + "</td><td>" + esc(d.texto) + "</td></tr>");
    });
    h.push("</tbody></table>");
    return h.join("");
  }
  function desenharImovel(p) {
    var pares = p.pares || [], operacao = (p.local && p.local.operacao) || (p.ficha && p.ficha.operacao);
    if (!p.pontuado) return '<div class="gc-sem"><strong>Calculando…</strong><p>O leitor ainda não fez a conta desta solicitação.</p></div>';
    if (!pares.length) {
      var funil = p.funil || {}, passos = [];
      ["operacao", "tipo", "local", "quartos", "preco", "confirmado"].forEach(function (e) {
        if (funil[e] != null) passos.push(funil[e] + " " + ETAPA[e]);
      });
      return '<div class="gc-sem"><strong>Sem imóvel compatível</strong><p>' + esc(p.sem_match_motivo || "nada passou nos filtros") + "</p>" +
             (passos.length ? '<p class="gc-funil">Imóveis nossos que sobraram a cada filtro: ' + esc(passos.join(" → ")) + "</p>" : "") + "</div>";
    }
    var m = pares[0], im = m.imovel || {}, faixa = p.faixa || "registro";
    var h = ['<div class="gc-imovel">',
             '<img class="gc-foto" alt="" data-foto="' + esc(im.codigo) + '" loading="lazy">',
             '<div class="gc-imovel__dados">',
             '<p class="gc-imovel__nome"><a href="' + esc(API.replace("api.", "") + "/imovel/" + im.codigo) + '" target="_blank" rel="noopener">' + esc(im.codigo) + " · " +
               esc(im.condominio || im.tipo_cadastro || "Imóvel") + "</a></p>",
             '<p class="gc-imovel__linha" data-endereco="' + esc(im.codigo) + '">' + esc([im.logradouro, im.bairro].filter(Boolean).join(" · ")) + "</p>",
             '<p class="gc-imovel__linha">' + esc(linhaDoImovel(im)) + "</p>",
             '<p class="gc-imovel__preco">' + esc(reais(valorDoImovel(im, operacao))) + (operacao === "aluguel" ? " /mês" : "") +
               (im.taxa_condominio ? ' <span class="gc-imovel__linha">+ cond. ' + esc(reais(im.taxa_condominio)) + "</span>" : "") + "</p>",
             (m.acima_do_teto ? '<span class="gc-etiqueta">acima do teto, negociável</span>' : ""),
             "</div>",
             '<div class="gc-nota gc-nota--' + esc(faixa) + '"><b>' + Math.round(m.nota) + "%</b><span>" +
               ({ verde: "na fila", amarelo: "parecido", registro: "fraco" }[faixa] || "") + "</span></div>",
             "</div>",
             desenharDetalhe(m)];
    if (im.confirmado_em) h.push('<p class="gc-confirmado">Disponível e confirmado em ' + esc(quando(im.confirmado_em)) + " (" + esc(im.confirmado_como || "") + ").</p>");
    if (pares.length > 1) {
      h.push('<details class="gc-alternativas"><summary>' + (pares.length - 1) + (pares.length === 2 ? " alternativa" : " alternativas") +
             (p.local && p.local.passaram > pares.length ? " (de " + (p.local.passaram - 1) + " que passaram)" : "") + "</summary><ul>");
      pares.slice(1).forEach(function (a) {
        var ia = a.imovel || {};
        h.push("<li><span>" + esc(ia.codigo) + " · " + esc(ia.condominio || ia.tipo_cadastro || "") + " · " + esc(ia.bairro || "") + " · " +
               esc(ia.quartos != null ? ia.quartos + "q" : "") + " · " + esc(reais(valorDoImovel(ia, operacao))) +
               (a.acima_do_teto ? " (acima do teto)" : "") + "</span><b>" + Math.round(a.nota) + "%</b></li>");
      });
      h.push("</ul></details>");
    }
    return h.join("");
  }

  function desenharItem(p) {
    var faixa = p.pontuado ? (p.faixa || "sem_match") : "registro";
    var j = p.julgamento, rejeitado = p.estado === "rejeitado";
    var quem = ['<span class="gc-grupo">' + esc(p.grupo || "Grupo") + "</span>"];
    if (p.nome) quem.push("<b>" + esc(p.nome) + "</b>");
    if (p.telefone) quem.push(esc(fone(p.telefone)));
    quem.push(esc(quando(p.enviada_em)));
    var h = ['<article class="gc-item gc-item--' + esc(faixa) + (rejeitado ? " gc-item--rejeitado" : "") + '" data-id="' + p.id + '">',
             '<div class="gc-lado">',
             '<div class="gc-quem">' + quem.join(" · ") + "</div>",
             '<p class="gc-texto">' + esc(p.texto) + "</p>",
             (p.parte > 1 || (p.ficha && p.ficha.trecho && p.ficha.trecho.length + 12 < String(p.texto).length)
               ? '<p class="gc-parte">Pedido ' + p.parte + " desta mensagem: “" + esc(p.ficha.trecho || "") + "”</p>" : ""),
             desenharFicha(p),
             '<div class="gc-acoes">',
             '<button type="button" class="btn-mini" disabled title="Só no modo ATIVO. No treino nada é enviado.">Aprovar e enviar</button>',
             '<button type="button" class="btn-mini" data-acao="' + (rejeitado ? "voltar" : "rejeitar") + '">' + (rejeitado ? "Desfazer rejeição" : "Rejeitar") + "</button>",
             '<button type="button" class="btn-mini" data-acao="correta">Leitura correta</button>',
             '<button type="button" class="btn-mini" data-acao="errada">Leitura errada</button>',
             (j ? '<span class="gc-julgado gc-julgado--' + esc(j.leitura) + '" title="' + esc(quando(j.quando)) + '">' +
                  (j.leitura === "correta" ? "✓ leitura correta" : "✗ leitura errada" + (j.o_que_errou ? ": " + esc(j.o_que_errou) : "")) + "</span>" : ""),
             "</div>",
             "</div>",
             '<div class="gc-lado">' + desenharImovel(p) + "</div>",
             "</article>"];
    return h.join("");
  }

  /* a foto e o endereço vêm do card do imóvel (a mesma rota do resto do admin), uma vez por código */
  function buscarFotos() {
    Array.prototype.forEach.call(painel.querySelectorAll("img[data-foto]"), function (img) {
      var c = img.getAttribute("data-foto");
      if (!estado.fotos[c]) {
        estado.fotos[c] = fetch(API + "/api/imovel-card/" + encodeURIComponent(c)).then(function (r) { return r.json(); })
          .then(function (d) { return d.imovel || {}; }).catch(function () { return {}; });
      }
      estado.fotos[c].then(function (im) {
        if (im.capa) img.src = im.capa;
        var linha = painel.querySelector('[data-endereco="' + c + '"]');
        if (linha && im.endereco) linha.textContent = [im.endereco, im.bairro].filter(Boolean).join(" · ");
      });
    });
  }

  function desenhar() {
    var d = estado.dados;
    if (!d) return;
    desenharTopo(d);
    var lista = $("gc-lista"), pedidos = d.pedidos || [];
    if (!pedidos.length) {
      lista.innerHTML = '<p class="gc-vazio">' + (estado.filtro === "todos"
        ? "Nenhuma solicitação nas últimas " + d.horas + " h. Cole uma mensagem em “Testar uma mensagem” para ver a leitura."
        : "Nenhuma solicitação neste filtro.") + "</p>";
      return;
    }
    lista.innerHTML = pedidos.map(desenharItem).join("");
    buscarFotos();
  }

  function carregar() {
    var n = ++estado.pedido;
    if (!estado.dados) $("gc-lista").innerHTML = '<p class="ga-carregando">Carregando as solicitações…</p>';
    return pedir("/admin/api/grupos/captacao?filtro=" + encodeURIComponent(estado.filtro))
      .then(function (d) { if (n === estado.pedido) { estado.dados = d; estado.carregou = true; desenhar(); } })
      .catch(function (e) { if (n === estado.pedido) $("gc-lista").innerHTML = '<p class="gc-vazio">Não consegui carregar: ' + esc(e.message) + "</p>"; });
  }

  /* ── ações de cada solicitação ── */
  function agir(item, acao, botao) {
    var id = item.getAttribute("data-id");
    if (acao === "errada") {
      if (item.querySelector(".gc-errou")) return;
      var caixa = document.createElement("form");
      caixa.className = "gc-errou";
      caixa.innerHTML = '<input class="entrada" maxlength="1000" placeholder="O que a leitura errou? (ex.: eram 2 quartos; o bairro é Aleixo)" aria-label="O que errou">' +
                        '<button class="btn-azul" type="submit">Salvar</button>';
      item.querySelector(".gc-acoes").appendChild(caixa);
      caixa.querySelector("input").focus();
      caixa.addEventListener("submit", function (ev) {
        ev.preventDefault();
        var texto = caixa.querySelector("input").value.trim();
        if (!texto) { caixa.querySelector("input").focus(); return; }
        pedir("/admin/api/grupos/captacao/" + id + "/julgar", { method: "POST", body: JSON.stringify({ leitura: "errada", erro: texto }) })
          .then(carregar).catch(function (e) { alert(e.message); });
      });
      return;
    }
    botao.disabled = true;
    var chamada = acao === "correta"
      ? pedir("/admin/api/grupos/captacao/" + id + "/julgar", { method: "POST", body: JSON.stringify({ leitura: "correta" }) })
      : pedir("/admin/api/grupos/captacao/" + id + "/estado", { method: "POST", body: JSON.stringify({ estado: acao === "rejeitar" ? "rejeitado" : "novo" }) });
    chamada.then(carregar).catch(function (e) { botao.disabled = false; alert(e.message); });
  }

  /* ── testar uma mensagem ── */
  function testar(ev) {
    ev.preventDefault();
    var campo = $("gc-teste-texto"), aviso = $("gc-teste-estado"), botao = $("gc-teste-ler"), texto = campo.value.trim();
    function dizer(t, erro) { aviso.textContent = t; if (erro) aviso.setAttribute("data-erro", "1"); else aviso.removeAttribute("data-erro"); }
    if (texto.length < 8) { dizer("Cole a mensagem do corretor.", true); campo.focus(); return; }
    botao.disabled = true;
    dizer("Enviando para a IA ler…");
    pedir("/admin/api/grupos/captacao/testar", { method: "POST", body: JSON.stringify({ texto: texto }) })
      .then(function (r) {
        var tentativas = 0;
        (function esperar() {
          tentativas += 1;
          pedir("/admin/api/grupos/captacao/testar/" + r.id).then(function (s) {
            if (s.lido && (s.pontuado || !s.pedidos)) {
              botao.disabled = false;
              if (s.erro) return dizer("A IA não respondeu agora (" + s.erro.slice(0, 80) + "). O leitor tenta de novo em 10 minutos.", true);
              if (!s.pedidos) return dizer("A IA leu e entendeu que isto NÃO é um pedido de imóvel" + (s.motivo ? " (" + s.motivo + ")" : "") + ".", true);
              dizer(s.pedidos === 1 ? "Lida: 1 pedido. Está no topo da lista." : "Lida: " + s.pedidos + " pedidos. Estão no topo da lista.");
              campo.value = "";
              estado.filtro = "todos";
              return carregar();
            }
            if (tentativas > 45) { botao.disabled = false; return dizer("O leitor está demorando. Se o selo lá em cima diz \"leitor parado\", é isso: a mensagem fica na fila.", true); }
            dizer(s.lido ? "Lida. Fazendo a conta com o catálogo…" : "A IA está lendo…");
            setTimeout(esperar, 2000);
          }).catch(function (e) { botao.disabled = false; dizer(e.message, true); });
        })();
      })
      .catch(function (e) { botao.disabled = false; dizer(e.message, true); });
  }

  /* ── demanda do mercado ── */
  function abrirDemanda() {
    var dlg = $("gc-demanda");
    if (!dlg.open) dlg.showModal();
    $("gc-dem-corpo").innerHTML = '<p class="ga-carregando">Somando os pedidos…</p>';
    pedir("/admin/api/grupos/captacao/demanda?dias=" + estado.demandaDias).then(function (d) {
      var h = ['<p class="ga-dica">Nos últimos ' + d.dias + " dias os grupos pediram <b>" + d.pedidos + "</b> imóveis e para <b>" + d.sem_imovel +
               "</b> não tínhamos nada compatível. Abaixo, o que mais pedem (bairro ou condomínio, quartos e faixa de valor); em vermelho, quantos ficaram sem imóvel nosso. " +
               "Testes colados na tela não entram.</p>"];
      if (!(d.linhas || []).length) {
        h.push('<p class="gc-vazio">Ainda não há pedidos de grupo guardados.</p>');
      } else {
        h.push('<div class="tabela-rolagem"><table class="gc-tabela"><thead><tr><th>Operação</th><th>Onde</th><th class="num">Quartos</th><th>Faixa de valor</th><th class="num">Pedidos</th><th class="num">Sem imóvel nosso</th></tr></thead><tbody>');
        d.linhas.forEach(function (l) {
          h.push("<tr" + (l.sem_imovel ? ' data-falta="1"' : "") + "><td>" + esc(l.operacao) + "</td><td>" + esc(l.lugar) + '</td><td class="num">' + esc(l.quartos == null ? "–" : l.quartos) +
                 "</td><td>" + esc(l.preco) + '</td><td class="num">' + l.pedidos + '</td><td class="num">' + l.sem_imovel + "</td></tr>");
        });
        h.push("</tbody></table></div>");
      }
      $("gc-dem-corpo").innerHTML = h.join("");
    }).catch(function (e) { $("gc-dem-corpo").innerHTML = '<p class="gc-vazio">Não consegui somar: ' + esc(e.message) + "</p>"; });
  }

  /* ── apelidos ── */
  var nomesDoCadastro = { bairro: [], condominio: [] };
  function encherNomes() {
    var tipo = $("gc-ap-tipo").value;
    $("gc-ap-nomes").innerHTML = (nomesDoCadastro[tipo] || []).map(function (n) { return '<option value="' + esc(n) + '">'; }).join("");
  }
  function carregarApelidos() {
    $("gc-ap-corpo").innerHTML = '<p class="ga-carregando">Carregando…</p>';
    return pedir("/admin/api/grupos/captacao/apelidos").then(function (d) {
      nomesDoCadastro = { bairro: d.bairros || [], condominio: d.condominios || [] };
      encherNomes();
      var h = ['<table class="gc-tabela"><thead><tr><th>Como escrevem</th><th>Tipo</th><th>Nome no cadastro</th><th></th></tr></thead><tbody>'];
      (d.apelidos || []).forEach(function (a) {
        h.push("<tr><td><b>" + esc(a.apelido) + "</b></td><td>" + (a.tipo === "bairro" ? "bairro" : "condomínio") + "</td><td>" + esc(a.oficial) +
               (a.obs ? ' <small style="color:var(--texto-fraco)">(' + esc(a.obs) + ")</small>" : "") +
               '</td><td><button type="button" class="btn-mini" data-gc-excluir="' + esc(a.apelido) + '">excluir</button></td></tr>');
      });
      if (!(d.apelidos || []).length) h.push('<tr><td colspan="4">Nenhum apelido ainda.</td></tr>');
      h.push("</tbody></table>");
      $("gc-ap-corpo").innerHTML = h.join("");
    }).catch(function (e) { $("gc-ap-corpo").innerHTML = '<p class="gc-vazio">Não consegui carregar: ' + esc(e.message) + "</p>"; });
  }
  function abrirApelidos(apelido, tipo, oficial) {
    var dlg = $("gc-apelidos");
    $("gc-ap-erro").textContent = "";
    $("gc-ap-apelido").value = apelido || "";
    if (tipo) $("gc-ap-tipo").value = tipo;
    $("gc-ap-oficial").value = oficial || "";
    if (!dlg.open) dlg.showModal();
    carregarApelidos().then(function () { (apelido ? $("gc-ap-oficial") : $("gc-ap-apelido")).focus(); });
  }
  function salvarApelido(ev) {
    ev.preventDefault();
    $("gc-ap-erro").textContent = "";
    pedir("/admin/api/grupos/captacao/apelidos", { method: "POST", body: JSON.stringify({
      apelido: $("gc-ap-apelido").value, tipo: $("gc-ap-tipo").value, oficial: $("gc-ap-oficial").value }) })
      .then(function () {
        $("gc-ap-apelido").value = ""; $("gc-ap-oficial").value = "";
        carregarApelidos();
        setTimeout(carregar, 12000);           // o leitor refaz a conta na passada seguinte
      })
      .catch(function (e) { $("gc-ap-erro").textContent = e.message; });
  }

  /* ── ligações ── */
  document.addEventListener("click", function (ev) {
    var alvo = ev.target.closest ? ev.target : null;
    if (!alvo) return;
    /* "+ Nova mensagem" é da agenda: nesta aba não há o que criar */
    var aba = alvo.closest("[data-painel-abre]");
    if (aba && $("ga-nova")) $("ga-nova").hidden = aba.getAttribute("data-painel-abre") === "captacao";
    if (alvo.closest('[data-painel-abre="captacao"]')) {
      if (!estado.carregou) carregar();
      try { history.replaceState(null, "", "#captacao"); } catch (_) { /* sem histórico */ }
      return;
    }
    var fechar = alvo.closest("#gc-demanda [data-fechar], #gc-apelidos [data-fechar]");
    if (fechar) { var dlg = fechar.closest("dialog"); if (dlg.open) dlg.close(); return; }
    /* nomes próprios (data-gc-...): o ouvinte geral do grupos-agenda.js pega todo botão com data-dias (período das
       métricas) e data-excluir (apaga mensagem agendada) */
    var dias = alvo.closest("#gc-dem-dias [data-gc-dias]");
    if (dias) {
      estado.demandaDias = parseInt(dias.getAttribute("data-gc-dias"), 10) || 30;
      Array.prototype.forEach.call($("gc-dem-dias").querySelectorAll("[data-gc-dias]"), function (b) { b.setAttribute("aria-pressed", b === dias ? "true" : "false"); });
      abrirDemanda();
      return;
    }
    var excluir = alvo.closest("[data-gc-excluir]");
    if (excluir) {
      pedir("/admin/api/grupos/captacao/apelidos", { method: "DELETE", body: JSON.stringify({ apelido: excluir.getAttribute("data-gc-excluir") }) })
        .then(function () { carregarApelidos(); setTimeout(carregar, 12000); })
        .catch(function (e) { $("gc-ap-erro").textContent = e.message; });
      return;
    }
    if (!painel.contains(alvo)) return;
    var filtro = alvo.closest("[data-filtro]");
    if (filtro) { estado.filtro = filtro.getAttribute("data-filtro"); carregar(); return; }
    if (alvo.closest("#gc-atualizar")) { carregar(); return; }
    if (alvo.closest("#gc-ver-demanda")) { abrirDemanda(); return; }
    if (alvo.closest("#gc-ver-apelidos")) { abrirApelidos(); return; }
    var apelido = alvo.closest("[data-apelido]");
    if (apelido) { abrirApelidos(apelido.getAttribute("data-apelido"), apelido.getAttribute("data-tipo"), apelido.getAttribute("data-oficial")); return; }
    var acao = alvo.closest("[data-acao]");
    if (acao) agir(acao.closest(".gc-item"), acao.getAttribute("data-acao"), acao);
  });
  $("gc-teste").addEventListener("submit", testar);
  $("gc-ap-form").addEventListener("submit", salvarApelido);
  $("gc-ap-tipo").addEventListener("change", encherNomes);

  /* a aba pode ser aberta direto pelo endereço: grupos.html#captacao */
  if (location.hash === "#captacao") {
    var aba = document.querySelector('[data-painel-abre="captacao"]');
    if (aba) aba.click();
  }
  /* com a aba aberta, a lista se renova sozinha (o leitor passa a cada 10 s) */
  setInterval(function () {
    if (!painel.hidden && estado.carregou && document.visibilityState === "visible" && !painel.querySelector(".gc-errou") &&
        !$("gc-demanda").open && !$("gc-apelidos").open) carregar();
  }, 45000);
})();
