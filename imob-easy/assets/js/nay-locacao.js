/* ==========================================================================
   Imob Easy — Painel da Nay de Locação (admin)

   Pedido do Tel (15/09/2026): "quero um painel de métricas de resposta, e
   acesso a toda configuração dela, prompt, regras, tudo lá -- se eu altero lá,
   altera no n8n".

   Lê tudo de /api/nai/estado. Salvar uma regra muda `nai_config`; salvar o
   prompt muda `nai_prompt`. O fluxo do n8n lê os dois do banco a cada mensagem,
   então a mudança vale na resposta seguinte, sem reiniciar nada.
   ========================================================================== */
(function () {
  "use strict";

  var API = window.API_BASE || "";
  var estado = null;

  function esc(t) {
    return String(t == null ? "" : t)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }

  function elemento(id) { return document.getElementById(id); }

  function tempo(seg) {
    if (seg == null) return "—";
    if (seg < 60) return Math.round(seg) + "s";
    return Math.floor(seg / 60) + "min " + Math.round(seg % 60) + "s";
  }

  function cartao(rotulo, valor, nota) {
    // mesmas classes da pagina "Relatorios das duas Nays"
    return '<div class="painel-cartao">' +
           '<div class="painel-cartao__n">' + esc(valor) + "</div>" +
           '<div class="painel-cartao__r">' + esc(rotulo) + (nota ? " · " + esc(nota) : "") + "</div>" +
           "</div>";
  }

  function tabela(alvo, colunas, linhas, celula) {
    var cabecalho = "<thead><tr>" + colunas.map(function (c) { return "<th>" + esc(c) + "</th>"; }).join("") + "</tr></thead>";
    var corpo = "<tbody>" + (linhas.length
      ? linhas.map(function (l, i) { return "<tr>" + celula(l, i) + "</tr>"; }).join("")
      : '<tr><td colspan="' + colunas.length + '">Nada por aqui ainda.</td></tr>') + "</tbody>";
    alvo.innerHTML = cabecalho + corpo;
  }

  /* ---------------------------------------------------------- MÉTRICAS ---- */
  function desenharMetricas() {
    var dias = estado.metricas || [];
    var hoje = dias[0] || {};
    var sete = dias.slice(0, 7).reduce(function (a, d) {
      a.turnos += Number(d.turnos || 0);
      a.respondidos += Number(d.turnos_respondidos || 0);
      a.escalados += Number(d.escalados_ao_tel || 0);
      a.fotos += Number(d.fotos_enviadas || 0);
      a.barradas += Number(d.mensagens_barradas || 0);
      a.pessoas += Number(d.pessoas || 0);
      return a;
    }, { turnos: 0, respondidos: 0, escalados: 0, fotos: 0, barradas: 0, pessoas: 0 });

    elemento("nay-cartoes-hoje").innerHTML =
      cartao("Mensagens atendidas", hoje.turnos || 0, hoje.pessoas ? hoje.pessoas + " pessoas" : "") +
      cartao("Respondidas", hoje.turnos_respondidos || 0, (hoje.turnos ? Math.round((hoje.turnos_respondidos || 0) * 100 / hoje.turnos) + "%" : "")) +
      cartao("Tempo até responder", tempo(hoje.segundos_ate_responder), "pior: " + tempo(hoje.pior_resposta_seg)) +
      cartao("Subiram para o Tel", hoje.escalados_ao_tel || 0) +
      cartao("Fotos enviadas", hoje.fotos_enviadas || 0);

    elemento("nay-cartoes-sete").innerHTML =
      cartao("Mensagens atendidas", sete.turnos) +
      cartao("Respondidas", sete.respondidos, (sete.turnos ? Math.round(sete.respondidos * 100 / sete.turnos) + "%" : "")) +
      cartao("Subiram para o Tel", sete.escalados) +
      cartao("Fotos enviadas", sete.fotos) +
      cartao("Mensagens barradas", sete.barradas, "cortadas antes de sair");

    tabela(elemento("nay-tab-metricas"),
      ["Dia", "Atendidas", "Pessoas", "Respondidas", "Tempo médio", "Pior", "Ao Tel", "Visita", "Fotos", "Barradas"],
      dias,
      function (d) {
        return "<td>" + esc(d.dia) + "</td><td>" + esc(d.turnos) + "</td><td>" + esc(d.pessoas) + "</td>" +
               "<td>" + esc(d.turnos_respondidos) + "</td><td>" + esc(tempo(d.segundos_ate_responder)) + "</td>" +
               "<td>" + esc(tempo(d.pior_resposta_seg)) + "</td><td>" + esc(d.escalados_ao_tel) + "</td>" +
               "<td>" + esc(d.falaram_de_visita) + "</td><td>" + esc(d.fotos_enviadas) + "</td>" +
               "<td>" + esc(d.mensagens_barradas) + "</td>";
      });

    tabela(elemento("nay-tab-conferencia"),
      ["#", "Conferência", "Agiu", "Mudou", "Cortou", "Parou", "Passagens", "Última vez"],
      estado.conferencias || [],
      function (c) {
        return "<td>" + esc(c.ordem) + "</td><td>" + esc(c.etapa) + "</td><td>" + esc(c.agiu) + "</td>" +
               "<td>" + esc(c.mudou) + "</td><td>" + esc(c.cortou) + "</td><td>" + esc(c.parou) + "</td>" +
               "<td>" + esc(c.passagens) + "</td><td>" + esc((c.ultima_vez || "").replace("T", " ").slice(0, 16)) + "</td>";
      });
  }

  /* ------------------------------------------------------------ REGRAS ---- */
  function desenharConfig() {
    tabela(elemento("nay-tab-config"),
      ["Regra", "Valor", "", "O que ela faz"],
      estado.config || [],
      function (c) {
        var campo = c.editavel
          ? '<input class="entrada" data-chave="' + esc(c.chave) + '" value="' + esc(c.valor) + '">'
          : "<code>" + esc(c.valor) + "</code>";
        var botao = c.editavel
          ? '<button class="btn-mini" type="button" data-salvar="' + esc(c.chave) + '">Salvar</button>'
          : "";
        return "<td><strong>" + esc(c.chave) + "</strong></td><td>" + campo + "</td><td>" + botao + "</td>" +
               "<td>" + esc(c.descricao || "") + "</td>";
      });
  }

  document.addEventListener("click", function (e) {
    var botao = e.target.closest("[data-salvar]");
    if (!botao) return;
    var chave = botao.dataset.salvar;
    var campo = document.querySelector('[data-chave="' + chave + '"]');
    if (!campo) return;
    botao.disabled = true;
    fetch(API + "/api/nai/config", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ chave: chave, valor: campo.value })
    }).then(function (r) { return r.json().then(function (j) { return { ok: r.ok, j: j }; }); })
      .then(function (res) {
        botao.disabled = false;
        botao.textContent = res.ok && res.j.ok ? "Salvo" : (res.j.erro || "Erro");
        setTimeout(function () { botao.textContent = "Salvar"; }, 2500);
      })
      .catch(function () { botao.disabled = false; botao.textContent = "Sem conexão"; });
  });

  /* ------------------------------------------------------------ PROMPT ---- */
  var papelAtual = "corretor";
  var versaoAtual = null;

  function carregarPrompt() {
    papelAtual = elemento("nay-papel").value;
    elemento("nay-prompt-info").textContent = "carregando…";
    fetch(API + "/api/nai/prompt/" + papelAtual)
      .then(function (r) { return r.json(); })
      .then(function (p) {
        elemento("nay-prompt").value = p.texto || "";
        versaoAtual = p.versao;
        elemento("nay-prompt-info").textContent =
          " versão " + p.versao + " · " + (p.texto || "").length + " caracteres · salvo por " +
          (p.atualizado_por || "—") + " em " + String(p.atualizado_em || "").replace("T", " ").slice(0, 16);
      })
      .catch(function () { elemento("nay-prompt-info").textContent = "não consegui carregar"; });
  }

  function salvarPrompt() {
    var aviso = elemento("nay-prompt-aviso");
    aviso.textContent = "salvando…";
    fetch(API + "/api/nai/prompt/" + papelAtual, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ texto: elemento("nay-prompt").value, versao: versaoAtual, por: "painel" })
    }).then(function (r) { return r.json().then(function (j) { return { ok: r.ok, j: j }; }); })
      .then(function (res) {
        if (res.ok && res.j.ok) {
          versaoAtual = res.j.versao;
          aviso.textContent = "salvo — vale na próxima mensagem (versão " + res.j.versao + ")";
        } else {
          aviso.textContent = res.j.erro || "não salvou";
        }
      })
      .catch(function () { aviso.textContent = "sem conexão"; });
  }


  /* ---------------------------------------------------------- POR IMÓVEL ---- */
  /* Quantas vezes cada imóvel foi oferecido e quantas visitas saíram dele
     (Tel, 15/09). O filtro é só de texto, no que já veio da API -- nada de ida
     e volta ao servidor a cada tecla. */
  function desenharImoveis() {
    var termo = (elemento("nay-filtro-imovel").value || "").trim().toLowerCase();
    var linhas = (estado.imoveis || []).filter(function (i) {
      if (!termo) return true;
      return [i.codigo, i.condominio_nome, i.bairro].join(" ").toLowerCase().indexOf(termo) >= 0;
    });
    tabela(elemento("nay-tab-imoveis"),
      ["Código", "Condomínio", "Bairro", "Aluguel", "Oferecido", "Fotos", "Perguntaram", "Visitas", "Confirmadas", "Em pé", "Última vez"],
      linhas,
      function (i) {
        return "<td><strong>" + esc(i.codigo) + "</strong></td>" +
               "<td>" + esc(i.condominio_nome || "—") + "</td><td>" + esc(i.bairro || "—") + "</td>" +
               "<td>" + (i.aluguel ? "R$ " + Number(i.aluguel).toLocaleString("pt-BR") : "—") + "</td>" +
               "<td>" + esc(i.vezes_mandado) + "</td><td>" + esc(i.fotos_enviadas) + "</td>" +
               "<td>" + esc(i.pessoas_perguntaram) + "</td>" +
               "<td>" + esc(i.visitas_pedidas) + "</td><td>" + esc(i.visitas_confirmadas) + "</td>" +
               "<td>" + esc(i.visitas_em_pe) + "</td>" +
               "<td>" + esc(String(i.ultima_vez_mandado || "").replace("T", " ").slice(0, 16) || "—") + "</td>";
      });
  }

  /* -------------------------------------------------- ÚLTIMAS RESPOSTAS ---- */
  function desenharTurnos() {
    tabela(elemento("nay-tab-turnos"),
      ["Quando", "Papel", "Imóvel", "Ele disse", "Ela respondeu", "Fotos", "Barradas", "Conferências que agiram"],
      estado.turnos || [],
      function (t) {
        return "<td>" + esc(String(t.quando || "").replace("T", " ").slice(5, 16)) + "</td>" +
               "<td>" + esc(t.papel) + "</td><td>" + esc(t.imovel || "—") + "</td>" +
               "<td>" + esc(t.ele_disse) + "</td><td>" + esc(t.ela_respondeu || "(calada)") + "</td>" +
               "<td>" + esc(t.fotos) + "</td><td>" + esc(t.barradas) + "</td>" +
               "<td>" + esc(t.conferencias_que_agiram || "—") + "</td>";
      });
  }



  /* ---------------------------------------------------------------- FILA ---- */
  /* O botão de pausa e a fila das duas pontas (Tel, 15/09). A pausa é a mesma
     chave que o comando PARAR ATENDIMENTO do WhatsApp mexe -- um lugar só, para
     o site e o WhatsApp nunca discordarem sobre se ela está atendendo.

     Carga própria e recarregada sozinha a cada 20s: a fila é a tela que se olha
     quando algo parece travado, e uma fila velha engana mais do que ajuda. */
  var fila = null;

  function desenharFila() {
    if (!fila) return;
    var r = fila.resumo || {};
    var e = fila.estado || {};
    var parada = e.pausada !== "nao";

    var botao = elemento("nay-botao-pausa");
    botao.textContent = parada ? "▶ Voltar a atender" : "⏸ Pausar";
    botao.dataset.pausar = parada ? "false" : "true";
    elemento("nay-pausa-aviso").textContent = parada
      ? "Parada. As mensagens continuam chegando e ficam guardadas; ela não responde ninguém até você dar play."
      : "";

    elemento("nay-fila-cartoes").innerHTML =
      cartao("A sair", r.a_sair || 0, r.mais_velha_segundos ? "a mais velha há " + tempo(r.mais_velha_segundos) : "") +
      cartao("Saindo agora", r.saindo || 0) +
      cartao("Chegando", r.chegando || 0, "ainda sem resposta") +
      cartao("Barradas (24h)", r.barradas_24h || 0, "com o motivo abaixo") +
      cartao("Conversas com o Tel", r.conversas_com_o_tel || 0, "ela não fala nelas") +
      cartao("Conversas liberadas", r.conversas_liberadas || 0, "pediram fotos ou imóveis");

    tabela(elemento("nay-tab-fila"),
      ["Quando", "Lado", "Para quem", "Texto", "Estado", "Por quê"],
      fila.fila || [],
      function (f) {
        return "<td>" + esc(String(f.quando || "").replace("T", " ").slice(5, 16)) + "</td>" +
               "<td>" + esc(f.lado === "entrada" ? "chegou" : f.papel) + "</td>" +
               "<td>" + esc(f.quem || "—") + "</td>" +
               "<td>" + esc(f.texto || "—") + "</td>" +
               "<td>" + esc(f.estado) + "</td>" +
               "<td>" + esc(f.bloqueio || f.motivo || "—") + "</td>";
      });

    tabela(elemento("nay-tab-porta"),
      ["Quando", "Quem", "Ele disse", "A porta decidiu", ""],
      fila.porta || [],
      function (p) {
        var marca = p.com_o_tel ? "com o Tel" : (p.ja_liberada ? "liberada" : "");
        return "<td>" + esc(String(p.quando || "").replace("T", " ").slice(5, 16)) + "</td>" +
               "<td>" + esc(p.quem || "—") + "</td>" +
               "<td>" + esc(p.ele_disse || "—") + "</td>" +
               "<td>" + esc(p.porta || "—") + "</td>" +
               "<td>" + esc(marca) + "</td>";
      });
  }

  function carregarFila() {
    fetch(API + "/api/nai/fila")
      .then(function (r) { return r.json(); })
      .then(function (dados) { fila = dados; desenharFila(); })
      .catch(function () { elemento("nay-pausa-aviso").textContent = "não consegui ler a fila."; });
  }

  /* o botão de pausa / play */
  document.addEventListener("click", function (ev) {
    var botao = ev.target.closest("#nay-botao-pausa");
    if (!botao) return;
    var pausar = botao.dataset.pausar === "true";
    botao.disabled = true;
    fetch(API + "/api/nai/pausa", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ pausar: pausar })
    }).then(function (r) { return r.json(); })
      .then(function (j) {
        botao.disabled = false;
        if (j.ok) { carregarFila(); carregar(); }
        else { elemento("nay-pausa-aviso").textContent = j.erro || "não consegui mudar"; }
      })
      .catch(function () { botao.disabled = false; elemento("nay-pausa-aviso").textContent = "sem conexão"; });
  });


  /* -------------------------------------------------------------- ENVIOS ---- */
  /* Tudo que saiu por este número, dizendo QUEM mandou (Tel, 15/09). A pergunta
     "foi a IA que mandou isso?" custou quatro consultas no banco no dia em que
     ele perguntou; aqui ela fica respondida na tela. */
  var envios = null;

  function desenharEnvios() {
    if (!envios) return;
    var r = envios.resumo || {};
    elemento("nay-envios-cartoes").innerHTML =
      cartao("Enviadas", r.total || 0, r.pessoas ? r.pessoas + " pessoas" : "") +
      cartao("A Nay escreveu", r.da_nay || 0,
             (r.total ? Math.round((r.da_nay || 0) * 100 / r.total) + "%" : "")) +
      cartao("Alguém digitou", r.de_gente || 0) +
      cartao("Nas últimas 24h", r.nas_24h || 0, (r.da_nay_24h || 0) + " dela");
    desenharTabelaEnvios();
  }

  function desenharTabelaEnvios() {
    var termo = (elemento("nay-envios-filtro").value || "").trim().toLowerCase();
    var linhas = (envios.envios || []).filter(function (e) {
      if (!termo) return true;
      return [e.para_quem, e.texto].join(" ").toLowerCase().indexOf(termo) >= 0;
    });
    tabela(elemento("nay-tab-envios"),
      ["Quando", "Para quem", "Quem mandou", "Texto", "Motivo"],
      linhas,
      function (e) {
        return "<td>" + esc(String(e.quando || "").replace("T", " ").slice(5, 16)) + "</td>" +
               "<td>" + esc(e.para_quem || "—") + "</td>" +
               "<td>" + esc(e.quem_mandou) + "</td>" +
               "<td>" + esc(e.texto || "—") + "</td>" +
               "<td>" + esc(e.motivo === "-" ? "" : e.motivo) + "</td>";
      });
  }

  function carregarEnvios() {
    fetch(API + "/api/nai/envios")
      .then(function (r) { return r.json(); })
      .then(function (d) { envios = d; desenharEnvios(); })
      .catch(function () {});
  }

  /* -------------------------------------------------------------- CARGA ---- */
  function carregar() {
    fetch(API + "/api/nai/estado")
      .then(function (r) { return r.json(); })
      .then(function (dados) {
        estado = dados;
        var config = {};
        (dados.config || []).forEach(function (c) { config[c.chave] = c.valor; });
        var ligada = config.modo && config.modo !== "desligado" && config.pausada === "nao";
        elemento("nay-selo").textContent = ligada ? (config.modo === "teste" ? "em teste" : "atendendo") : "parada";
        elemento("nay-selo").className = "selo " + (ligada ? (config.modo === "teste" ? "selo--teste" : "selo--on") : "selo--off");
        elemento("nay-nota").textContent =
          "Modo " + (config.modo || "?") + (config.modo === "teste" ? " (só " + (config.numeros_teste || "") + ")" : "") +
          " · janela " + (config.janela_inicio || "?") + " às " + (config.janela_fim || "?") +
          " · envio " + (config.envio_simulado === "sim" ? "simulado" : "real") +
          " · prompt do corretor com " + ((dados.prompts || []).filter(function (p) { return p.papel === "corretor"; })[0] || {}).caracteres + " caracteres";
        desenharMetricas();
        desenharConfig();
        desenharTurnos();
        desenharImoveis();
        carregarPrompt();
      })
      .catch(function () {
        elemento("nay-nota").textContent = "não consegui falar com a API.";
      });
  }

  document.addEventListener("DOMContentLoaded", function () {
    elemento("nay-papel").addEventListener("change", carregarPrompt);
    elemento("nay-salvar-prompt").addEventListener("click", salvarPrompt);
    elemento("nay-filtro-imovel").addEventListener("input", desenharImoveis);
    elemento("nay-envios-filtro").addEventListener("input", desenharTabelaEnvios);
    carregar();
    carregarFila();
    carregarEnvios();
    // a fila se recarrega sozinha: e a tela de quem esta olhando algo travar
    setInterval(carregarFila, 20000);
  });
})();
