/* Aprendizado (admin/aprendizado.html). Pedro, 28/10/2026: "cria ele lá no menu do imobeasy dentro do menu Mais,
   Aprendizado, e no aprendizado abre a tela para eu pôr o link para ele ir fazer isso".
   Manda os links ao Agente de Aprendizado (Hermes perfil `aprendizado`, VPS2) e acompanha o pedido. Tudo passa por
   /admin/api/hermes, como a mesa do agente em Agentes (hermes-painel.js): `enviar` cria o pedido, `pulso` diz em que
   passo ele está. Quem salva o .txt é o próprio agente (mcp_transcricao.py), na pasta transcricoes/ do PC. */
(function () {
  "use strict";
  var P = "aprendizado";
  var LINK = /https?:\/\/(?:www\.|m\.)?(?:youtube\.com\/(?:watch\?[^\s]*v=|shorts\/|live\/|embed\/)|youtu\.be\/)[A-Za-z0-9_-]{11}[^\s]*/g;
  // o que o agente está fazendo, em palavras (o nome da ferramenta do Hermes → o passo da receita)
  var PASSO = {
    browser_navigate: "abrindo o tactiq", browser_snapshot: "lendo a página", browser_type: "colando o link",
    browser_click: "clicando no botão", browser_press: "apertando uma tecla", browser_vision: "olhando a tela",
    browser_scroll: "rolando a página", mcp_transcricao_salvar_transcricao: "esperando a transcrição e salvando o arquivo"
  };
  var est = { run: null, v: "", timer: null };
  var $ = function (id) { return document.getElementById(id); };

  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function api(rota, corpo) {
    var o = { credentials: "same-origin", headers: {} };
    if (corpo !== undefined) {
      o.method = "POST";
      o.headers["Content-Type"] = "application/json";
      o.headers["X-Painel-Hermes"] = "1";   // a rota só aceita escrita com este cabeçalho
      o.body = JSON.stringify(corpo);
    }
    return fetch("api/hermes/agentes" + (rota ? "/" + P + "/" + rota : ""), o).then(function (r) {
      return r.json().catch(function () { return {}; }).then(function (d) {
        if (!r.ok) throw new Error(d.erro || ("erro " + r.status));
        return d;
      });
    });
  }
  function quando(t) {
    if (!t) return "";
    var d = new Date(typeof t === "number" ? t * 1000 : t);
    return isNaN(d) ? "" : d.toLocaleString("pt-BR", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });
  }

  /* ---- o agente e o navegador */
  function lerEstado() {
    return api("").then(function (d) {
      var a = (d.agentes || []).filter(function (x) { return x.id === P; })[0];
      var caixa = $("ap-estado");
      if (!a) { caixa.className = "ap-estado ap-estado--ruim"; caixa.textContent = "O Agente de Aprendizado ainda não está instalado na VPS2."; return; }
      var partes = [], ruim = false;
      if (!a.servico.ativo) { partes.push("<b>Agente parado.</b> Ligue em Agentes › Agente de Aprendizado."); ruim = true; }
      else partes.push("<b>Agente no ar</b>" + (a.trabalhando ? " · trabalhando" : ""));
      if (!a.navegador.ligado) { partes.push("<b>Navegador desligado:</b> dê dois cliques em <code>navegador-olx.bat</code> (pasta nay-agentes\\hermes-painel) no seu computador."); ruim = true; }
      else partes.push("navegador do seu computador ligado");
      caixa.className = "ap-estado" + (ruim ? " ap-estado--ruim" : "");
      caixa.innerHTML = partes.join(" · ");
    }).catch(function (e) { $("ap-estado").className = "ap-estado ap-estado--ruim"; $("ap-estado").textContent = e.message; });
  }
  /* ---- os passos de um pedido (28/10, Pedro: "põe os processos que passou cada solicitação, se tá aguardando o
     tactiq ou se já foi"). Entra a lista de ferramentas que o agente usou, na ordem: {nome, estado, texto}. No pedido
     em curso o estado vem da ponte (rodando/ok/erro); no pedido antigo vem a resposta da ferramenta (texto). */
  function salvar(nome) { return /salvar_transcricao$/.test(nome || ""); }
  function passos(itens) {
    var lista = [];
    itens.forEach(function (it) {
      var p;
      if (salvar(it.nome)) {
        var t = it.texto || "";
        if (it.estado === "rodando") p = { cls: "vivo", txt: "Aguardando o tactiq gerar a transcrição; depois copia e salva" };
        else if (/^Salvo/.test(t)) p = { cls: "ok", txt: t.replace(/^Salvo no computador do Pedro: /, "Salvo: ") };
        else if (t) p = { cls: "erro", txt: t };
        else p = it.estado === "erro" ? { cls: "erro", txt: "A ferramenta de salvar falhou" } : { cls: "ok", txt: "Transcrição copiada e salva" };
      } else {
        var rot = PASSO_FEITO[it.nome];
        if (!rot) return;    // ferramentas internas do Hermes (tool_search etc.) não entram
        p = { cls: it.estado === "rodando" ? "vivo" : it.estado === "erro" ? "erro" : "ok", txt: it.estado === "rodando" ? PASSO[it.nome] : rot };
      }
      var ult = lista[lista.length - 1];
      if (ult && ult.txt === p.txt && ult.cls === p.cls) return;   // o mesmo passo repetido aparece uma vez
      lista.push(p);
    });
    if (!lista.length) return '<p class="ap-vazio">Nenhum passo ainda.</p>';
    return '<ol class="ap-passos">' + lista.map(function (p) {
      return '<li class="ap-passo ap-passo--' + p.cls + '">' + esc(p.txt) + "</li>";
    }).join("") + "</ol>";
  }
  var PASSO_FEITO = {
    browser_navigate: "Abriu o tactiq", browser_type: "Colou o link", browser_click: "Clicou em Get Video Transcript",
    browser_press: "Apertou uma tecla", browser_snapshot: "Leu a página", browser_vision: "Olhou a tela", browser_scroll: "Rolou a página"
  };
  // o resumo do pedido: quantos vídeos foram salvos dos que ele pediu
  function selo(itens, links, vivo) {
    if (vivo) return '<span class="ap-selo ap-selo--vivo">em andamento</span>';
    var ok = itens.filter(function (it) { return salvar(it.nome) && /^Salvo/.test(it.texto || ""); }).length;
    if (!ok) return '<span class="ap-selo ap-selo--erro">não salvou</span>';
    return '<span class="ap-selo ap-selo--ok">' + (links > 1 ? ok + " de " + links + " salvos" : "salvo") + "</span>";
  }
  function lerPedidos() {
    return api("sessoes").then(function (d) {
      var s = (d.sessoes || []).slice(0, 12);
      if (!s.length) { $("ap-pedidos").innerHTML = '<li class="ap-vazio">Nenhum pedido ainda.</li>'; return; }
      return Promise.all(s.map(function (x) {
        return api("sessoes/" + encodeURIComponent(x.id) + "/mensagens").then(function (m) { return m.mensagens || []; }).catch(function () { return []; });
      })).then(function (todas) { est.pedidos = { s: s, todas: todas }; desenharPedidos(); });
    }).catch(function () { $("ap-pedidos").innerHTML = '<li class="ap-vazio">Não consegui ler os pedidos.</li>'; });
  }
  // redesenha a lista com o que já foi lido (o pedido em curso usa os passos ao vivo, sem chamar a ponte de novo)
  function desenharPedidos() {
    if (!est.pedidos) return;
    var s = est.pedidos.s, todas = est.pedidos.todas;
    var abertos = {};    // o que a pessoa abriu ou fechou continua assim depois de redesenhar
    [].forEach.call(document.querySelectorAll("#ap-pedidos details[data-sessao]"), function (d) { abertos[d.getAttribute("data-sessao")] = d.open; });
    $("ap-pedidos").innerHTML = s.map(function (x, i) {
      var msgs = todas[i];
      var pedido = (msgs.filter(function (m) { return m.papel === "voce"; })[0] || {}).texto || x.titulo;
      var links = (pedido.match(LINK) || []).length || 1;
      var itens = msgs.filter(function (m) { return m.papel === "ferramenta"; });
      var vivo = !!(est.sessaoViva && est.sessaoViva === x.id);
      var resposta = msgs.filter(function (m) { return m.papel === "agente" && m.texto; }).pop();
      var aberto = x.id in abertos ? abertos[x.id] : i === 0;
      return '<li><details data-sessao="' + esc(x.id) + '"' + (aberto ? " open" : "") + "><summary>" +
        '<span class="ap-quando">' + esc(quando(x.ultima)) + "</span>" + selo(itens, links, vivo) +
        '<span class="ap-titulo">' + esc(pedido.replace(/^Salve a(s)? transcriç(ão|ões) dest(e|es) (\d+ )?vídeos?:\s*/i, "")) + "</span></summary>" +
        passos(vivo ? (est.linha || []).filter(function (it) { return it.t === "ferramenta"; }) : itens) +
        (resposta && !vivo ? '<p class="ap-final">' + esc(resposta.texto) + "</p>" : "") + "</details></li>";
    }).join("");
  }

  /* ---- o pedido em curso */
  function mostrar(run) {
    var caixa = $("ap-andamento");
    caixa.hidden = false;
    if (run.linha) est.linha = run.linha;
    if (run.sessao) est.sessaoViva = run.vivo ? run.sessao : null;
    var feitas = (est.linha || []).filter(function (it) { return it.t === "ferramenta"; });
    var h = '<p class="ap-pedido">' + esc(run.pedido || "") + "</p>";
    if (run.vivo) {
      h += run.status === "waiting_for_approval" ? '<p class="ap-trab">esperando a sua permissão em Agentes</p>'
        : (feitas.length ? passos(feitas) : '<p class="ap-trab">começando</p>');
    } else if (run.status === "failed") h += '<p class="ap-erro">Não deu certo: ' + esc(run.erro || "o agente falhou") + "</p>";
    else if (run.status === "cancelled") h += '<p class="ap-erro">Parado a seu pedido.</p>';
    else h += '<div class="ap-resposta">' + esc(run.saida || "Terminou.").replace(/\n/g, "<br>") + "</div>";
    caixa.innerHTML = h;
    $("ap-parar").hidden = !run.vivo;
    document.querySelector('#ap-form [type="submit"]').disabled = !!run.vivo;
  }
  function pulso() {
    clearTimeout(est.timer);
    api("pulso?" + (est.run ? "run=" + encodeURIComponent(est.run) + "&" : "") + "v=" + encodeURIComponent(est.v)).then(function (d) {
      var run = d.run;
      if (!run || (est.run && run.id !== est.run)) return;
      var novo = !est.run;
      if (novo) { if (!run.vivo) return; est.run = run.id; }   // a tela abriu com um pedido no meio: acompanha
      est.v = String(run.v);
      mostrar(run);
      if (run.vivo) { if (novo) lerPedidos(); else desenharPedidos(); }   // a lista mostra o mesmo passo a passo do pedido em curso
      if (run.vivo) est.timer = setTimeout(pulso, 2500);
      else { est.run = null; est.v = ""; lerPedidos(); lerEstado(); }
    }).catch(function () { if (est.run) est.timer = setTimeout(pulso, 5000); });
  }

  $("ap-form").addEventListener("submit", function (e) {
    e.preventDefault();
    var vistos = {};   // o mesmo vídeo colado duas vezes (watch?v= e youtu.be) vai uma vez só
    var links = ($("ap-links").value.match(LINK) || []).filter(function (l) {
      var id = (l.match(/(?:[?&]v=|youtu\.be\/|shorts\/|live\/|embed\/)([A-Za-z0-9_-]{11})/) || [])[1];
      if (vistos[id]) return false;
      vistos[id] = true;
      return true;
    });
    if (!links.length) { alert("Não achei link do YouTube. Cole um por linha, como https://www.youtube.com/watch?v=..."); return; }
    var texto = (links.length > 1 ? "Salve as transcrições destes " + links.length + " vídeos:\n" : "Salve a transcrição deste vídeo:\n") + links.join("\n");
    document.querySelector('#ap-form [type="submit"]').disabled = true;
    est.linha = [];
    mostrar({ pedido: texto, vivo: true, status: "running" });
    api("enviar", { texto: texto, sessao: null }).then(function (d) {
      est.run = d.run; est.v = "";
      $("ap-links").value = "";
      est.timer = setTimeout(pulso, 2000);
    }).catch(function (er) {
      document.querySelector('#ap-form [type="submit"]').disabled = false;
      mostrar({ pedido: texto, status: "failed", erro: er.message });
    });
  });
  $("ap-parar").addEventListener("click", function () {
    if (est.run) api("execucao/" + encodeURIComponent(est.run) + "/parar", {}).then(function () { setTimeout(pulso, 1500); }).catch(function (er) { alert(er.message); });
  });

  lerEstado();
  lerPedidos();
  pulso();
})();
