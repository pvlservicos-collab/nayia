/* ==========================================================================
   Agentes › Hermes (13/10/2026, Pedro: "um quadrado para cada agente do hermes ... controlar o navegador deles,
   mandar msg, tudo por essa mesma tela para cada um, todas as funções disponíveis eu quero ali").
   Cada quadrado abre a mesa do agente: conversa à esquerda; à direita o navegador dele ao vivo (dá para clicar e
   digitar), as tarefas agendadas, skills e ferramentas, memória e logs. Em cima, reiniciar/parar o serviço.
   Tudo passa por /admin/api/hermes (senha do admin) → ponte na VPS2 (nay-agentes/hermes-painel/ponte.py).
   13/10, à noite (Pedro: "TIRA ESSES hermes de la ... crie um para acessar esse site aqui https://conta.olx.com.br/acesso
   ... não vi o terminal onde digito ... eu vou guiando ele até ele estar bom"): os três Hermes saíram; ficou o Agente
   OLX, cujo navegador é um Chrome no computador de quem usa (a OLX bloqueia o da VPS). A caixa de escrever ganhou
   rótulo e a conversa vazia explica como funciona, com exemplos.
   ========================================================================== */
(function () {
  "use strict";
  var grade = document.getElementById("hm-grade");
  if (!grade) return;

  var ICONE = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="8" width="16" height="11" rx="3"/><path d="M12 8V4M9 13h.01M15 13h.01M9 16h6M2 13v2M22 13v2"/></svg>';
  var TONS = [["#15161a", "#3a3c44"], ["#1d1f24", "#44474f"], ["#2d2f36", "#585b64"]];
  var NOME_PLAT = { telegram: "Telegram", whatsapp: "WhatsApp", discord: "Discord", slack: "Slack" };
  var EST_PLAT = { connected: "conectado", disconnected: "desconectado", retrying: "reconectando", connecting: "conectando", fatal: "com erro" };
  var FERRAMENTA = { browser_navigate: "Abrir página", browser_click: "Clicar", browser_type: "Digitar", browser_snapshot: "Ler a página",
    browser_scroll: "Rolar", browser_back: "Voltar", browser_press: "Tecla", browser_vision: "Olhar a tela", browser_get_images: "Imagens da página",
    browser_console: "Console da página", browser_cdp: "Comando no navegador", terminal: "Terminal", process: "Processo", web_search: "Buscar na web",
    web_extract: "Ler página da web", read_file: "Ler arquivo", write_file: "Gravar arquivo", patch: "Editar arquivo", search_files: "Procurar em arquivos",
    memory: "Memória", todo: "Lista de passos", execute_code: "Rodar código", delegate_task: "Subagente", skill_view: "Ler skill", skills_list: "Listar skills",
    skill_manage: "Editar skill", session_search: "Procurar em conversas", vision_analyze: "Analisar imagem", cronjob: "Tarefa agendada" };
  var ESCOLHA = { once: "Permitir uma vez", session: "Permitir nesta conversa", always: "Permitir sempre", deny: "Negar" };
  var TECLAS = ["Enter", "Backspace", "Tab", "Escape", "Delete", "ArrowLeft", "ArrowUp", "ArrowRight", "ArrowDown", "Home", "End", "PageUp", "PageDown"];

  var agentes = [], aberto = null, mesa = null, est = {};

  function esc(t) { return String(t == null ? "" : t).replace(/[&<>"']/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]; }); }
  function mb(b) { return b >= 1073741824 ? (b / 1073741824).toFixed(1) + " GB" : Math.round((b || 0) / 1048576) + " MB"; }
  function haQuanto(s) {
    if (!s || s < 0) return "—";
    var m = Math.round(s / 60);
    if (m < 60) return m + " min";
    var h = Math.floor(m / 60);
    return h < 48 ? h + " h " + (m % 60) + " min" : Math.floor(h / 24) + " dias";
  }
  function quando(v) {
    if (!v) return "—";
    var d = new Date(typeof v === "number" ? v * 1000 : v);
    return isNaN(d) ? "—" : d.toLocaleString("pt-BR", { timeZone: "America/Manaus", day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });
  }
  // o texto do agente: blocos de código, `código`, **negrito**, links
  function fmt(t) {
    return esc(t).split("```").map(function (parte, i) {
      if (i % 2) return "<pre>" + parte.replace(/^[a-z]*\n/, "") + "</pre>";
      return parte.replace(/`([^`\n]+)`/g, "<code>$1</code>").replace(/\*\*([^*\n]+)\*\*/g, "<b>$1</b>")
        .replace(/(https?:\/\/[^\s<)]+)/g, '<a href="$1" target="_blank" rel="noopener noreferrer">$1</a>').replace(/\n/g, "<br>");
    }).join("");
  }
  function $(sel) { return mesa.querySelector(sel); }

  function api(rota, corpo) {
    var o = { credentials: "same-origin", headers: {} };
    if (corpo !== undefined) {
      o.method = "POST";
      o.headers["Content-Type"] = "application/json";
      o.headers["X-Painel-Hermes"] = "1";   // a rota só aceita escrita vinda desta tela
      o.body = JSON.stringify(corpo);
    }
    return fetch("api/hermes/" + rota, o).then(function (r) {
      return r.json().catch(function () { return {}; }).then(function (d) {
        if (!r.ok) throw new Error(d.erro || ("erro " + r.status));
        return d;
      });
    });
  }
  function doAgente(rota, corpo) { return api("agentes/" + encodeURIComponent(aberto) + "/" + rota, corpo); }
  function agente(id) { return agentes.filter(function (a) { return a.id === (id || aberto); })[0]; }

  /* ---------------------------------------------------------------- os quadrados */
  function estadoDe(a) {
    if (a.servico.bloqueado) return ["bloqueado", "ag-estado--mudo"];
    if (!a.servico.ativo) return ["parado", "ag-estado--parado"];
    if (a.trabalhando) return ["trabalhando", "hm-estado--trab"];
    return ["no ar", ""];
  }
  function fichas(a) {
    var f = a.modelo ? "<span>" + esc(a.modelo) + "</span>" : "";
    Object.keys(a.plataformas || {}).forEach(function (n) {
      var s = a.plataformas[n];
      f += '<span' + (s === "connected" ? "" : ' class="hm-ficha--alerta"') + ">" + esc(NOME_PLAT[n] || n) + " " + esc(EST_PLAT[s] || s || "?") + "</span>";
    });
    if (a.navegador.tem) f += "<span" + (a.navegador.no_pc && !a.navegador.ligado ? ' class="hm-ficha--alerta"' : "") + ">navegador " + (a.navegador.no_pc ? "do seu computador " : "") +
      (a.navegador.ligado ? "ligado" + (a.navegador.mem ? " · " + mb(a.navegador.mem) : "") : "desligado") + "</span>";
    return f + "<span><b>" + a.tarefas + "</b> " + (a.tarefas === 1 ? "tarefa agendada" : "tarefas agendadas") + "</span>";
  }
  function quadrado(a, i, agora) {
    var e = estadoDe(a), tom = TONS[i % TONS.length];
    return '<article class="ag-card hm-card' + (a.servico.ativo ? "" : " ag-card--parado") + '" style="--ag:' + tom[0] + ";--ag2:" + tom[1] + '">' +
      '<div class="ag-topo"><div class="ag-icone">' + ICONE + '</div><div><div class="ag-nome">' + esc(a.nome.replace(/^Hermes\s*·\s*/, "")) + '</div><span class="ag-onde">perfil ' + esc(a.id) + "</span></div>" +
      '<span class="ag-estado ' + e[1] + '">' + e[0] + "</span></div>" +
      '<p class="ag-faz">' + esc(a.faz) + "</p>" +
      '<div class="ag-hoje">' + fichas(a) + "</div>" +
      '<dl class="ag-uso"><div><dt>Memória agora</dt><dd>' + (a.servico.ativo ? mb(a.servico.mem) : "—") + "</dd></div>" +
        "<div><dt>No ar há</dt><dd>" + (a.servico.ativo ? haQuanto(agora - a.servico.desde) : "—") + "</dd></div></dl>" +
      '<button type="button" class="hm-abrir" data-hm-abrir="' + esc(a.id) + '">Abrir e conversar <span aria-hidden="true">→</span></button></article>';
  }
  function lerAgentes() {
    return api("agentes").then(function (d) {
      agentes = d.agentes || [];
      grade.innerHTML = agentes.map(function (a, i) { return quadrado(a, i, d.agora); }).join("") || '<p class="ag-vazio">Nenhum Hermes configurado na ponte.</p>';
      if (aberto) cabecalho();
    }).catch(function (e) {
      if (!agentes.length) grade.innerHTML = '<p class="ag-vazio">Não consegui falar com os Hermes: ' + esc(e.message) + "</p>";
    });
  }
  grade.addEventListener("click", function (e) {
    var b = e.target.closest("[data-hm-abrir]");
    if (b) abrir(b.getAttribute("data-hm-abrir"));
  });
  lerAgentes();
  setInterval(function () { if (!document.hidden) lerAgentes(); }, 12000);

  /* ---------------------------------------------------------------- a mesa do agente */
  function montarMesa() {
    mesa = document.createElement("div");
    mesa.className = "hm-mesa";
    mesa.setAttribute("role", "dialog");
    mesa.setAttribute("aria-modal", "true");
    mesa.setAttribute("data-estado-proprio", "");   // o layout.js não mexe nos botões daqui
    mesa.hidden = true;
    mesa.innerHTML =
      '<div class="hm-mesa__caixa">' +
      '<header class="hm-topo"><div class="ag-icone">' + ICONE + '</div>' +
        '<div class="hm-topo__quem"><div class="hm-topo__nome"></div><div class="hm-topo__sub"></div></div>' +
        '<span class="ag-estado"></span>' +
        '<div class="hm-topo__acoes"><button type="button" class="hm-bt" data-hm-servico="reiniciar">Reiniciar</button>' +
          '<button type="button" class="hm-bt" data-hm-servico="alternar">Parar</button>' +
          '<button type="button" class="hm-bt hm-bt--fechar" data-hm-fechar aria-label="Fechar">✕</button></div></header>' +
      '<div class="hm-troca"><button type="button" class="hm-troca__bt hm-troca__bt--ativo" data-hm-troca="conversa">Conversa</button>' +
        '<button type="button" class="hm-troca__bt" data-hm-troca="lado">Navegador e funções</button></div>' +
      '<div class="hm-corpo" data-hm-vendo="conversa">' +
        '<section class="hm-conversa" aria-label="Conversa">' +
          '<div class="hm-conversa__barra"><select class="hm-sessoes" aria-label="Conversas"></select>' +
            '<button type="button" class="hm-bt" data-hm-nova>+ Nova</button></div>' +
          '<div class="hm-msgs" aria-live="polite"></div>' +
          '<p class="hm-conversa__aviso" hidden></p>' +
          '<form class="hm-escrever"><label class="hm-escrever__rotulo" for="hm-campo">Escreva aqui o que o agente deve fazer</label>' +
            '<div class="hm-escrever__linha"><textarea id="hm-campo" rows="3" placeholder="Ex.: abra a OLX e me diga quantos anúncios ativos eu tenho. Enter envia; Shift+Enter quebra a linha." aria-label="Mensagem"></textarea>' +
            '<button type="submit" class="hm-bt hm-bt--forte">Enviar</button>' +
            '<button type="button" class="hm-bt hm-bt--perigo" data-hm-parar hidden>Parar</button></div></form>' +
        "</section>" +
        '<section class="hm-lado" aria-label="Navegador e funções">' +
          '<nav class="hm-abas">' +
            ["navegador:Navegador", "tarefas:Tarefas", "skills:Skills e ferramentas", "memoria:Memória", "logs:Logs"].map(function (x, i) {
              var p = x.split(":");
              return '<button type="button" class="hm-aba' + (i ? "" : " hm-aba--ativa") + '" data-hm-aba="' + p[0] + '">' + p[1] + "</button>";
            }).join("") + "</nav>" +
          '<div class="hm-painel" data-hm-painel="navegador">' +
            '<div class="hm-nav__barra"><button type="button" class="hm-bt hm-bt--icone" data-hm-nav="voltar" title="Voltar" aria-label="Voltar">←</button>' +
              '<button type="button" class="hm-bt hm-bt--icone" data-hm-nav="avancar" title="Avançar" aria-label="Avançar">→</button>' +
              '<button type="button" class="hm-bt hm-bt--icone" data-hm-nav="recarregar" title="Recarregar" aria-label="Recarregar">⟳</button>' +
              '<form class="hm-nav__url"><input type="text" placeholder="Endereço do site ou o que buscar" autocomplete="off" spellcheck="false" aria-label="Endereço"></form>' +
              '<button type="button" class="hm-bt hm-bt--icone" data-hm-nav="nova_aba" title="Nova aba" aria-label="Nova aba">＋</button>' +
              '<button type="button" class="hm-bt" data-hm-energia>Ligar</button></div>' +
            '<div class="hm-nav__abas"></div>' +
            '<div class="hm-nav__tela" tabindex="0" aria-label="Tela do navegador do agente"><img alt="" draggable="false" hidden>' +
              '<div class="hm-nav__aviso" hidden></div></div>' +
            '<form class="hm-nav__digitar"><input type="text" placeholder="Digitar na página (acentos, celular): escreva e mande" autocomplete="off" aria-label="Texto para a página">' +
              '<button type="submit" class="hm-bt">Digitar</button><button type="button" class="hm-bt" data-hm-tecla="Enter">Enter ↵</button></form>' +
            '<p class="hm-dica">Clique na tela para clicar na página. Com a tela selecionada, o teclado e a rodinha vão para a página. É o mesmo navegador que o agente usa: o login que você fizer aqui fica para ele.</p>' +
          "</div>" +
          '<div class="hm-painel" data-hm-painel="tarefas" hidden></div>' +
          '<div class="hm-painel" data-hm-painel="skills" hidden></div>' +
          '<div class="hm-painel" data-hm-painel="memoria" hidden></div>' +
          '<div class="hm-painel" data-hm-painel="logs" hidden></div>' +
        "</section></div></div>";
    document.body.appendChild(mesa);
    ligarEventos();
  }

  function cabecalho() {
    var a = agente();
    if (!a) return;
    var e = estadoDe(a);
    $(".hm-topo__nome").textContent = a.nome;
    $(".hm-topo__sub").textContent = [a.modelo, "serviço " + a.servico.nome, a.servico.ativo ? "memória " + mb(a.servico.mem) : ""].filter(Boolean).join(" · ");
    var pill = mesa.querySelector(".hm-topo .ag-estado");
    pill.className = "ag-estado " + e[1];
    pill.textContent = e[0];
    var alt = $('[data-hm-servico="alternar"]'), rei = $('[data-hm-servico="reiniciar"]');
    alt.hidden = rei.hidden = a.servico.bloqueado;
    alt.textContent = a.servico.ativo ? "Parar" : "Iniciar";
    rei.hidden = a.servico.bloqueado || !a.servico.ativo;
    conversaDisponivel();
  }

  function abrir(id) {
    if (!agente(id)) return;
    if (!mesa) montarMesa();
    fechar(true);
    aberto = id;
    est = { sessao: null, sessoes: [], run: null, runV: "", vivo: false, linha: [], hash: "", aba: null, lado: "navegador", navLigado: false,
            rapidoAte: 0, relogio: null, soLeitura: false, fila: Promise.resolve(), carregou: {} };
    mesa.hidden = false;
    document.body.classList.add("hm-aberta");
    $(".hm-msgs").innerHTML = "";
    $(".hm-escrever textarea").value = "";
    $(".hm-nav__tela img").hidden = true;
    mostrarLado("navegador");
    ver("conversa");
    cabecalho();
    var a = agente();
    $('[data-hm-aba="navegador"]').hidden = !a.navegador.tem;
    if (!a.navegador.tem) mostrarLado("tarefas");
    if (a.conversa) lerSessoes(true);
    bater();
    $(".hm-escrever textarea").focus();
  }
  function fechar(quieto) {
    if (!aberto) return;
    clearTimeout(est.relogio);
    aberto = null;
    if (!quieto) { mesa.hidden = true; document.body.classList.remove("hm-aberta"); lerAgentes(); }
  }
  function ver(qual) {          // no celular: conversa OU o lado
    $(".hm-corpo").setAttribute("data-hm-vendo", qual);
    if (aberto && qual === "lado") acelerar(1500);
    mesa.querySelectorAll("[data-hm-troca]").forEach(function (b) { b.classList.toggle("hm-troca__bt--ativo", b.getAttribute("data-hm-troca") === qual); });
  }

  /* ---------------------------------------------------------------- conversa */
  function conversaDisponivel() {
    var a = agente(), form = $(".hm-escrever"), barra = $(".hm-conversa__barra"), motivo = "";
    if (!a.conversa) motivo = "Este agente não conversa por aqui: o serviço dele está bloqueado no servidor. Dá para ver tarefas, skills, memória e logs ao lado.";
    else if (!a.servico.ativo) motivo = "O serviço deste agente está parado. Clique em Iniciar, lá em cima, para conversar.";
    else if (!a.api_no_ar) motivo = "O agente está subindo… a conversa volta em alguns segundos.";
    form.hidden = (!!motivo && !est.vivo) || est.soLeitura;
    barra.hidden = !a.conversa;
    var aviso = $(".hm-conversa__aviso"), voltou = !motivo && !aviso.hidden;
    aviso.textContent = motivo;
    aviso.hidden = !motivo || est.vivo;
    if (voltou && !est.sessoes.length) lerSessoes(true);
  }
  function lerSessoes(escolher) {
    return doAgente("sessoes").then(function (d) {
      if (!aberto) return;
      est.sessoes = d.sessoes || [];
      var sel = $(".hm-sessoes");
      sel.innerHTML = '<option value="">Nova conversa</option>' + est.sessoes.map(function (s) {
        var deFora = s.origem && s.origem !== "api_server";
        return '<option value="' + esc(s.id) + '">' + esc((s.titulo || "").slice(0, 60)) + " · " + quando(s.ultima) + (deFora ? " · " + esc(NOME_PLAT[s.origem] || s.origem) : "") + "</option>";
      }).join("");
      if (escolher) {     // abre na conversa mais recente feita por esta tela
        var minha = est.sessoes.filter(function (s) { return s.origem === "api_server"; })[0];
        if (minha && !est.vivo) trocarSessao(minha.id); else boasVindas();
      }
      sel.value = est.sessao || "";
    }).catch(function () {});
  }
  function boasVindas() {
    if (est.sessao || est.vivo) return;
    var a = agente();
    var exemplos = (a.exemplos || []).map(function (t) { return '<button type="button" class="hm-exemplo" data-hm-exemplo="' + esc(t) + '">' + esc(t) + "</button>"; }).join("");
    $(".hm-msgs").innerHTML = '<div class="hm-vazio"><b>' + esc(a.nome) + "</b><p>É uma conversa: escreva na caixa aqui embaixo o que você quer, ele faz no navegador ao lado e te responde. Errou? Corrija na conversa. Acertou? Diga “guarda isso” e ele aprende o caminho.</p>" +
      (exemplos ? '<div class="hm-exemplos">' + exemplos + "</div>" : "") + "</div>";
  }
  function trocarSessao(id) {
    est.sessao = id || null;
    est.soLeitura = false;
    $(".hm-sessoes").value = est.sessao || "";
    if (!est.sessao) { $(".hm-msgs").innerHTML = ""; boasVindas(); conversaDisponivel(); return Promise.resolve(); }
    var s = est.sessoes.filter(function (x) { return x.id === id; })[0];
    est.soLeitura = !!(s && s.origem && s.origem !== "api_server");
    return doAgente("sessoes/" + encodeURIComponent(id) + "/mensagens").then(function (d) {
      if (est.sessao !== id) return;
      desenharMensagens(d.mensagens || []);
      conversaDisponivel();
    }).catch(function (e) { $(".hm-msgs").innerHTML = '<p class="hm-indisponivel">Não consegui abrir a conversa: ' + esc(e.message) + "</p>"; });
  }
  function balao(m) {
    if (m.papel === "ferramenta") return '<div class="hm-passo hm-passo--ok"><b>' + esc(FERRAMENTA[m.nome] || m.nome || "ferramenta") + "</b></div>";
    var usou = (m.usou || []).map(function (u) { return '<div class="hm-passo hm-passo--ok"><b>' + esc(FERRAMENTA[u] || u) + "</b></div>"; }).join("");
    return (m.texto && m.texto.trim() ? '<div class="hm-msg hm-msg--' + (m.papel === "voce" ? "voce" : "agente") + '">' + (m.papel === "voce" ? esc(m.texto).replace(/\n/g, "<br>") : fmt(m.texto)) + "</div>" : "") + usou;
  }
  function desenharMensagens(lista) {
    var caixa = $(".hm-msgs");
    // o resultado de cada ferramenta já aparece como passo do agente; a linha "ferramenta" repetiria
    caixa.innerHTML = lista.filter(function (m) { return m.papel !== "ferramenta"; }).map(balao).join("") +
      (est.soLeitura ? '<p class="hm-indisponivel">Esta conversa veio de fora (Telegram ou WhatsApp) e aqui é só leitura. Para falar com o agente, comece uma nova.</p>' : "") +
      '<div class="hm-vivo"></div>';
    caixa.scrollTop = caixa.scrollHeight;
  }
  function vivoHtml(run) {
    var h = "";
    est.linha.forEach(function (it, i) {
      if (it.t === "texto") { if (it.v.trim()) h += '<div class="hm-msg hm-msg--agente">' + fmt(it.v) + "</div>"; }
      else if (it.t === "ferramenta") h += '<div class="hm-passo hm-passo--' + esc(it.estado) + '"><b>' + esc(FERRAMENTA[it.nome] || it.nome) + "</b>" +
        (it.previa ? " <span>" + esc(it.previa) + "</span>" : "") + (it.dur != null ? " <small>" + Number(it.dur).toFixed(1).replace(".", ",") + " s</small>" : "") + "</div>";
      else if (it.t === "pensando") h += '<div class="hm-pensa">' + esc(it.v) + "</div>";
      else if (it.t === "aprovacao") h += '<div class="hm-aprova"><b>O agente pede permissão para rodar:</b><pre>' + esc(it.comando) + "</pre>" +
        (it.motivo ? "<p>" + esc(it.motivo) + "</p>" : "") +
        (it.pendente ? '<div class="hm-aprova__bts">' + (it.escolhas || []).map(function (c) {
          return '<button type="button" class="hm-bt' + (c === "deny" ? " hm-bt--perigo" : c === "once" ? " hm-bt--forte" : "") + '" data-hm-aprovar="' + esc(c) + '">' + esc(ESCOLHA[c] || c) + "</button>";
        }).join("") + "</div>" : "<small>Resposta: " + esc(ESCOLHA[it.resposta] || it.resposta || "—") + "</small>") + "</div>";
    });
    if (run.vivo) h += '<div class="hm-trabalhando">' + (run.status === "waiting_for_approval" ? "esperando a sua permissão" : run.status === "stopping" ? "parando…" : "trabalhando…") + "</div>";
    else if (run.status === "failed") h += '<div class="hm-msg hm-msg--erro">Não deu certo: ' + esc(run.erro || "o agente falhou") + "</div>";
    else if (run.status === "cancelled") h += '<div class="hm-msg hm-msg--erro">Parado a seu pedido.</div>';
    else if (run.saida && !est.linha.some(function (it) { return it.t === "texto" && it.v.indexOf(run.saida.slice(0, 80)) >= 0; })) h += '<div class="hm-msg hm-msg--agente">' + fmt(run.saida) + "</div>";
    return h;
  }
  function aplicarRun(run) {
    if (!run || est.enviando || (est.run && run.id !== est.run)) return;
    var caixa = $(".hm-msgs"), noFim = caixa.scrollHeight - caixa.scrollTop - caixa.clientHeight < 80;
    if (!est.run) {            // a tela abriu com o agente no meio de um pedido: retoma de onde está
      if (!run.vivo) return;
      est.run = run.id;
      est.sessao = run.sessao;
      $(".hm-sessoes").value = est.sessao || "";
      desenharMensagens([{ papel: "voce", texto: run.pedido }]);
    }
    if (run.linha) { est.linha = run.linha; est.runV = String(run.v); }
    est.vivo = run.vivo;
    var vivo = caixa.querySelector(".hm-vivo");
    if (!vivo) { vivo = document.createElement("div"); vivo.className = "hm-vivo"; caixa.appendChild(vivo); }
    vivo.innerHTML = vivoHtml(run);
    if (noFim) caixa.scrollTop = caixa.scrollHeight;
    $("[data-hm-parar]").hidden = !run.vivo;
    $('.hm-escrever [type="submit"]').disabled = run.vivo;
    if (!run.vivo) {           // acabou: a conversa gravada passa a valer
      est.run = null; est.runV = "";
      lerSessoes(false);
      if (run.status === "completed") doAgente("sessoes/" + encodeURIComponent(run.sessao) + "/mensagens").then(function (d) {
        if (est.sessao === run.sessao && !est.run && !est.enviando) desenharMensagens(d.mensagens || []);
      }).catch(function () {});
      lerAgentes();
    }
  }
  function enviar(texto) {
    var caixa = $(".hm-msgs");
    if (!est.sessao) caixa.innerHTML = "";
    var antigo = caixa.querySelector(".hm-vivo");
    if (antigo) antigo.className = "";        // o que ficou da execução anterior vira histórico
    caixa.insertAdjacentHTML("beforeend", balao({ papel: "voce", texto: texto }) + '<div class="hm-vivo"><div class="hm-trabalhando">enviando…</div></div>');
    caixa.scrollTop = caixa.scrollHeight;
    $('.hm-escrever [type="submit"]').disabled = true;
    est.linha = [];
    est.enviando = true;
    return doAgente("enviar", { texto: texto, sessao: est.sessao }).then(function (d) {
      est.enviando = false;
      est.run = d.run; est.runV = ""; est.sessao = d.sessao; est.vivo = true;
      $("[data-hm-parar]").hidden = false;
      acelerar(4000);
    }).catch(function (e) {
      est.enviando = false;
      $('.hm-escrever [type="submit"]').disabled = false;
      caixa.querySelector(".hm-vivo").innerHTML = '<div class="hm-msg hm-msg--erro">' + esc(e.message) + "</div>";
    });
  }

  /* ---------------------------------------------------------------- navegador */
  function acao(a) {            // as ações vão em fila: clique, texto e Enter chegam na ordem
    if (est.aba && !a.aba) a.aba = est.aba;
    var id = aberto;
    est.fila = est.fila.then(function () {
      return id === aberto ? doAgente("navegador/acao", a).then(function (d) { acelerar(3500); return d; }) : null;
    }).catch(function (e) { avisoNav(e.message, true); });
    return est.fila;
  }
  function avisoNav(texto, some) {
    var av = $(".hm-nav__aviso");
    av.innerHTML = texto || "";
    av.hidden = !texto;
    av.classList.toggle("hm-nav__aviso--faixa", !!some);   // erro passageiro é uma faixa; aviso de estado cobre a tela
    if (some) setTimeout(function () { if (av.innerHTML === texto) av.hidden = true; }, 4000);
  }
  function aplicarNav(n) {
    if (!n) return;
    var img = $(".hm-nav__tela img"), energia = $("[data-hm-energia]"), mudou = est.navLigado !== !!n.ligado;
    est.navLigado = !!n.ligado;
    est.noPc = !!n.no_pc;
    energia.hidden = est.noPc && !n.ligado;      // ligar é no computador de quem usa; desligar dá para fazer daqui
    if (n.larg && n.alt) { est.navLarg = n.larg; est.navAlt = n.alt; }
    energia.textContent = n.ligado ? "Desligar" : "Ligar";
    energia.title = n.ligado && n.mem ? "Navegador ligado · " + mb(n.mem) : "";
    mesa.querySelectorAll("[data-hm-nav], .hm-nav__digitar input, .hm-nav__digitar button").forEach(function (b) { b.disabled = !n.ligado; });
    if (!n.ligado) {
      img.hidden = true; est.hash = "";
      $(".hm-nav__abas").innerHTML = "";
      avisoNav(n.no_pc ? '<b>O navegador deste agente fica no seu computador</b><span>A OLX bloqueia navegador de servidor, então o agente usa um Chrome separado aí na sua máquina, escondido: nenhuma janela abre, tudo aparece aqui. Ele está desligado. Para ligar, dê dois cliques em navegador-olx.bat (pasta nay-agentes\\hermes-painel); em uns 20 segundos a tela aparece.</span>' : '<b>Navegador desligado</b><span>Ele liga sozinho quando o agente precisa de um site (uns 2 segundos) e desliga depois de 20 minutos parado, para não ocupar a memória da VPS.</span><button type="button" class="hm-bt hm-bt--forte" data-hm-energia>Ligar agora</button>');
      return;
    }
    if (n.erro) { avisoNav(esc(n.erro), true); return; }
    if (mudou || !n.img) { var av = $(".hm-nav__aviso"); if (av.querySelector("[data-hm-energia]")) av.hidden = true; }
    if (n.img) { img.src = "data:image/jpeg;base64," + n.img; img.hidden = false; est.hash = n.hash; avisoNav(""); }
    var campo = $(".hm-nav__url input");
    if (document.activeElement !== campo && n.url != null) campo.value = n.url === "about:blank" ? "" : n.url;
    if (n.abas) $(".hm-nav__abas").innerHTML = n.abas.map(function (t) {
      return '<span class="hm-guia' + (t.id === n.aba ? " hm-guia--ativa" : "") + '"><button type="button" data-hm-guia="' + esc(t.id) + '" title="' + esc(t.url) + '">' + esc(t.titulo || "nova aba") + "</button>" +
        (n.abas.length > 1 ? '<button type="button" class="hm-guia__x" data-hm-fechar-guia="' + esc(t.id) + '" aria-label="Fechar aba">×</button>' : "") + "</span>";
    }).join("") + (n.abas.length > 1 ? '<button type="button" class="hm-guia__seguir' + (n.seguindo ? " hm-guia__seguir--on" : "") + '" data-hm-seguir title="Mostrar sempre a aba que o agente estiver usando">' + (n.seguindo ? "seguindo o agente" : "seguir o agente") + "</button>" : "");
  }
  function energia() {
    var ligar = !est.navLigado, bt = $("[data-hm-energia]");
    if (!ligar && !confirm(est.noPc ? "Desligar o navegador do agente? Ele fecha aí no seu computador (o login fica guardado). Para ligar de novo é pelo navegador-olx.bat, no seu computador."
      : "Desligar o navegador deste agente? As abas abertas fecham; os logins ficam guardados.")) return;
    bt.disabled = true;
    avisoNav(ligar ? "<b>Ligando o navegador…</b>" : "<b>Desligando…</b>");
    doAgente("navegador/" + (ligar ? "ligar" : "desligar"), {}).then(function () { est.hash = ""; est.aba = null; acelerar(4000); })
      .catch(function (e) { avisoNav(esc(e.message), true); }).then(function () { bt.disabled = false; });
  }
  function ponto(e, img) {      // do clique na imagem para o pixel da página
    var r = img.getBoundingClientRect();
    // a medida da página vem da ponte: num monitor com escala a foto é maior que a página
    var larg = est.navLarg || img.naturalWidth, alt = est.navAlt || img.naturalHeight;
    return { x: Math.round((e.clientX - r.left) * larg / r.width), y: Math.round((e.clientY - r.top) * alt / r.height) };
  }

  /* ---------------------------------------------------------------- tarefas, skills, memória, logs */
  function mostrarLado(qual) {
    est.lado = qual;
    mesa.querySelectorAll("[data-hm-aba]").forEach(function (b) { b.classList.toggle("hm-aba--ativa", b.getAttribute("data-hm-aba") === qual); });
    mesa.querySelectorAll("[data-hm-painel]").forEach(function (p) { p.hidden = p.getAttribute("data-hm-painel") !== qual; });
    if (qual === "tarefas") lerTarefas();
    else if (qual === "skills") lerSkills();
    else if (qual === "memoria") lerMemoria();
    else if (qual === "logs") lerLogs();
    else acelerar(1500);
  }
  function painel(qual) { return $('[data-hm-painel="' + qual + '"]'); }
  function carregando(qual) { if (!est.carregou[qual]) painel(qual).innerHTML = '<p class="hm-indisponivel">Lendo…</p>'; }
  function falhou(qual, e) { painel(qual).innerHTML = '<p class="hm-indisponivel">Não consegui ler: ' + esc(e.message) + "</p>"; }

  function lerTarefas() {
    carregando("tarefas");
    doAgente("tarefas").then(function (d) {
      est.carregou.tarefas = true;
      var mexe = d.pode_mexer;
      painel("tarefas").innerHTML = '<p class="hm-dica">O que o agente faz sozinho, na hora marcada. ' + (mexe ? "" : "O serviço dele está parado: aqui é só leitura.") + "</p>" +
        ((d.tarefas || []).map(function (t) {
          return '<article class="hm-tarefa' + (t.ligada ? "" : " hm-tarefa--pausada") + '"><div class="hm-tarefa__topo"><b>' + esc(t.nome) + "</b><code>" + esc(t.quando) + "</code>" +
            '<span class="hm-selo' + (t.ligada ? "" : " hm-selo--mudo") + '">' + (t.ligada ? "ligada" : "pausada") + "</span></div>" +
            '<p class="hm-tarefa__pedido">' + esc(t.pedido) + "</p>" +
            '<div class="hm-tarefa__info"><span>próxima: <b>' + quando(t.proxima) + "</b></span><span>última: <b>" + quando(t.ultima) + "</b>" +
              (t.resultado ? ' <i class="hm-res hm-res--' + (t.resultado === "ok" || t.resultado === "success" ? "ok" : "erro") + '">' + esc(t.resultado === "error" ? "deu erro" : t.resultado) + "</i>" : "") + "</span>" +
              (t.entrega ? "<span>entrega: " + esc(t.entrega) + "</span>" : "") + "</div>" +
            (t.erro ? '<p class="hm-tarefa__erro">' + esc(t.erro) + "</p>" : "") +
            (mexe ? '<div class="hm-tarefa__bts"><button type="button" class="hm-bt" data-hm-tarefa="' + (t.ligada ? "pausar" : "retomar") + '" data-id="' + esc(t.id) + '">' + (t.ligada ? "Pausar" : "Retomar") + "</button>" +
              '<button type="button" class="hm-bt" data-hm-tarefa="rodar" data-id="' + esc(t.id) + '">Rodar agora</button>' +
              '<button type="button" class="hm-bt hm-bt--perigo" data-hm-tarefa="excluir" data-id="' + esc(t.id) + '" data-nome="' + esc(t.nome) + '">Excluir</button></div>' : "") + "</article>";
        }).join("") || '<p class="hm-indisponivel">Nenhuma tarefa agendada.</p>') +
        (mexe ? '<form class="hm-form" data-hm-nova-tarefa><h3>Nova tarefa</h3>' +
          '<label>Nome<input name="nome" required maxlength="120" placeholder="Ex.: Conferir anúncios da OLX"></label>' +
          '<label>Quando<input name="quando" required placeholder="0 9 * * *  (todo dia às 9h)  ·  every 2h  ·  30m"></label>' +
          '<label>O que ele deve fazer<textarea name="pedido" rows="3" required placeholder="Escreva o pedido completo: a tarefa roda sem a conversa de antes."></textarea></label>' +
          '<label>Onde entregar o resultado<select name="entrega"><option value="local">Só guardar (aparece nos logs)</option>' + Object.keys(agente().plataformas || {}).map(function (n) { return '<option value="' + esc(n) + '">' + esc(NOME_PLAT[n] || n) + "</option>"; }).join("") + "</select></label>" +
          '<button type="submit" class="hm-bt hm-bt--forte">Agendar</button><span class="hm-form__msg"></span></form>' : "");
    }).catch(function (e) { falhou("tarefas", e); });
  }
  function lerSkills() {
    carregando("skills");
    doAgente("skills").then(function (d) {
      est.carregou.skills = true;
      var grupos = {};
      (d.skills || []).forEach(function (s) { (grupos[s.grupo || "outras"] = grupos[s.grupo || "outras"] || []).push(s); });
      painel("skills").innerHTML =
        (d.ferramentas && d.ferramentas.length ? '<h3 class="hm-titulo">Ferramentas <small>' + d.ferramentas.filter(function (f) { return f.ligada; }).length + " ligadas de " + d.ferramentas.length + "</small></h3>" +
          '<div class="hm-ferramentas">' + d.ferramentas.map(function (f) {
            return '<details class="hm-ferramenta' + (f.ligada ? "" : " hm-ferramenta--off") + '"><summary><b>' + esc(f.nome) + "</b> <span>" + esc(f.descricao) + "</span>" +
              '<i class="hm-selo' + (f.ligada ? "" : " hm-selo--mudo") + '">' + (f.ligada ? "ligada" : "desligada") + "</i></summary><p>" + (f.itens || []).map(esc).join(" · ") + "</p></details>";
          }).join("") + "</div>" : "") +
        '<h3 class="hm-titulo">Skills <small>' + (d.skills || []).length + ' receitas que ele sabe seguir</small></h3><input type="search" class="hm-busca" placeholder="Procurar skill…" aria-label="Procurar skill">' +
        Object.keys(grupos).sort().map(function (g) {
          return '<div class="hm-grupo"><h4>' + esc(g) + "</h4>" + grupos[g].map(function (s) {
            return '<div class="hm-skill" data-hm-busca="' + esc((s.nome + " " + s.descricao + " " + g).toLowerCase()) + '"><b>' + esc(s.nome) + "</b><span>" + esc(s.descricao) + "</span></div>";
          }).join("") + "</div>";
        }).join("");
    }).catch(function (e) { falhou("skills", e); });
  }
  function lerMemoria() {
    carregando("memoria");
    doAgente("memoria").then(function (d) {
      est.carregou.memoria = true;
      var NOMES = { "MEMORY.md": "O que ele anotou para lembrar", "USER.md": "O que ele sabe sobre você", "SOUL.md": "A personalidade (só leitura)" };
      painel("memoria").innerHTML = (d.arquivos || []).map(function (a) {
        return '<form class="hm-form hm-memoria" data-hm-memoria="' + esc(a.nome) + '"><h3>' + esc(NOMES[a.nome] || a.nome) + " <small>" + esc(a.nome) + "</small></h3>" +
          '<textarea rows="' + (a.edita ? 9 : 7) + '"' + (a.edita ? "" : " readonly") + ' spellcheck="false">' + esc(a.texto) + "</textarea>" +
          (a.edita ? '<div><button type="submit" class="hm-bt hm-bt--forte">Salvar</button><span class="hm-form__msg"></span></div>' : "") + "</form>";
      }).join("");
    }).catch(function (e) { falhou("memoria", e); });
  }
  function lerLogs() {
    var p = painel("logs");
    if (!p.querySelector("pre")) p.innerHTML = '<div class="hm-logs__barra"><select aria-label="Qual log"><option value="agent">O que o agente fez</option><option value="gateway">Mensagens e conexões</option><option value="errors">Erros</option></select>' +
      '<button type="button" class="hm-bt" data-hm-logs>Atualizar</button></div><pre class="hm-logs">Lendo…</pre>';
    doAgente("logs?arquivo=" + p.querySelector("select").value + "&linhas=200").then(function (d) {
      var pre = p.querySelector("pre");
      pre.textContent = (d.linhas || []).join("\n") || "(vazio)";
      pre.scrollTop = pre.scrollHeight;
    }).catch(function (e) { p.querySelector("pre").textContent = "Não consegui ler: " + e.message; });
  }

  /* ---------------------------------------------------------------- o pulso */
  function acelerar(ms) { est.rapidoAte = Date.now() + ms; clearTimeout(est.relogio); est.relogio = setTimeout(bater, 250); }
  function bater() {
    var id = aberto;
    if (!id) return;
    clearTimeout(est.relogio);
    if (document.hidden) { est.relogio = setTimeout(bater, 2000); return; }
    var q = ["v=" + encodeURIComponent(est.runV)], tela = est.lado === "navegador" && agente().navegador.tem && $(".hm-lado").offsetParent !== null;
    if (est.run) q.push("run=" + encodeURIComponent(est.run));
    if (tela) { q.push("tela=1", "hash=" + est.hash); if (est.aba) q.push("aba=" + encodeURIComponent(est.aba)); }
    doAgente("pulso?" + q.join("&")).then(function (d) {
      if (id !== aberto) return;
      aplicarRun(d.run);
      aplicarNav(d.nav);
    }).catch(function () {}).then(function () {
      if (id !== aberto) return;
      var rapido = Date.now() < est.rapidoAte;
      est.relogio = setTimeout(bater, rapido ? 450 : est.vivo ? 1000 : (tela && est.navLigado) ? 1300 : 4000);
    });
  }

  /* ---------------------------------------------------------------- eventos */
  function ligarEventos() {
    var tela = $(".hm-nav__tela"), img = tela.querySelector("img"), digitando = "", tDig = null, roda = 0, tRoda = null, ondeRoda = null;
    function despejar() { clearTimeout(tDig); if (digitando) { acao({ tipo: "texto", texto: digitando }); digitando = ""; } }

    mesa.addEventListener("click", function (e) {
      var b;
      if (e.target === mesa || e.target.closest("[data-hm-fechar]")) return fechar();
      if ((b = e.target.closest("[data-hm-troca]"))) return ver(b.getAttribute("data-hm-troca"));
      if ((b = e.target.closest("[data-hm-exemplo]"))) { var campo = $(".hm-escrever textarea"); campo.value = b.getAttribute("data-hm-exemplo"); campo.focus(); return; }
      if ((b = e.target.closest("[data-hm-aba]"))) return mostrarLado(b.getAttribute("data-hm-aba"));
      if (e.target.closest("[data-hm-nova]")) { if (!est.vivo) trocarSessao(null).then(function () { $(".hm-escrever textarea").focus(); }); return; }
      if (e.target.closest("[data-hm-parar]")) { if (est.run) doAgente("execucao/" + est.run + "/parar", {}).then(function () { acelerar(3000); }).catch(function () {}); return; }
      if ((b = e.target.closest("[data-hm-aprovar]"))) { b.parentNode.querySelectorAll("button").forEach(function (x) { x.disabled = true; });
        doAgente("execucao/" + est.run + "/aprovar", { escolha: b.getAttribute("data-hm-aprovar") }).then(function () { acelerar(3000); }).catch(function (er) { alert(er.message); }); return; }
      if ((b = e.target.closest("[data-hm-servico]"))) return servico(b.getAttribute("data-hm-servico"));
      if (e.target.closest("[data-hm-energia]")) return energia();
      if ((b = e.target.closest("[data-hm-nav]"))) { var t = b.getAttribute("data-hm-nav"); acao({ tipo: t }).then(function (d) { if (t === "nova_aba" && d && d.aba) est.aba = d.aba; }); return; }
      if ((b = e.target.closest("[data-hm-tecla]"))) return acao({ tipo: "tecla", tecla: b.getAttribute("data-hm-tecla") });
      if ((b = e.target.closest("[data-hm-guia]"))) { est.aba = b.getAttribute("data-hm-guia"); est.hash = ""; acao({ tipo: "focar_aba", aba: est.aba }); return; }
      if ((b = e.target.closest("[data-hm-fechar-guia]"))) { var qual = b.getAttribute("data-hm-fechar-guia"); if (est.aba === qual) est.aba = null; est.hash = ""; acao({ tipo: "fechar_aba", aba: qual }); return; }
      if (e.target.closest("[data-hm-seguir]")) { est.aba = null; est.hash = ""; acao({ tipo: "seguir" }); return; }
      if ((b = e.target.closest("[data-hm-tarefa]"))) return tarefa(b);
      if (e.target.closest("[data-hm-logs]")) return lerLogs();
    });
    mesa.addEventListener("change", function (e) {
      if (e.target.classList.contains("hm-sessoes")) { if (est.vivo) { e.target.value = est.sessao || ""; return; } trocarSessao(e.target.value); }
      else if (e.target.closest(".hm-logs__barra")) lerLogs();
    });
    mesa.addEventListener("input", function (e) {
      if (!e.target.classList.contains("hm-busca")) return;
      var termo = e.target.value.trim().toLowerCase();
      painel("skills").querySelectorAll(".hm-skill").forEach(function (s) { s.hidden = termo && s.getAttribute("data-hm-busca").indexOf(termo) < 0; });
      painel("skills").querySelectorAll(".hm-grupo").forEach(function (g) { g.hidden = !g.querySelector(".hm-skill:not([hidden])"); });
    });
    mesa.addEventListener("submit", function (e) {
      e.preventDefault();
      var f = e.target, campo, msg;
      if (f.classList.contains("hm-escrever")) {
        campo = f.querySelector("textarea");
        var texto = campo.value.trim();
        if (!texto || est.vivo) return;
        campo.value = "";
        enviar(texto);
      } else if (f.classList.contains("hm-nav__url")) {
        campo = f.querySelector("input");
        if (campo.value.trim()) { acao({ tipo: "navegar", url: campo.value.trim() }); campo.blur(); }
      } else if (f.classList.contains("hm-nav__digitar")) {
        campo = f.querySelector("input");
        if (campo.value) { acao({ tipo: "texto", texto: campo.value }); campo.value = ""; }
      } else if (f.hasAttribute("data-hm-nova-tarefa")) {
        msg = f.querySelector(".hm-form__msg");
        msg.textContent = "agendando…";
        doAgente("tarefas", { nome: f.nome.value, quando: f.quando.value, pedido: f.pedido.value, entrega: f.entrega.value })
          .then(lerTarefas).catch(function (er) { msg.textContent = er.message; });
      } else if (f.hasAttribute("data-hm-memoria")) {
        msg = f.querySelector(".hm-form__msg");
        msg.textContent = "salvando…";
        doAgente("memoria", { nome: f.getAttribute("data-hm-memoria"), texto: f.querySelector("textarea").value })
          .then(function () { msg.textContent = "salvo (a versão anterior ficou guardada no servidor)"; }).catch(function (er) { msg.textContent = er.message; });
      }
    });
    $(".hm-escrever textarea").addEventListener("keydown", function (e) {
      if (e.key === "Enter" && !e.shiftKey && !e.isComposing) { e.preventDefault(); if (this.form.requestSubmit) this.form.requestSubmit(); else this.form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true })); }
    });

    $(".hm-nav__url input").addEventListener("focus", function () { this.select(); });   // como a barra de um navegador

    // --- a tela do navegador: clique, rodinha e teclado vão para a página do agente
    img.addEventListener("click", function (e) {
      if (!est.navLigado) return;
      tela.focus();
      var p = ponto(e, img), marca = document.createElement("i");
      marca.className = "hm-nav__clique";
      marca.style.left = (e.clientX - tela.getBoundingClientRect().left) + "px";
      marca.style.top = (e.clientY - tela.getBoundingClientRect().top + tela.scrollTop) + "px";
      tela.appendChild(marca);
      setTimeout(function () { marca.remove(); }, 600);
      despejar();
      acao({ tipo: "clicar", x: p.x, y: p.y, duplo: e.detail === 2 });
    });
    tela.addEventListener("wheel", function (e) {
      if (!est.navLigado || img.hidden) return;
      e.preventDefault();
      roda += e.deltaMode === 1 ? e.deltaY * 40 : e.deltaY;
      ondeRoda = ponto(e, img);
      if (!tRoda) tRoda = setTimeout(function () { tRoda = null; acao({ tipo: "rolar", x: ondeRoda.x, y: ondeRoda.y, dy: Math.round(roda) }); roda = 0; }, 140);
    }, { passive: false });
    tela.addEventListener("keydown", function (e) {
      if (!est.navLigado || e.metaKey || e.altKey) return;
      var k = e.key;
      if (TECLAS.indexOf(k) >= 0) { e.preventDefault(); despejar(); acao({ tipo: "tecla", tecla: k, shift: e.shiftKey, ctrl: e.ctrlKey }); return; }
      if (e.ctrlKey && k.length === 1) {
        var l = k.toLowerCase();
        if (l === "v") { e.preventDefault(); if (navigator.clipboard && navigator.clipboard.readText) navigator.clipboard.readText().then(function (t) { if (t) acao({ tipo: "texto", texto: t }); }).catch(function () {}); }
        else if ("acxz".indexOf(l) >= 0) { e.preventDefault(); despejar(); acao({ tipo: "tecla", tecla: l, ctrl: true }); }
        return;
      }
      if (k.length === 1) { e.preventDefault(); digitando += k; clearTimeout(tDig); tDig = setTimeout(despejar, 170); }
    });
    document.addEventListener("keydown", function (e) {
      if (e.key !== "Escape" || !aberto) return;
      var onde = document.activeElement;
      if (onde && (onde === tela || /^(INPUT|TEXTAREA|SELECT)$/.test(onde.tagName))) return;   // na tela, o Esc é da página
      fechar();
    });
    document.addEventListener("visibilitychange", function () { if (aberto && !document.hidden) acelerar(1500); });
  }
  function servico(qual) {
    var a = agente(), acaoS = qual === "alternar" ? (a.servico.ativo ? "parar" : "iniciar") : "reiniciar";
    var frase = { parar: "Parar o " + a.nome + "? Ele deixa de responder (aqui e no " + (Object.keys(a.plataformas || {}).map(function (n) { return NOME_PLAT[n] || n; }).join(", ") || "canal dele") + ") até ser iniciado de novo.",
                  reiniciar: "Reiniciar o " + a.nome + "? Leva uns 10 segundos; o que ele estiver fazendo é interrompido.", iniciar: "" }[acaoS];
    if (frase && !confirm(frase)) return;
    doAgente("servico", { acao: acaoS }).then(function () {
      $(".hm-topo__sub").textContent = { parar: "parando…", iniciar: "iniciando…", reiniciar: "reiniciando…" }[acaoS];
      setTimeout(lerAgentes, 2500); setTimeout(lerAgentes, 8000); setTimeout(lerAgentes, 15000);
    }).catch(function (e) { alert(e.message); });
  }
  function tarefa(b) {
    var qual = b.getAttribute("data-hm-tarefa"), id = b.getAttribute("data-id");
    if (qual === "excluir" && !confirm('Excluir a tarefa "' + b.getAttribute("data-nome") + '"? Não tem volta.')) return;
    b.disabled = true;
    doAgente("tarefas/" + encodeURIComponent(id) + "/" + qual, {}).then(function () {
      if (qual === "rodar") { b.textContent = "pedido feito"; setTimeout(lerTarefas, 6000); } else lerTarefas();
    }).catch(function (e) { b.disabled = false; alert(e.message); });
  }
})();
