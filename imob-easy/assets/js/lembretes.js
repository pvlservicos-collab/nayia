/* OS LEMBRETES DA EQUIPE NO SININHO (Pedro, 15/10/2026): "um lembrete de aviso pra nós: ele nos avisa no site, em um
   menu de notificação, ao entrar pela primeira vez lá em cima, até eu ir lá e clicar em feito, em um dia específico e
   um texto que eu escrevo".

   Carregado pelo layout.js em toda página do admin. O sininho do topo mostra quantos lembretes são de hoje (ou
   atrasados); na primeira entrada do dia neste navegador, se houver algum, o painel abre sozinho. Cada um sai com
   "Feito". Embaixo, o campo para escrever um novo e escolher o dia. Quem guarda é o banco (migração 375,
   /admin/api/lembretes). Dentro do CRM (a página do site num quadro) o topo do site não aparece, e isto não roda. */
(function () {
  "use strict";
  if (window.self !== window.top) return;
  var sino = document.querySelector(".barra-topo .sino");
  if (!sino) return;

  var API = "/admin/api/lembretes";
  var dados = null;

  var estilo = document.createElement("style");
  estilo.textContent = [
    ".sino { position: relative; }",
    ".sino__conta { position: absolute; top: -3px; right: -3px; min-width: 18px; height: 18px; padding: 0 5px; border-radius: 999px;",
    "  background: #e8475f; color: #fff; font: 700 11px/18px Rubik, system-ui, sans-serif; text-align: center; box-shadow: 0 0 0 2px #fff; }",
    ".lb-painel { position: absolute; z-index: 60; width: min(380px, calc(100vw - 24px)); max-height: min(70vh, 620px); overflow: auto;",
    "  padding: 14px; border-radius: 18px; background: rgba(255,255,255,.86); border: 1px solid rgba(255,255,255,.95);",
    "  box-shadow: 0 18px 50px rgba(30,40,90,.18); -webkit-backdrop-filter: blur(18px) saturate(1.4); backdrop-filter: blur(18px) saturate(1.4);",
    "  font: 400 14px/1.4 Rubik, system-ui, sans-serif; color: #1c2340; }",
    ".lb-painel[hidden] { display: none; }",
    ".lb-titulo { margin: 2px 2px 10px; font: 800 18px Barlow, system-ui, sans-serif; color: #1c2340; display: flex; justify-content: space-between; align-items: center; }",
    ".lb-sec { margin: 12px 2px 6px; font: 700 11px Rubik, sans-serif; letter-spacing: .1em; text-transform: uppercase; color: #6b7390; }",
    ".lb-item { display: flex; gap: 10px; align-items: flex-start; padding: 10px 11px; border-radius: 12px; background: rgba(243,245,251,.9); margin-bottom: 6px; }",
    ".lb-item--agora { background: #fff4e5; border: 1px solid #f7c97c; }",
    ".lb-item--atrasado { background: #fdecef; border: 1px solid #f3a3b0; }",
    ".lb-item__texto { flex: 1; white-space: pre-wrap; word-break: break-word; }",
    ".lb-item__dia { display: block; font: 600 11.5px Rubik, sans-serif; color: #6b7390; margin-top: 3px; }",
    ".lb-item--atrasado .lb-item__dia { color: #c0354d; }",
    ".lb-feito { flex: 0 0 auto; border: 0; border-radius: 999px; padding: 6px 12px; font: 700 12.5px Rubik, sans-serif; cursor: pointer; background: #1d9e6a; color: #fff; }",
    ".lb-feito:hover { background: #157f55; }",
    ".lb-x { flex: 0 0 auto; border: 0; background: transparent; color: #8a91a8; font-size: 18px; line-height: 1; cursor: pointer; padding: 0 2px; }",
    ".lb-x:hover { color: #c0354d; }",
    ".lb-link { border: 0; background: transparent; color: #6b4fd8; font: 600 12px Rubik, sans-serif; cursor: pointer; padding: 0; }",
    ".lb-vazio { color: #6b7390; margin: 2px 2px 8px; }",
    ".lb-novo { display: grid; gap: 8px; margin-top: 12px; padding-top: 12px; border-top: 1px solid #e6e8f2; }",
    ".lb-novo textarea { width: 100%; min-height: 64px; resize: vertical; padding: 9px 11px; border-radius: 10px; border: 1px solid #d6d9e6; font: inherit; }",
    ".lb-novo__linha { display: flex; gap: 8px; align-items: center; }",
    ".lb-novo input[type=date] { flex: 1; padding: 8px 10px; border-radius: 10px; border: 1px solid #d6d9e6; font: inherit; }",
    ".lb-salvar { border: 0; border-radius: 10px; padding: 9px 16px; font: 700 13px Rubik, sans-serif; background: #6b4fd8; color: #fff; cursor: pointer; }",
    ".lb-salvar:disabled { opacity: .6; cursor: default; }",
    ".lb-erro { color: #c0354d; font-size: 12.5px; min-height: 1em; }"
  ].join("\n");
  document.head.appendChild(estilo);

  var conta = document.createElement("span");
  conta.className = "sino__conta";
  conta.hidden = true;
  sino.appendChild(conta);
  sino.setAttribute("aria-haspopup", "dialog");
  sino.setAttribute("aria-expanded", "false");

  var painel = document.createElement("div");
  painel.className = "lb-painel";
  painel.hidden = true;
  painel.setAttribute("role", "dialog");
  painel.setAttribute("aria-label", "Lembretes da equipe");
  document.body.appendChild(painel);

  function esc(t) { return String(t == null ? "" : t).replace(/[&<>"']/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]; }); }
  function diaBonito(iso, hoje) {
    if (!iso) return "";
    if (iso === hoje) return "hoje";
    var p = iso.split("-"), d = new Date(+p[0], +p[1] - 1, +p[2]), h = hoje.split("-"), dh = new Date(+h[0], +h[1] - 1, +h[2]);
    var dif = Math.round((d - dh) / 86400000);
    if (dif === 1) return "amanhã";
    if (dif === -1) return "ontem";
    var txt = d.toLocaleDateString("pt-BR", { weekday: "short", day: "2-digit", month: "2-digit" });
    return dif < 0 ? txt + " (atrasado " + (-dif) + " dias)" : txt;
  }
  function pedir(url, opcoes) {
    return fetch(url, Object.assign({ credentials: "same-origin", headers: { "Content-Type": "application/json" } }, opcoes || {}))
      .then(function (r) {
        return r.json().catch(function () { return {}; }).then(function (d) {
          if (!r.ok || d.erro) throw new Error(d.erro || "Não consegui agora.");
          return d;
        });
      });
  }

  function desenhar() {
    var d = dados || { agora: [], proximos: [], feitos: [], hoje: "" };
    var n = (d.agora || []).length;
    conta.hidden = !n;
    conta.textContent = n > 9 ? "9+" : String(n);
    sino.setAttribute("aria-label", n ? "Lembretes: " + n + " para hoje" : "Lembretes");
    var h = ['<div class="lb-titulo">Lembretes da equipe<button type="button" class="lb-x" data-lb-fechar aria-label="Fechar">×</button></div>'];
    h.push('<div class="lb-sec">Agora</div>');
    h.push(n ? d.agora.map(function (l) {
      return '<div class="lb-item lb-item--' + (l.atrasado ? "atrasado" : "agora") + '"><div class="lb-item__texto">' + esc(l.texto) +
             '<span class="lb-item__dia">' + esc(diaBonito(l.dia, d.hoje)) + '</span></div>' +
             '<button type="button" class="lb-feito" data-lb-feito="' + l.id + '">Feito</button></div>';
    }).join("") : '<p class="lb-vazio">Nada para hoje.</p>');
    if ((d.proximos || []).length) {
      h.push('<div class="lb-sec">Próximos</div>');
      h.push(d.proximos.map(function (l) {
        return '<div class="lb-item"><div class="lb-item__texto">' + esc(l.texto) + '<span class="lb-item__dia">' + esc(diaBonito(l.dia, d.hoje)) + '</span></div>' +
               '<button type="button" class="lb-x" data-lb-apagar="' + l.id + '" title="Apagar este lembrete" aria-label="Apagar">×</button></div>';
      }).join(""));
    }
    if ((d.feitos || []).length) {
      h.push('<div class="lb-sec">Feitos (7 dias)</div>');
      h.push(d.feitos.map(function (l) {
        return '<div class="lb-item" style="opacity:.7"><div class="lb-item__texto"><s>' + esc(l.texto) + '</s></div>' +
               '<button type="button" class="lb-link" data-lb-desfazer="' + l.id + '">desfazer</button></div>';
      }).join(""));
    }
    h.push('<form class="lb-novo" data-lb-novo><label class="lb-sec" style="margin:0" for="lb-texto">Novo lembrete</label>' +
           '<textarea id="lb-texto" maxlength="1000" placeholder="O que é para lembrar?"></textarea>' +
           '<div class="lb-novo__linha"><input type="date" id="lb-dia" value="' + esc(d.hoje || "") + '" aria-label="Dia">' +
           '<button type="submit" class="lb-salvar">Salvar</button></div><div class="lb-erro" role="alert"></div></form>');
    painel.innerHTML = h.join("");
  }

  function posicionar() {
    var r = sino.getBoundingClientRect();
    var largura = painel.offsetWidth;
    painel.style.top = (r.bottom + window.scrollY + 8) + "px";
    painel.style.left = Math.max(12, Math.min(r.right + window.scrollX - largura, window.scrollX + document.documentElement.clientWidth - largura - 12)) + "px";
  }
  function abrir() { desenhar(); painel.hidden = false; posicionar(); sino.setAttribute("aria-expanded", "true"); }
  function fechar() { painel.hidden = true; sino.setAttribute("aria-expanded", "false"); }

  function carregar(primeira) {
    return pedir(API).then(function (d) {
      dados = d;
      desenhar();
      if (!painel.hidden) posicionar();
      // a primeira entrada do dia neste navegador abre o painel sozinha, se houver lembrete para agora
      if (primeira && (d.agora || []).length) {
        var chave = "lembretes-abertos-" + d.hoje, ja = null;
        try { ja = localStorage.getItem(chave); localStorage.setItem(chave, "1"); } catch (e) { /* sem armazenamento */ }
        if (!ja) abrir();
      }
    }).catch(function () { /* sem a senha ou sem API: o sininho fica quieto */ });
  }

  sino.addEventListener("click", function (ev) {
    ev.stopPropagation();
    if (painel.hidden) { abrir(); carregar(false); } else fechar();
  });
  document.addEventListener("click", function (ev) {
    if (painel.hidden || painel.contains(ev.target)) return;
    fechar();
  });
  document.addEventListener("keydown", function (ev) { if (ev.key === "Escape" && !painel.hidden) { fechar(); sino.focus(); } });
  window.addEventListener("resize", function () { if (!painel.hidden) posicionar(); });

  painel.addEventListener("click", function (ev) {
    var b;
    if (ev.target.closest("[data-lb-fechar]")) { fechar(); return; }
    if ((b = ev.target.closest("[data-lb-feito]"))) {
      b.disabled = true;
      pedir(API + "/" + b.getAttribute("data-lb-feito") + "/feito", { method: "POST", body: "{}" }).then(function () { return carregar(false); })
        .catch(function (e) { b.disabled = false; alert(e.message); });
      return;
    }
    if ((b = ev.target.closest("[data-lb-desfazer]"))) {
      pedir(API + "/" + b.getAttribute("data-lb-desfazer") + "/feito", { method: "POST", body: JSON.stringify({ feito: false }) })
        .then(function () { return carregar(false); }).catch(function (e) { alert(e.message); });
      return;
    }
    if ((b = ev.target.closest("[data-lb-apagar]"))) {
      if (!confirm("Apagar este lembrete?")) return;
      pedir(API + "/" + b.getAttribute("data-lb-apagar"), { method: "DELETE" }).then(function () { return carregar(false); })
        .catch(function (e) { alert(e.message); });
    }
  });
  painel.addEventListener("submit", function (ev) {
    var f = ev.target.closest("[data-lb-novo]");
    if (!f) return;
    ev.preventDefault();
    var texto = f.querySelector("textarea").value.trim(), dia = f.querySelector("input[type=date]").value, erro = f.querySelector(".lb-erro");
    var botao = f.querySelector(".lb-salvar");
    if (!texto) { erro.textContent = "Escreva o lembrete."; return; }
    if (!dia) { erro.textContent = "Escolha o dia."; return; }
    botao.disabled = true; erro.textContent = "";
    pedir(API, { method: "POST", body: JSON.stringify({ texto: texto, dia: dia }) })
      .then(function () { return carregar(false); })
      .catch(function (e) { botao.disabled = false; erro.textContent = e.message; });
  });

  carregar(true);
  // quem deixa o admin aberto o dia todo também vê o lembrete do dia seguinte
  setInterval(function () { if (painel.hidden) carregar(false); }, 10 * 60 * 1000);
})();
