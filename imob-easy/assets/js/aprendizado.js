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
  function lerPedidos() {
    return api("sessoes").then(function (d) {
      var s = (d.sessoes || []).slice(0, 15);
      $("ap-pedidos").innerHTML = s.length ? s.map(function (x) {
        return '<li><span class="ap-quando">' + esc(quando(x.ultima)) + "</span>" + esc(x.titulo) + "</li>";
      }).join("") : '<li class="ap-vazio">Nenhum pedido ainda.</li>';
    }).catch(function () { $("ap-pedidos").innerHTML = '<li class="ap-vazio">Não consegui ler os pedidos.</li>'; });
  }

  /* ---- o pedido em curso */
  function mostrar(run) {
    var caixa = $("ap-andamento");
    caixa.hidden = false;
    if (run.linha) est.linha = run.linha;
    var feitas = (est.linha || []).filter(function (it) { return it.t === "ferramenta"; });
    var salvos = feitas.filter(function (it) { return /salvar_transcricao$/.test(it.nome || "") && it.estado !== "rodando"; }).length;
    var h = '<p class="ap-pedido">' + esc(run.pedido || "") + "</p>";
    if (run.vivo) {
      var ultima = feitas[feitas.length - 1];
      h += '<p class="ap-trab">' + (run.status === "waiting_for_approval" ? "esperando a sua permissão em Agentes"
        : "trabalhando: " + esc(ultima ? (PASSO[ultima.nome] || (/salvar_transcricao$/.test(ultima.nome || "") ? PASSO.mcp_transcricao_salvar_transcricao : ultima.nome)) : "começando")) +
        (salvos ? " · " + salvos + " salvo" + (salvos > 1 ? "s" : "") + " até agora" : "") + "</p>";
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
      if (!est.run) { if (!run.vivo) return; est.run = run.id; }   // a tela abriu com um pedido no meio: acompanha
      est.v = String(run.v);
      mostrar(run);
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
