/* ==========================================================================
   Imob Easy — Captação de proprietários (campanha temporária)

   Esta tela é só o lado humano. Quem manda mensagem e quem conversa é o
   fluxo n8n `Nay - captacao proprietarios`; aqui o Tel monta a lista, tira
   quem não deve receber, acompanha o log e faz a curadoria do que voltou.

   Nada nesta tela dispara mensagem. "Adicionar lista" só cria os leads com
   status 'novo' -- o envio depende do cron do n8n e do interruptor
   captacao_pausada, que mora no banco.
   ========================================================================== */
(function () {
  "use strict";

  var API = window.API_BASE;
  var corpo = document.getElementById("corpo-leads");
  var indicadores = document.getElementById("indicadores");
  var avisoTeste = document.getElementById("aviso-teste");
  var chaves = document.getElementById("chaves");
  var chavesStatus = document.getElementById("chaves-status");
  var abas = document.getElementById("abas");
  var acaoAba = document.getElementById("acao-aba");
  var baldeAtual = "";
  var candidatosAbertos = [];
  var listaAberta = null;
  var busca = document.getElementById("busca-leads");
  var buscaConta = document.getElementById("busca-conta");
  var leadsNaTela = {};     // id -> lead, para o popup "Mudar manualmente"
  var leadMudando = null;

  function esc(txt) {
    return String(txt == null ? "" : txt)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }

  function quando(iso) {
    if (!iso) return "—";
    var d = new Date(iso);
    return d.toLocaleDateString("pt-BR") + " " +
      d.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" });
  }

  function telefoneBonito(t) {
    var d = String(t || "").replace(/\D/g, "");
    if (d.length < 12) return t || "—";
    var ddd = d.slice(2, 4), resto = d.slice(4);
    return "(" + ddd + ") " + resto.slice(0, resto.length - 4) + "-" + resto.slice(-4);
  }

  var ROTULO_SITUACAO = {
    disponivel: '<span class="etiqueta etiqueta--verde">disponível</span>',
    alugado: '<span class="etiqueta etiqueta--azul">alugado</span>',
    vendido: '<span class="etiqueta etiqueta--laranja">já vendeu</span>'
  };

  /* ---------------------------------------------------------------- */
  /* Métricas e interruptores                                          */
  /* ---------------------------------------------------------------- */

  function cartao(rotulo, valor) {
    return '<div class="indicador"><div class="indicador__topo">' +
      '<span class="indicador__rotulo">' + esc(rotulo) + "</span></div>" +
      '<span class="indicador__valor">' + esc(valor) + "</span></div>";
  }

  function pintarResumo(d) {
    var l = d.leads, e = d.envios;
    indicadores.innerHTML =
      cartao("Na campanha", l.total) +
      cartao("Mensagens enviadas", e.enviadas) +
      cartao("Enviadas hoje", e.enviadasHoje) +
      cartao("Responderam", l.responderam) +
      cartao("Disponíveis", l.disponiveis) +
      cartao("Alugados", l.alugados) +
      cartao("Já venderam", l.vendidos) +
      cartao("Querem vender", l.querem_vender) +
      cartao("Com o Tel", l.com_o_tel) +
      cartao("Com outro imóvel", l.com_outro_imovel) +
      cartao("Sem resposta", l.sem_resposta) +
      cartao("Falhas de envio", e.falharam) +
      cartao("Pediram para sair", l.opt_out) +
      cartao("Último envio", quando(e.ultimoEnvio));

    // Espelha o que está no banco nos controles, sem disparar o onchange.
    Object.keys(d.config).forEach(function (chave) {
      var campo = chaves.querySelector('[data-chave="' + chave + '"]');
      if (campo) campo.value = d.config[chave];
    });

    if (d.config.modo_teste === "sim") {
      avisoTeste.hidden = false;
      avisoTeste.className = "cap-teste";
      avisoTeste.innerHTML =
        "<strong>🧪 MODO TESTE LIGADO.</strong> Toda mensagem desta campanha vai para " +
        "<strong>" + esc(telefoneBonito(d.config.telefone_teste)) + "</strong>, seja qual for o " +
        "proprietário da fila. Nenhum proprietário real recebe nada enquanto isto estiver assim. " +
        "Para valer, mude “Modo teste” para <em>desligado</em> aqui em cima — " +
        "ou apague o nó <strong>🧪 MODO TESTE — SÓ ENVIA PRO TEL</strong> no fluxo do n8n.";
    } else {
      avisoTeste.hidden = false;
      avisoTeste.className = "cap-teste";
      avisoTeste.style.borderColor = "var(--perigo, #c0392b)";
      avisoTeste.innerHTML =
        "<strong>⚠️ MODO TESTE DESLIGADO.</strong> As mensagens vão para os proprietários de verdade.";
    }
  }

  function carregarResumo() {
    return fetch(API + "/api/captacao/resumo")
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(pintarResumo)
      .catch(function () {
        indicadores.innerHTML = '<div class="indicador"><span class="indicador__rotulo">' +
          "Não foi possível carregar o resumo.</span></div>";
      });
  }

  chaves.addEventListener("change", function (evento) {
    var campo = evento.target.closest("[data-chave]");
    if (!campo) return;
    chavesStatus.textContent = "Salvando…";
    fetch(API + "/api/captacao/config", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ chave: campo.dataset.chave, valor: String(campo.value) })
    })
      .then(function (r) { return r.json().then(function (j) { return { ok: r.ok, j: j }; }); })
      .then(function (res) {
        chavesStatus.textContent = res.ok
          ? "Salvo às " + new Date().toLocaleTimeString("pt-BR")
          : "Não salvou: " + (res.j.erro || "erro");
        return carregarResumo();
      })
      .catch(function () { chavesStatus.textContent = "Não salvou: rede."; });
  });

  /* ---------------------------------------------------------------- */
  /* Tabela de curadoria                                               */
  /* ---------------------------------------------------------------- */

  /* A acao muda com a aba, e essa e a regra do processo:
     - "Todos" e a unica coluna que um humano enche -> Adicionar lista.
     - Os outros baldes sao preenchidos pela IA, a partir do que o
       proprietario respondeu. Ninguem arrasta lead na mao para "Disponiveis";
       o que se faz com eles e exportar. Por isso "Adicionar lista" nem
       aparece fora de "Todos". */
  function pintarAcao() {
    if (baldeAtual === "") {
      acaoAba.innerHTML =
        '<button class="btn-azul" type="button" id="btn-importar">Adicionar lista à campanha</button>' +
        "<span>Esta é a única coluna que você enche. Daqui pra frente quem move o lead é a IA, " +
        "pelo que o proprietário responder.</span>";
    } else {
      acaoAba.innerHTML =
        '<button class="btn-azul-vazado" type="button" id="btn-exportar">Exportar esta lista (CSV)</button>' +
        "<span>A IA trouxe estes leads para cá pela resposta do proprietário. " +
        "Aqui você exporta — não adiciona.</span>";
    }
  }

  function linhaLead(l) {
    var trat = l.tratamento || "";
    var seletor =
      '<select class="cap-trat' + (trat ? "" : " cap-trat--vazio") + '" data-trat="' + l.id + '">' +
      '<option value=""' + (trat ? "" : " selected") + ">— só nome</option>" +
      '<option value="Sr."' + (trat === "Sr." ? " selected" : "") + ">Sr.</option>" +
      '<option value="Sra."' + (trat === "Sra." ? " selected" : "") + ">Sra.</option>" +
      "</select>";
    return '<tr class="' + (l.cinza ? "cinza" : "") + '">' +
      "<td><strong>" + esc(l.nome || "(sem nome)") + "</strong><br>" +
        '<span style="font-size:var(--fs-xs);color:var(--texto-fraco)">' +
        esc(telefoneBonito(l.telefone)) + "</span></td>" +
      "<td>" + seletor + "</td>" +
      "<td>" + esc(l.imovel || "—") +
        (l.codigo ? '<br><span style="font-size:var(--fs-xs);color:var(--texto-fraco)">cód. ' +
          esc(l.codigo) + "</span>" : "") + "</td>" +
      "<td>" + (ROTULO_SITUACAO[l.situacao] || (l.querVender ? "" : '<span class="etiqueta">—</span>')) +
        (l.querVender ? '<span class="etiqueta etiqueta--laranja">quer vender</span>' +
          (l.valorVendaPedido ? '<br><span style="font-size:var(--fs-xs)">' + esc(l.valorVendaPedido) + "</span>" : "") : "") +
        "</td>" +
      "<td>" + esc(l.contratoAte || "—") + "</td>" +
      "<td>" + (l.temOutroImovel
        ? '<span class="etiqueta etiqueta--alerta">sim</span><br>' +
          '<span style="font-size:var(--fs-xs)">' + esc(l.outrosImoveis || "") + "</span>"
        : "—") + "</td>" +
      "<td>" + (l.comOTel ? '<span class="etiqueta etiqueta--azul" title="O Tel está atendendo: a Nay não responde mais aqui">com o Tel</span><br>' : "") +
        esc(l.etapa || "—") +
        (l.optOut ? '<br><span class="etiqueta etiqueta--alerta">pediu p/ sair</span>' : "") + "</td>" +
      '<td class="num">' + esc(l.enviadas) + " / " + esc(l.recebidas) + "</td>" +
      "<td>" + esc(quando(l.ultimoEnvio)) + "</td>" +
      '<td class="col-acoes"><button class="btn-mini" type="button" data-conversa="' +
        l.id + '">Ver detalhes</button>' +
        '<button class="btn-mini" type="button" data-mudar="' + l.id + '">Mudar manualmente</button></td>' +
      "</tr>";
  }

  var pedidoAtual = 0;
  function carregarLeads() {
    var termo = (busca && busca.value || "").trim();
    var meu = ++pedidoAtual;   // resposta velha (de uma letra atras) nao pinta a tabela
    corpo.innerHTML = '<tr><td colspan="10">Carregando…</td></tr>';
    fetch(API + "/api/captacao/leads?balde=" + encodeURIComponent(baldeAtual) +
          (termo ? "&q=" + encodeURIComponent(termo) : ""))
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (itens) {
        if (meu !== pedidoAtual) return;
        leadsNaTela = {};
        itens.forEach(function (l) { leadsNaTela[l.id] = l; });
        if (buscaConta) buscaConta.textContent = termo ? itens.length + " encontrado(s)" : "";
        corpo.innerHTML = itens.length ? itens.map(linhaLead).join("")
          : '<tr><td colspan="10" style="text-align:center;color:var(--texto-fraco);padding:24px">' +
            (termo ? "Ninguém com “" + esc(termo) + "” nesta aba." : "Nenhum proprietário neste balde ainda.") +
            "</td></tr>";
      })
      .catch(function () {
        corpo.innerHTML = '<tr><td colspan="10">Não foi possível carregar.</td></tr>';
      });
  }

  /* Busca: espera a pessoa parar de digitar (300 ms) antes de perguntar. */
  var esperaBusca = null;
  if (busca) {
    busca.addEventListener("input", function () {
      clearTimeout(esperaBusca);
      esperaBusca = setTimeout(carregarLeads, 300);
    });
  }

  abas.addEventListener("click", function (evento) {
    var botao = evento.target.closest("[data-balde]");
    if (!botao) return;
    baldeAtual = botao.dataset.balde;
    Array.prototype.forEach.call(abas.children, function (b) {
      b.setAttribute("aria-selected", b === botao ? "true" : "false");
    });
    pintarAcao();
    carregarLeads();
  });

  /* Salvar correcao manual de Sr./Sra. direto na tabela. */
  corpo.addEventListener("change", function (evento) {
    var sel = evento.target.closest("[data-trat]");
    if (!sel) return;
    sel.disabled = true;
    fetch(API + "/api/captacao/lead/" + sel.dataset.trat + "/tratamento", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ tratamento: sel.value })
    })
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function () {
        sel.disabled = false;
        sel.classList.toggle("cap-trat--vazio", !sel.value);
      })
      .catch(function () { sel.disabled = false; alert("Não deu para salvar o tratamento."); });
  });

  /* ---------------------------------------------------------------- */
  /* Popup da conversa (curadoria)                                     */
  /* ---------------------------------------------------------------- */

  corpo.addEventListener("click", function (evento) {
    var botao = evento.target.closest("[data-conversa]");
    if (!botao) return;
    abrir("sobrepor-conversa");
    var alvo = document.getElementById("conversa-corpo");
    alvo.innerHTML = "Carregando…";
    fetch(API + "/api/captacao/lead/" + botao.dataset.conversa)
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (d) {
        document.getElementById("conversa-titulo").textContent =
          (d.nome || "(sem nome)") + " — " + telefoneBonito(d.telefone);
        var cabeca =
          '<div class="lead-campos">' +
          '<div class="lead-campo"><span>Imóvel</span><strong>' + esc(d.imovel || "—") + "</strong></div>" +
          '<div class="lead-campo"><span>Situação</span><strong>' + esc(d.situacao || "ainda não sabemos") + "</strong></div>" +
          '<div class="lead-campo"><span>Contrato até</span><strong>' + esc(d.contratoAte || "—") + "</strong></div>" +
          '<div class="lead-campo"><span>Etapa</span><strong>' + esc(d.etapa || "—") + "</strong></div>" +
          "</div>";
        var extras = d.outrosImoveis.length
          ? '<h3 class="lead-secao__titulo">Outros imóveis que ele citou</h3><ul class="painel__lista">' +
            d.outrosImoveis.map(function (e) {
              return '<li class="painel__item"><strong>' + esc(e.descricao) +
                "</strong><span>" + esc(e.negocio) + "</span></li>";
            }).join("") + "</ul>"
          : "";
        var conversa = d.mensagens.length
          ? '<div class="cap-conversa">' + d.mensagens.map(function (m) {
              return '<div class="cap-balao cap-balao--' + esc(m.direcao) + '">' +
                esc(m.texto || "(" + (m.origem || "sem texto") + ")") +
                '<span class="cap-balao__quando">' + esc(quando(m.em)) +
                (m.status === "Falhou" ? " — FALHOU" : "") + "</span></div>";
            }).join("") + "</div>"
          : '<p class="painel__vazio">Nenhuma mensagem ainda.</p>';
        alvo.innerHTML = cabeca + conversa + extras;
      })
      .catch(function () { alvo.innerHTML = "Não foi possível carregar a conversa."; });
  });

  /* ---------------------------------------------------------------- */
  /* Popup de importação: escolher lista, desmarcar quem não recebe    */
  /* ---------------------------------------------------------------- */

  function abrir(id) { document.getElementById(id).hidden = false; }
  function fechar(id) { document.getElementById(id).hidden = true; }

  document.addEventListener("click", function (evento) {
    var botao = evento.target.closest("[data-fechar]");
    if (botao) { fechar(botao.dataset.fechar); return; }
    // Clique no fundo escuro (fora da caixa) tambem fecha.
    if (evento.target.classList && evento.target.classList.contains("sobreposicao")) {
      evento.target.hidden = true;
    }
  });
  // Esc fecha o popup que estiver aberto.
  document.addEventListener("keydown", function (evento) {
    if (evento.key !== "Escape") return;
    Array.prototype.forEach.call(document.querySelectorAll(".sobreposicao"), function (s) { s.hidden = true; });
  });

  /* ---------------------------------------------------------------- */
  /* Mudar manualmente (ex.: passar o lead para Alugados)              */
  /* ---------------------------------------------------------------- */
  var formMudar = document.getElementById("form-mudar");
  var campoContrato = document.getElementById("mudar-contrato");
  var statusMudar = document.getElementById("mudar-status");

  var NOME_SITUACAO = { disponivel: "Disponível", alugado: "Alugado", vendido: "Já vendeu" };

  corpo.addEventListener("click", function (evento) {
    var botao = evento.target.closest("[data-mudar]");
    if (!botao) return;
    var l = leadsNaTela[botao.dataset.mudar];
    if (!l) return;
    leadMudando = l;
    document.getElementById("mudar-titulo").textContent = "Mudar manualmente — " + (l.nome || "(sem nome)");
    document.getElementById("mudar-atual").textContent =
      (l.imovel || "—") + (l.codigo ? " (cód. " + l.codigo + ")" : "") + " · hoje: " +
      (NOME_SITUACAO[l.situacao] || "sem situação") + (l.temOutroImovel ? " · tem outro imóvel" : "") +
      (l.querVender ? " · quer vender" + (l.valorVendaPedido ? " (" + l.valorVendaPedido + ")" : "") : "") +
      (l.comOTel ? " · com o Tel" : "");
    formMudar.reset();
    var atual = formMudar.querySelector('input[name="situacao"][value="' + (l.situacao || "manter") + '"]');
    if (atual) atual.checked = true;
    formMudar.elements.tem_outro_imovel.checked = !!l.temOutroImovel;
    formMudar.elements.quer_vender.checked = !!l.querVender;
    formMudar.elements.valor_venda.value = l.valorVendaPedido || "";
    formMudar.elements.humano.checked = !!l.comOTel;
    document.getElementById("mudar-valor").hidden = !l.querVender;
    formMudar.elements.contrato_ate.value = l.contratoAte || "";
    campoContrato.hidden = l.situacao !== "alugado";
    statusMudar.textContent = "";
    document.getElementById("btn-salvar-mudar").disabled = false;
    abrir("sobrepor-mudar");
  });

  formMudar.addEventListener("change", function (evento) {
    if (evento.target.name === "situacao") campoContrato.hidden = evento.target.value !== "alugado";
    if (evento.target.name === "quer_vender") document.getElementById("mudar-valor").hidden = !evento.target.checked;
  });

  formMudar.addEventListener("submit", function (evento) {
    evento.preventDefault();
    if (!leadMudando) return;
    var escolhida = formMudar.querySelector('input[name="situacao"]:checked');
    if (!escolhida) { statusMudar.textContent = "Escolha uma opção."; return; }
    var botaoSalvar = document.getElementById("btn-salvar-mudar");
    botaoSalvar.disabled = true;
    statusMudar.textContent = "Salvando…";
    fetch(API + "/api/captacao/lead/" + leadMudando.id + "/mudar", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        // "manter" = nao mexe na situacao: manda a que ja estava.
        situacao: escolhida.value === "manter" ? (leadMudando.situacao || null) : (escolhida.value || null),
        contrato_ate: escolhida.value === "alugado" ? formMudar.elements.contrato_ate.value : null,
        tem_outro_imovel: formMudar.elements.tem_outro_imovel.checked,
        quer_vender: formMudar.elements.quer_vender.checked,
        valor_venda: formMudar.elements.quer_vender.checked ? formMudar.elements.valor_venda.value : null,
        humano: formMudar.elements.humano.checked,
        quem: (window.USUARIO_ATUAL || "admin")
      })
    })
      .then(function (r) { return r.json().then(function (j) { return { ok: r.ok, j: j }; }); })
      .then(function (res) {
        if (!res.ok) throw new Error(res.j.erro || "erro");
        fechar("sobrepor-mudar");
        carregarResumo();
        carregarLeads();
      })
      .catch(function (e) {
        botaoSalvar.disabled = false;
        statusMudar.textContent = "Não salvou: " + e.message;
      });
  });

  acaoAba.addEventListener("click", function (evento) {
    if (evento.target.closest("#btn-exportar")) {
      // Deixa o navegador baixar direto: o CSV vem com Content-Disposition.
      window.location.href = API + "/api/captacao/exportar?balde=" +
        encodeURIComponent(baldeAtual);
      return;
    }
    if (!evento.target.closest("#btn-importar")) return;
    abrir("sobrepor-importar");
    var alvo = document.getElementById("importar-corpo");
    alvo.innerHTML = "Carregando listas…";
    fetch(API + "/api/listas")
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (listas) {
        if (!listas.length) {
          alvo.innerHTML = '<p class="painel__vazio">Nenhuma lista criada ainda. ' +
            'Crie uma nos filtros de vencimento (Imóveis, Proprietários, Locação).</p>';
          return;
        }
        alvo.innerHTML =
          "<p>Escolha a lista. Na etapa seguinte você desmarca quem não deve receber.</p>" +
          '<ul class="painel__lista">' + listas.map(function (l) {
            return '<li class="painel__item"><strong>' + esc(l.nome) + "</strong>" +
              "<span>" + esc(l.area) + " — " + esc(l.quantidade) + " itens — " +
              esc(quando(l.criado_em)) + "</span>" +
              '<button class="btn-mini" type="button" data-previa="' + l.id + '">Usar esta</button></li>';
          }).join("") + "</ul>";
      })
      .catch(function () { alvo.innerHTML = "Não foi possível carregar as listas."; });
  });

  document.getElementById("importar-corpo").addEventListener("click", function (evento) {
    var usar = evento.target.closest("[data-previa]");
    if (usar) return mostrarPrevia(usar.dataset.previa);

    var confirmar = evento.target.closest("#btn-confirmar-import");
    if (confirmar) return confirmarImportacao();

    var marcarTodos = evento.target.closest("#marcar-todos");
    if (marcarTodos) {
      var caixas = document.querySelectorAll("#importar-corpo input[data-codigo]");
      Array.prototype.forEach.call(caixas, function (c) { c.checked = marcarTodos.checked; });
      atualizarContagem();
    }
  });

  document.getElementById("importar-corpo").addEventListener("change", function (evento) {
    if (evento.target.matches("input[data-codigo]")) atualizarContagem();
  });

  function atualizarContagem() {
    var marcadas = document.querySelectorAll("#importar-corpo input[data-codigo]:checked").length;
    var alvo = document.getElementById("contagem-import");
    if (alvo) alvo.textContent = marcadas + " de " + candidatosAbertos.filter(function (c) {
      return !c.bloqueio;
    }).length + " entram na campanha";
  }

  function mostrarPrevia(listaId) {
    var alvo = document.getElementById("importar-corpo");
    alvo.innerHTML = "Montando a prévia…";
    fetch(API + "/api/captacao/previa/" + listaId)
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (d) {
        listaAberta = d.lista.id;
        candidatosAbertos = d.candidatos;
        document.getElementById("importar-titulo").textContent =
          "Quem entra na campanha — " + d.lista.nome;

        var linhas = d.candidatos.map(function (c) {
          if (c.bloqueio) {
            return "<tr><td></td><td>" + esc(c.nome || "(sem nome)") + "</td>" +
              "<td>" + esc(c.telefone_bruto || "—") + "</td>" +
              "<td>" + esc(c.condominio || c.bairro || "—") + "</td>" +
              '<td class="cap-bloqueado">' + esc(c.bloqueio) + "</td></tr>";
          }
          return "<tr><td><input type=\"checkbox\" checked data-codigo=\"" + esc(c.codigo) + "\"></td>" +
            "<td>" + esc(c.nome || "(sem nome)") +
              (c.tratamento
                ? ' <span class="etiqueta">' + esc(c.tratamento) + "</span>"
                : ' <span class="etiqueta etiqueta--alerta" title="não deu para deduzir o gênero pelo nome; a mensagem vai sem Sr./Sra. e você pode corrigir depois na tabela">só nome</span>') +
            "</td>" +
            "<td>" + esc(telefoneBonito(c.telefone)) + "</td>" +
            "<td>" + esc(c.condominio || c.bairro || "—") + "</td>" +
            "<td>" + esc(c.imovel_desc || "") + "</td></tr>";
        }).join("");

        alvo.innerHTML =
          "<p>Desmarque quem <strong>não</strong> deve receber. Quem está em itálico não pode " +
          "entrar, e o motivo está na última coluna — essas linhas nem contam.</p>" +
          '<p id="contagem-import" style="font-weight:600;margin:8px 0"></p>' +
          '<div class="cap-candidatos"><table class="tabela"><thead><tr>' +
          '<th><input type="checkbox" id="marcar-todos" checked title="marcar/desmarcar todos"></th>' +
          "<th>Nome</th><th>Telefone</th><th>Condomínio / bairro</th><th>Como entra na mensagem</th>" +
          "</tr></thead><tbody>" + linhas + "</tbody></table></div>" +
          '<div class="popup-imovel__rodape" style="display:flex;gap:8px;justify-content:flex-end">' +
          '<button class="btn-neutro" type="button" data-fechar="sobrepor-importar">Cancelar</button>' +
          '<button class="btn-azul" type="button" id="btn-confirmar-import">Adicionar à campanha</button>' +
          "</div>";
        atualizarContagem();
      })
      .catch(function () { alvo.innerHTML = "Não foi possível montar a prévia."; });
  }

  function confirmarImportacao() {
    // O servidor remonta os candidatos do banco: daqui só vai quem foi
    // DESMARCADO. Nome e telefone que estão na tela não são usados para
    // escrever nada -- se a tela estiver velha, quem manda é o banco.
    var excluidos = candidatosAbertos.filter(function (c) { return !c.bloqueio; })
      .map(function (c) { return c.codigo; })
      .filter(function (codigo) {
        var caixa = document.querySelector('#importar-corpo input[data-codigo="' + codigo + '"]');
        return caixa && !caixa.checked;
      });

    var botao = document.getElementById("btn-confirmar-import");
    botao.disabled = true;
    botao.textContent = "Adicionando…";

    fetch(API + "/api/captacao/importar", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        lista_id: listaAberta,
        excluidos: excluidos,
        quem: (window.USUARIO_ATUAL || "admin")
      })
    })
      .then(function (r) { return r.json().then(function (j) { return { ok: r.ok, j: j }; }); })
      .then(function (res) {
        if (!res.ok) throw new Error(res.j.erro || "erro");
        fechar("sobrepor-importar");
        alert(res.j.importados + " proprietário(s) entraram na campanha.\n" +
          (res.j.bloqueados ? res.j.bloqueados + " não puderam entrar (sem telefone, repetidos ou já na campanha).\n" : "") +
          (res.j.desmarcados ? res.j.desmarcados + " você desmarcou." : ""));
        carregarResumo();
        carregarLeads();
      })
      .catch(function (e) {
        botao.disabled = false;
        botao.textContent = "Adicionar à campanha";
        alert("Não deu para adicionar: " + e.message);
      });
  }

  /* ---------------------------------------------------------------- */

  if (!API) {
    corpo.innerHTML = "<tr><td colspan=\"10\">config.js não define API_BASE.</td></tr>";
    return;
  }
  abas.querySelector('[data-balde=""]').setAttribute("aria-selected", "true");
  pintarAcao();
  carregarResumo();
  carregarLeads();
})();
