/* O PAINEL DE ESTUDOS (Pedro, 25/10/2026): "o código de todas as nays ... o código inteiro de um lado e na direita várias
   ferramentas de estudo ... cada jargão técnico vai ter um () explicando ... um raio-x de cada função ... se o nó for várias
   funções eu quero todas as opções lado a lado ... um fluxo vertical, uma função por vez ... uma opção exportar ... e se eu
   passar o mouse em cima das funções e tags aparece uma janelinha explicando".
   Os dados: admin/dados/inteligencia/estudo-<nay>.json (scripts/estudo_gerar.py + scripts/estudo_explicar.py). */
(function () {
  "use strict";
  var esc = window.IE.esc, pedir = window.IE.pedir;
  var NAYS = [["parceria", "Parceria"], ["leads", "Leads"], ["olx", "OLX"], ["corretores", "Corretores"], ["captacao", "Captação"], ["cadastro", "Cadastro"]];
  var DICA_DA_TAG = {
    "usa o modelo (IA)": "Pergunta a um modelo de inteligência artificial (a Luna, o JEV...). É a parte que 'pensa' e pode custar tokens (o pedaço de texto que o modelo cobra).",
    "lê o banco": "Consulta o banco de dados (onde ficam guardados imóveis, conversas e configurações) sem mudar nada.",
    "grava no banco": "Escreve ou atualiza alguma coisa no banco de dados: depois disso, a informação fica guardada.",
    "manda mensagem": "Envia algo para fora: WhatsApp (pela Z-API), o grupo da equipe ou o chat da OLX.",
    "regra fixa": "Decide por uma regra escrita no código (um 'se isso, então aquilo' ou um padrão de texto), sem perguntar ao modelo.",
    "decide o caminho": "Escolhe o que acontece depois: qual resposta, qual ferramenta, qual etapa.",
    "confere/barra": "Confere se está certo e barra o que está errado antes de sair (uma parede).",
    "monta texto": "Junta pedaços para formar um texto: a mensagem, o card do imóvel ou o que o modelo vai ler.",
    "calcula": "Faz uma conta ou compara valores (preço, distância, nota).",
    "espera/tempo": "Mexe com tempo: espera, prazo, horário de Manaus.",
    "registra (rastro)": "Anota o que aconteceu (o rastro) para dar para ver depois onde errou.",
    "ajuda pequena": "Uma funçãozinha de apoio, usada por outras (limpar um texto, formatar um número...)."
  };
  var GLOSSARIO_BASE = {
    "função": "Um pedaço de código com nome, que faz uma tarefa e pode ser chamado de outros lugares.",
    "webhook": "O endereço que outro sistema (a Z-API, do WhatsApp) chama sozinho quando chega uma mensagem.",
    "JSON": "Um jeito de escrever dados organizados em campos, tipo um formulário: {\"nome\": \"Ana\"}.",
    "regex": "Um padrão para achar pedaços de texto (ex.: 'qualquer número de 4 dígitos').",
    "prompt": "O texto de instruções que o modelo de IA lê antes de responder.",
    "token": "O pedacinho de texto que o modelo de IA lê ou escreve; é por ele que se paga.",
    "template": "Um texto pronto com lacunas que o código preenche (o nome, o valor, o código).",
    "banco": "O banco de dados (naydb): onde ficam guardados imóveis, conversas e configurações.",
    "SQL": "A língua para pedir coisas ao banco de dados (buscar, gravar, juntar tabelas).",
    "trace": "O rastro: a anotação de cada etapa que o turno passou, com tempo e custo.",
    "turno": "Uma rodada da conversa: o que a pessoa mandou e o que a Nay respondeu.",
    "rajada": "Várias mensagens seguidas da mesma pessoa, que a Nay junta antes de responder.",
    "Z-API": "O serviço que liga o nosso sistema ao WhatsApp (manda e recebe mensagens).",
    "Luna": "O modelo de IA (gpt-6-luna) que a Nay usa para ler e escrever.",
    "JEV": "Um modelo de IA que só responde perguntas fechadas (sim/não, uma opção): rápido e barato.",
    "None": "Em Python, 'nada': a função não devolveu nada ou o valor não existe.",
    "dict": "Em Python, um dicionário: uma lista de pares nome → valor, tipo um formulário.",
    "list": "Em Python, uma lista de coisas em ordem.",
    "return": "O que a função devolve para quem a chamou.",
    "deploy": "Subir o código novo para o servidor, para valer de verdade."
  };
  var cache = {}, atual = null, glossario = {};
  var alvo = document.getElementById("ie-estudo");
  var nays = document.getElementById("ie-est-nays");

  nays.innerHTML = NAYS.map(function (n) { return '<button type="button" role="tab" aria-selected="false" data-est-nay="' + n[0] + '">' + esc(n[1]) + "</button>"; }).join("");
  nays.addEventListener("click", function (ev) {
    var b = ev.target.closest("[data-est-nay]");
    if (b && nays.contains(b)) escolher(b.getAttribute("data-est-nay"));
  });

  function carregar(chave) {
    if (cache[chave]) return Promise.resolve(cache[chave]);
    return pedir("dados/inteligencia/estudo-" + chave + ".json?v=" + Date.now()).then(function (d) { cache[chave] = d; return d; });
  }

  /* ---------- o código colorido ---------- */
  var PY_K = /^(def|class|return|if|elif|else|for|while|in|not|and|or|is|None|True|False|import|from|as|with|try|except|finally|raise|lambda|yield|pass|break|continue|global|async|await|del)$/;
  var SQL_K = /^(select|from|where|and|or|not|in|is|null|join|left|on|as|case|when|then|else|end|create|or|replace|function|returns|language|begin|return|declare|if|insert|into|values|update|set|delete|with|group|by|order|limit|union|all|distinct|exists|coalesce|true|false|security|definer|stable|table|perform|loop|elsif|raise|notice)$/i;
  function colorir(codigo, sql) {
    var rx = sql ? /(--[^\n]*)|('(?:[^']|'')*')|(\b\d+(?:\.\d+)?\b)|([A-Za-z_][A-Za-z0-9_]*)|(\s+|.)/g
                 : /(#[^\n]*)|("""[\s\S]*?"""|'''[\s\S]*?'''|[rbfu]{0,2}"(?:\\.|[^"\\\n])*"|[rbfu]{0,2}'(?:\\.|[^'\\\n])*')|(@[A-Za-z_][\w.]*)|(\b\d+(?:\.\d+)?\b)|([A-Za-z_][A-Za-z0-9_]*)|(\s+|.)/g;
    // a cor de um texto de várias linhas fecha e reabre em cada linha (cada linha é um <span class="l"> próprio)
    function cor(cls, t) { return t.split("\n").map(function (s) { return '<span class="' + cls + '">' + esc(s) + "</span>"; }).join("\n"); }
    var out = "", m, depoisDoDef = false;
    while ((m = rx.exec(codigo)) !== null) {
      var t = m[0];
      if (m[1]) out += cor("c", t);
      else if (m[2]) out += cor("s", t);
      else if (!sql && m[3]) out += cor("d", t);
      else if ((sql ? m[3] : m[4])) out += cor("n", t);
      else if ((sql ? m[4] : m[5])) {
        if (depoisDoDef) { out += '<span class="f">' + esc(t) + "</span>"; depoisDoDef = false; }
        else if (sql ? SQL_K.test(t) : PY_K.test(t)) { out += '<span class="k">' + esc(t) + "</span>"; depoisDoDef = !sql && (t === "def" || t === "class"); }
        else out += esc(t);
      } else out += esc(t);
    }
    return out;
  }
  function blocoDeCodigo(codigo, inicio, sql) {
    var linhas = colorir(codigo, sql).split("\n");
    return '<pre class="ie-codigo">' + linhas.map(function (l, i) { return '<span class="l" data-n="' + (inicio + i) + '">' + (l || " ") + "</span>"; }).join("") + "</pre>";
  }

  /* ---------- as palavras difíceis com a janelinha ---------- */
  // os termos do glossário, do mais longo ao mais curto, com a regex pronta (refeito ao escolher a Nay)
  var termos = [];
  function prepararTermos() {
    termos = Object.keys(glossario).filter(function (t) { return t.length >= 3; }).sort(function (a, b) { return b.length - a.length; })
      .map(function (t) { return { t: t, rx: new RegExp("(^|[^\\wÀ-ú])(" + t.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + ")(?![\\wÀ-ú])", "i") }; });
  }
  // marca a 1ª vez que cada termo aparece no TEXTO PURO, sem sobrepor; só depois monta o HTML
  function marcarJargoes(texto) {
    texto = String(texto || "");
    var faixas = [], vistos = {};
    termos.forEach(function (x) {
      var k = x.t.toLowerCase();
      if (vistos[k]) return;
      var m = x.rx.exec(texto);
      if (!m) return;
      var ini = m.index + m[1].length, fim = ini + m[2].length;
      if (faixas.some(function (f) { return ini < f.fim && fim > f.ini; })) return;
      vistos[k] = true;
      faixas.push({ ini: ini, fim: fim, termo: x.t });
    });
    faixas.sort(function (a, b) { return a.ini - b.ini; });
    var h = "", p = 0;
    faixas.forEach(function (f) {
      h += esc(texto.slice(p, f.ini)) + '<span class="ie-jargao" data-dica-titulo="' + esc(f.termo) + '" data-dica="' +
        esc(glossario[f.termo]) + '">' + esc(texto.slice(f.ini, f.fim)) + "</span>";
      p = f.fim;
    });
    return h + esc(texto.slice(p));
  }
  function nomeCurto(fid) { var p = fid.split(":"); return p[1] || p[0]; }
  function ligacoes(lista, d) {
    return (lista || []).slice(0, 14).map(function (fid) {
      var f = d.funcoes[fid];
      return '<button type="button" class="ie-liga" data-ir-fn="' + esc(fid) + '" data-dica-titulo="' + esc(fid) + '" data-dica="' + esc(f && f.resumo ? f.resumo : "Clique para ir até ela.") + '">' + esc(nomeCurto(fid)) + "</button>";
    }).join("") || "<span class=\"ie-sem-exp\">nenhuma</span>";
  }
  function cartao(fid, d) {
    var f = d.funcoes[fid];
    if (!f) return "";
    var sql = f.tipo === "sql";
    var onde = sql ? (f.servidor || "banco") : (f.arquivo + " · linhas " + f.linha + "–" + f.fim);
    var tags = (f.tags || []).map(function (t) { return '<span class="ie-tag" data-dica-titulo="' + esc(t) + '" data-dica="' + esc(DICA_DA_TAG[t] || "") + '">' + esc(t) + "</span>"; }).join("");
    var estudo;
    if (f.explicacao) {
      estudo = '<h4>O que faz</h4><p class="ie-resumo-fn">' + marcarJargoes(f.resumo || "") + "</p><p>" + marcarJargoes(f.explicacao) + "</p>" +
        ((f.passos || []).length ? "<h4>Passo a passo</h4><ol>" + f.passos.map(function (p) { return "<li>" + marcarJargoes(p) + "</li>"; }).join("") + "</ol>" : "") +
        ((f.jargoes || []).length ? '<h4>Palavras difíceis</h4><div class="ie-jargoes">' + f.jargoes.map(function (j) {
          return '<span class="ie-jargao" data-dica-titulo="' + esc(j.termo) + '" data-dica="' + esc(j.significado) + '">' + esc(j.termo) + "</span>"; }).join("") + "</div>" : "");
    } else {
      estudo = '<p class="ie-sem-exp">A explicação desta função ainda não foi escrita.</p>' + (f.doc ? "<p>" + esc(f.doc) + "</p>" : "");
    }
    estudo += (tags ? '<h4>Etiquetas</h4><div class="ie-tags">' + tags + "</div>" : "") +
      (sql ? "" : "<h4>Ela chama</h4><div>" + ligacoes(f.chama, d) + "</div>") +
      "<h4>Quem chama ela</h4><div>" + ligacoes(f.chamada_por, d) + "</div>" +
      ((f.sql || []).length ? "<h4>Usa no banco</h4><div>" + ligacoes(f.sql.map(function (s) { return "banco:" + s; }), d) + "</div>" : "") +
      "<h4>Onde mora</h4><p class=\"ie-fn__onde\">" + esc(sql ? f.servidor : (d.servidor.split(" ")[0] + "/" + f.arquivo + ":" + f.linha)) + "</p>";
    return '<article class="ie-fn" id="fn-' + esc(fid.replace(/[^\w-]/g, "_")) + '" data-fn="' + esc(fid) + '">' +
      '<div class="ie-fn__cab"><span class="ie-fn__nome" data-dica-titulo="' + esc(f.nome) + '" data-dica="' + esc(f.resumo || f.doc || "") + '">' + esc(f.nome) + (sql ? "() · SQL" : "()") + "</span>" +
      '<span class="ie-fn__onde">' + esc(onde) + "</span>" + (tags ? '<span class="ie-tags">' + tags + "</span>" : "") + "</div>" +
      '<div class="ie-fn__corpo">' + blocoDeCodigo(f.codigo || "", f.linha || 1, sql) + '<div class="ie-estudo">' + estudo + "</div></div></article>";
  }

  /* ---------- a Nay escolhida: as etapas, uma por vez, desenhadas quando chegam perto da tela ---------- */
  var olho = null;
  function desenharEtapa(sec, d) {
    if (sec.getAttribute("data-feita")) return;
    sec.setAttribute("data-feita", "1");
    var e = d.etapas[+sec.getAttribute("data-etapa")];
    var corpo = sec.querySelector(".ie-etapa__fns");
    var MAX = 30, fns = e.funcoes;
    function lote(de) {
      var h = fns.slice(de, de + MAX).map(function (fid) { return cartao(fid, d); }).join("");
      var b = corpo.querySelector(".ie-mais"); if (b) b.remove();
      corpo.insertAdjacentHTML("beforeend", h);
      if (de + MAX < fns.length) {
        corpo.insertAdjacentHTML("beforeend", '<button type="button" class="ie-mais">Mostrar mais ' + (fns.length - de - MAX) + " funções</button>");
        corpo.querySelector(".ie-mais").addEventListener("click", function () { lote(de + MAX); });
      }
    }
    lote(0);
  }
  function escolher(chave) {
    nays.querySelectorAll("[data-est-nay]").forEach(function (b) { b.setAttribute("aria-selected", b.getAttribute("data-est-nay") === chave ? "true" : "false"); });
    alvo.innerHTML = '<p class="ag-vazio">Lendo o código da Nay…</p>';
    carregar(chave).then(function (d) {
      atual = d;
      glossario = Object.assign({}, GLOSSARIO_BASE);
      Object.keys(d.funcoes).forEach(function (k) { (d.funcoes[k].jargoes || []).forEach(function (j) { if (j.termo && !glossario[j.termo]) glossario[j.termo] = j.significado; }); });
      prepararTermos();
      var nFn = 0, nSql = 0, nExp = 0;
      Object.keys(d.funcoes).forEach(function (k) { if (d.funcoes[k].tipo === "sql") nSql++; else nFn++; if (d.funcoes[k].explicacao) nExp++; });
      var h = '<div class="ie-cartao ie-est-nay"><h2>' + esc(d.nome) + "</h2><p>" + esc(d.descricao) + "</p>" +
        '<p class="ie-camada__onde">Atende: ' + esc(d.quem) + " · mora em: " + esc(d.servidor) + " · " + d.arquivos.length + " arquivos, " + nFn + " funções, " + nSql + " do banco · " + nExp + " explicadas</p>" +
        '<p>Role a tela: cada etapa é um pedaço do atendimento, na ordem em que acontece. Em cada função, o código está à esquerda e o estudo à direita. Passe o mouse nas palavras sublinhadas e nas etiquetas para ver o que querem dizer.</p>' +
        '<div class="ie-indice">' + d.etapas.map(function (e, i) { return '<a href="#etapa-' + i + '" data-ir-etapa="' + i + '">' + (i + 1) + ". " + esc(e.titulo) + " (" + e.funcoes.length + ")</a>"; }).join("") + "</div></div>";
      h += d.etapas.map(function (e, i) {
        return '<section class="ie-etapa" id="etapa-' + i + '" data-etapa="' + i + '"><div class="ie-etapa__cab"><span class="ie-etapa__n">' + (i + 1) + "</span><h3>" + esc(e.titulo) + "</h3></div>" +
          '<p class="ie-etapa__exp">' + marcarJargoes(e.explicacao) + (e.lado_a_lado ? " <b>As opções estão lado a lado: role para o lado.</b>" : "") + "</p>" +
          '<div class="ie-etapa__fns' + (e.lado_a_lado ? " ie-lado" : "") + '"></div></section>';
      }).join("");
      alvo.innerHTML = h;
      if (olho) olho.disconnect();
      olho = "IntersectionObserver" in window ? new IntersectionObserver(function (vs) {
        vs.forEach(function (v) { if (v.isIntersecting) desenharEtapa(v.target, d); });
      }, { rootMargin: "800px 0px" }) : null;
      alvo.querySelectorAll(".ie-etapa").forEach(function (s, i) { if (olho) olho.observe(s); else if (i < 3) desenharEtapa(s, d); });
    }).catch(function (e) { alvo.innerHTML = '<p class="ag-vazio">Não li o código desta Nay: ' + esc(e.message) + "</p>"; });
  }

  /* ir até uma função (das ligações "ela chama", "quem chama ela" e da busca) */
  function irAte(fid) {
    if (!atual) return;
    var i = atual.etapas.findIndex(function (e) { return e.funcoes.indexOf(fid) >= 0; });
    if (i < 0) return;
    var sec = document.getElementById("etapa-" + i);
    desenharEtapa(sec, atual);
    var pos = atual.etapas[i].funcoes.indexOf(fid);
    while (!document.getElementById("fn-" + fid.replace(/[^\w-]/g, "_")) && sec.querySelector(".ie-mais") && pos >= 0) sec.querySelector(".ie-mais").click();
    var el = document.getElementById("fn-" + fid.replace(/[^\w-]/g, "_"));
    if (!el) return;
    document.querySelectorAll(".ie-fn--achada").forEach(function (x) { x.classList.remove("ie-fn--achada"); });
    el.classList.add("ie-fn--achada");
    el.scrollIntoView({ behavior: "smooth", block: "start" });
  }
  alvo.addEventListener("click", function (ev) {
    var b = ev.target.closest("[data-ir-fn]");
    if (b && alvo.contains(b)) { ev.preventDefault(); irAte(b.getAttribute("data-ir-fn")); return; }
    var a = ev.target.closest("[data-ir-etapa]");
    if (a && alvo.contains(a)) {
      ev.preventDefault();
      var s = document.getElementById("etapa-" + a.getAttribute("data-ir-etapa"));
      desenharEtapa(s, atual); s.scrollIntoView({ behavior: "smooth", block: "start" });
    }
  });

  /* a busca: o nome, o resumo ou um pedaço do código; Enter de novo vai para a próxima */
  var achadas = [], qual = -1, ultimo = "";
  document.getElementById("ie-est-busca").addEventListener("keydown", function (ev) {
    if (ev.key !== "Enter" || !atual) return;
    ev.preventDefault();
    var q = ev.target.value.trim().toLowerCase();
    if (!q) return;
    if (q !== ultimo) {
      ultimo = q; qual = -1;
      achadas = Object.keys(atual.funcoes).filter(function (k) { var f = atual.funcoes[k]; return (f.nome + " " + (f.resumo || "") + " " + f.codigo).toLowerCase().indexOf(q) >= 0; });
    }
    if (!achadas.length) { ev.target.title = "nada achado"; return; }
    qual = (qual + 1) % achadas.length;
    ev.target.title = (qual + 1) + " de " + achadas.length;
    irAte(achadas[qual]);
  });

  /* exportar: todos os códigos e funções de cada Nay, e onde estão, num arquivo só (.md) */
  document.getElementById("ie-est-exportar").addEventListener("click", function () {
    var b = this; b.disabled = true; b.textContent = "Juntando…";
    Promise.all(NAYS.map(function (n) { return carregar(n[0]).catch(function () { return null; }); })).then(function (ds) {
      var t = "# O código das Nays da Imob Easy (exportado em " + new Date().toLocaleString("pt-BR") + ")\n\n" +
        "Cada Nay: onde mora, as etapas do atendimento, cada arquivo com as funções (o que fazem) e o código inteiro.\n\n";
      ds.forEach(function (d) {
        if (!d) return;
        t += "\n\n---\n\n# " + d.nome + "\n\n" + d.descricao + "\n\n- Atende: " + d.quem + "\n- Mora em: " + d.servidor + "\n\n## As etapas do atendimento\n\n";
        d.etapas.forEach(function (e, i) { t += (i + 1) + ". **" + e.titulo + "**: " + e.explicacao + "\n   Funções: " + e.funcoes.map(nomeCurto).join(", ") + "\n"; });
        t += "\n## Os arquivos\n";
        d.arquivos.forEach(function (a) {
          t += "\n### " + a.caminho + " (" + a.linhas + " linhas; no servidor: " + a.servidor + ")\n\n" + (a.doc ? a.doc + "\n\n" : "");
          a.funcoes.forEach(function (fid) { var f = d.funcoes[fid]; t += "- `" + f.nome + "` (linhas " + f.linha + "–" + f.fim + "): " + (f.resumo || (f.doc || "").split("\n")[0]) + "\n"; });
          t += "\n```python\n" + a.codigo + "\n```\n";
        });
        var sqls = Object.keys(d.funcoes).filter(function (k) { return d.funcoes[k].tipo === "sql"; });
        if (sqls.length) {
          t += "\n## As funções do banco que ela usa\n";
          sqls.forEach(function (k) { var f = d.funcoes[k]; t += "\n### " + f.nome + " (" + f.servidor + ")\n\n" + (f.resumo ? f.resumo + "\n\n" : "") + "```sql\n" + f.codigo + "\n```\n"; });
        }
      });
      var url = URL.createObjectURL(new Blob([t], { type: "text/markdown;charset=utf-8" }));
      var a = document.createElement("a");
      a.href = url; a.download = "codigo-das-nays-" + new Date().toISOString().slice(0, 10) + ".md";
      document.body.appendChild(a); a.click(); a.remove();
      setTimeout(function () { URL.revokeObjectURL(url); }, 4000);
    }).finally(function () { b.disabled = false; b.textContent = "Exportar"; });
  });

  /* a janelinha: qualquer [data-dica] da página (etiquetas, palavras difíceis, nomes de função) */
  var dica = document.getElementById("ie-dica");
  document.addEventListener("mouseover", function (ev) {
    var el = ev.target.closest && ev.target.closest("[data-dica]");
    if (!el || !el.getAttribute("data-dica")) { dica.hidden = true; return; }
    dica.innerHTML = (el.getAttribute("data-dica-titulo") ? "<b>" + esc(el.getAttribute("data-dica-titulo")) + "</b>" : "") + esc(el.getAttribute("data-dica"));
    dica.hidden = false;
    var r = el.getBoundingClientRect(), w = Math.min(320, window.innerWidth - 24);
    dica.style.left = Math.max(12, Math.min(r.left, window.innerWidth - w - 12)) + "px";
    dica.style.top = (r.bottom + 8 + 120 > window.innerHeight ? Math.max(12, r.top - dica.offsetHeight - 8) : r.bottom + 8) + "px";
  });
  window.addEventListener("scroll", function () { dica.hidden = true; }, { passive: true });

  window.IEstudos = { abrir: function () { if (!atual) escolher("parceria"); } };
  var painel = document.querySelector('[data-painel="estudos"]');
  if (painel && !painel.hidden) window.IEstudos.abrir();
})();
