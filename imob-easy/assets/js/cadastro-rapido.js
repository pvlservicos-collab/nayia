/* ==========================================================================
   Imob Easy — Aba CADASTRO RÁPIDO de Imóveis (site e CRM)

   Pedro, 09/10/2026: "quero uma tela de cadastro de imóveis, hoje temos várias
   fontes, WhatsApp, OLX, quero todos agrupados em uma página ... aba nova,
   cadastro rápido, ele abre um popup e vamos passando imóvel por imóvel e
   marcando os campos que faltam, podemos chamar um condomínio e as informações
   do condomínio preencher no automático, e se for OLX já tem ali naquele popup
   o extrator da OLX, e podemos aprovar ali, aprovado ali já fica disponível
   para a Nay oferecer, vai ser uma curadoria geral de todas as fontes,
   incluindo os que foram novos cadastros pelos proprietários mesmo se faltar
   algo, foto e tudo mais".

   A FILA é a do Cadastro Pendente (nai_cadastro_pendente, 248): rascunhos de
   todas as origens (OLX, captação no CRM, secretária, site), a ficha que o dono
   ditou na conversa sem imóvel cadastrado, bloqueados e o que está no ar
   faltando o essencial. Aqui ela vira uma sequência, uma por vez.

   O POPUP não tem um segundo cadastro: o corpo é o próprio editor
   (imovel-editar.html) num iframe da mesma origem -- condomínio que preenche o
   endereço, os imóveis do condomínio, as fotos, o "falta preencher". Em cima, a
   faixa da curadoria: de onde veio, o que falta, Importar tudo, Pular e APROVAR.
     · Aprovar = salva o que estiver aberto no editor e põe a situação em
       Disponível (PUT de sempre): no site e na Nay, menos imóvel de parceiro
       (a regra da 274 e da "parceria nunca sai" valem iguais).
     · Ficha da conversa sem imóvel: "Criar o imóvel com esta ficha" faz o
       pré-cadastro (Rascunho, ligado ao dono, com as fotos dele) e abre o editor.
     · OLX: o favorito "Enviar para Imob Easy" desta aba traz o anúncio para cá
       (#olx=...); o pré-cadastro e as fotos entram e o popup abre nele.
   ========================================================================== */
(function () {
  "use strict";

  var aba = document.querySelector('[data-painel-abre="rapido"]');
  var painel = document.querySelector('[data-painel="rapido"]');
  if (!aba || !painel) return;

  function $(id) { return document.getElementById(id); }
  function esc(t) {
    return String(t == null ? "" : t).replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }
  function cor(p) { return p >= 90 ? "#3f9c6d" : p >= 50 ? "#c4762f" : "#b42323"; }

  /* ---- de onde veio ---------------------------------------------------------- */
  var FONTES = [
    { k: "", rotulo: "Todas" },
    { k: "olx", rotulo: "OLX" },
    { k: "conversa", rotulo: "Conversa do dono" },
    { k: "crm", rotulo: "Captação (CRM)" },
    { k: "secretaria", rotulo: "Secretária" },
    { k: "site", rotulo: "Site" },
    { k: "antigo", rotulo: "Site antigo" },
    { k: "outros", rotulo: "Outras" }
  ];
  function fonteDe(it) {
    if (it.fonte === "ficha") return "conversa";
    var o = String(it.origem || "").toLowerCase();
    if (o === "olx") return "olx";
    if (o === "captacao") return "conversa";
    if (o === "crm") return "crm";
    if (o === "secretaria") return "secretaria";
    if (o === "site") return "site";
    if (o.indexOf("planilha") === 0 || o.indexOf("site_antigo") >= 0) return "antigo";
    return "outros";
  }
  function rotuloDaFonte(k) {
    var f = FONTES.filter(function (x) { return x.k === k; })[0];
    return f ? f.rotulo : k;
  }
  /* primeiro o que ainda NÃO está no ar (é o que espera a aprovação); depois o resto */
  function foraDoAr(it) {
    return it.fonte === "ficha" || it.status === "Rascunho" ||
      it.motivos.some(function (m) { return /bloqueado|Rascunho/.test(m); });
  }

  /* ---- o estilo (sobre as variáveis do site: segue o tema no CRM) ------------- */
  var css = document.createElement("style");
  css.textContent =
    ".cr-topo{display:flex;flex-wrap:wrap;gap:10px;align-items:center;margin:0 0 12px}" +
    ".cr-chips{display:flex;flex-wrap:wrap;gap:6px}" +
    ".cr-chip{height:32px;padding:0 12px;border-radius:999px;border:1px solid var(--borda-forte,#cfcfca);background:var(--superficie,#fff);color:var(--texto,#16161a);font:inherit;font-size:13px;cursor:pointer}" +
    ".cr-chip b{margin-left:4px}" +
    ".cr-chip[aria-pressed=true]{background:var(--roxo,#6d28d9);border-color:var(--roxo,#6d28d9);color:#fff}" +
    ".cr-comecar{height:40px;padding:0 18px;border:0;border-radius:999px;background:#16a34a;color:#fff;font:inherit;font-weight:700;cursor:pointer}" +
    ".cr-comecar[disabled]{opacity:.5;cursor:default}" +
    ".cr-so{display:inline-flex;gap:6px;align-items:center;font-size:13px;color:var(--texto-medio,#3f3f45)}" +
    ".cr-olx{margin:0 0 14px;padding:12px 14px;border:1px dashed var(--borda-forte,#cfcfca);border-radius:12px;background:var(--superficie,#fff)}" +
    ".cr-olx form{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin-top:8px}" +
    ".cr-olx input{flex:1 1 320px;height:36px;padding:0 10px;border:1px solid var(--borda-forte,#cfcfca);border-radius:8px;font:inherit;background:var(--superficie,#fff);color:var(--texto,#16161a)}" +
    ".cr-olx .cr-fav{display:inline-flex;align-items:center;height:32px;padding:0 12px;border-radius:999px;background:#6e0ad6;color:#fff;font-weight:700;font-size:13px;text-decoration:none;cursor:grab}" +
    ".cr-nota{font-size:12.5px;color:var(--texto-fraco,#6f6f74);line-height:1.4}" +
    ".cr-lista{width:100%}" +
    ".cr-lista td{vertical-align:top}" +
    ".cr-barrinha{display:inline-block;width:70px;height:6px;border-radius:4px;background:var(--borda,#e2e2de);overflow:hidden;vertical-align:middle;margin-right:6px}" +
    ".cr-barrinha>i{display:block;height:100%;border-radius:4px}" +
    /* o popup */
    ".cr-veu{position:fixed;inset:0;z-index:2000;background:rgba(0,0,0,.55);display:flex;align-items:stretch;justify-content:center;padding:14px}" +
    ".cr-caixa{flex:1;max-width:1500px;display:flex;flex-direction:column;border-radius:14px;overflow:hidden;background:var(--fundo,#f4f4f2);box-shadow:0 20px 60px rgba(0,0,0,.4)}" +
    ".cr-faixa{display:flex;flex-wrap:wrap;gap:8px 14px;align-items:center;padding:10px 14px;background:var(--superficie,#fff);border-bottom:1px solid var(--borda,#e2e2de)}" +
    ".cr-nav{display:flex;gap:6px;align-items:center;font-weight:700;white-space:nowrap}" +
    ".cr-nav button,.cr-acao{height:34px;padding:0 12px;border-radius:999px;border:1px solid var(--borda-forte,#cfcfca);background:var(--superficie,#fff);color:var(--texto,#16161a);font:inherit;font-size:13px;cursor:pointer}" +
    ".cr-nav button[disabled],.cr-acao[disabled]{opacity:.45;cursor:default}" +
    ".cr-quem{flex:1 1 320px;min-width:0}" +
    ".cr-quem b{font-size:15px}" +
    ".cr-quem .cr-sub{display:block;font-size:12.5px;color:var(--texto-fraco,#6f6f74);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}" +
    ".cr-fonte{display:inline-block;margin-right:6px;padding:1px 8px;border-radius:999px;font-size:11px;font-weight:700;letter-spacing:.04em;text-transform:uppercase;background:var(--roxo-suave,#f3edff);color:var(--roxo,#6d28d9)}" +
    ".cr-falta{font-size:12.5px;color:#b45309}" +
    ".cr-acoes{display:flex;gap:6px;flex-wrap:wrap;align-items:center}" +
    ".cr-aprovar{height:36px;padding:0 16px;border:0;border-radius:999px;background:#16a34a;color:#fff;font:inherit;font-weight:700;cursor:pointer}" +
    ".cr-aprovar[disabled]{opacity:.5;cursor:default}" +
    ".cr-fechar{width:36px;height:36px;border-radius:999px;border:0;background:transparent;color:var(--texto,#16161a);font-size:20px;cursor:pointer}" +
    ".cr-recado{width:100%;font-size:12.5px;min-height:0}" +
    ".cr-recado--ok{color:#15803d}.cr-recado--erro{color:#b42323}" +
    ".cr-corpo{flex:1;min-height:0;position:relative;background:var(--fundo,#f4f4f2)}" +
    ".cr-corpo iframe{position:absolute;inset:0;width:100%;height:100%;border:0;background:transparent}" +
    ".cr-ficha{max-width:760px;margin:24px auto;padding:20px 22px;border-radius:14px;background:var(--superficie,#fff);border:1px solid var(--borda,#e2e2de)}" +
    ".cr-ficha dl{display:grid;grid-template-columns:max-content 1fr;gap:6px 16px;margin:12px 0 16px}" +
    ".cr-ficha dt{color:var(--texto-fraco,#6f6f74)}.cr-ficha dd{margin:0}";
  document.head.appendChild(css);

  /* ---- a aba ---------------------------------------------------------------- */
  painel.innerHTML =
    '<div class="cr-olx">' +
      "<b>Trazer da OLX</b> " +
      '<span class="cr-nota">Arraste o botão roxo para a barra de favoritos uma vez. Na página do anúncio da OLX, clique nele: ' +
      "o anúncio, as fotos e os dados entram aqui como pré-cadastro e o cadastro rápido abre nele.</span>" +
      '<form id="cr-olx-form">' +
        '<a class="cr-fav" id="cr-fav" href="#" title="Arraste para a barra de favoritos">Enviar para Imob Easy</a>' +
        '<input id="cr-olx-link" type="url" placeholder="ou cole aqui o link do anúncio da OLX e abra" aria-label="Link do anúncio da OLX">' +
        '<button class="cr-acao" type="submit">Abrir o anúncio</button>' +
      "</form>" +
      '<div class="cr-nota" id="cr-olx-recado" role="status"></div>' +
    "</div>" +
    '<div class="cr-topo">' +
      '<div class="cr-chips" id="cr-chips"></div>' +
      '<label class="cr-so"><input type="checkbox" id="cr-so-fora" checked> só o que ainda não está no ar</label>' +
      '<button class="cr-comecar" type="button" id="cr-comecar" disabled>Começar a curadoria</button>' +
    "</div>" +
    '<div class="tabela-envolucro"><div class="tabela-rolagem"><table class="tabela cr-lista">' +
      '<thead><tr><th scope="col">Imóvel</th><th scope="col">De onde veio</th><th scope="col">Cadastro</th><th scope="col">Por que está aqui</th><th scope="col"></th></tr></thead>' +
      '<tbody id="cr-corpo"><tr><td colspan="5">Carregando…</td></tr></tbody>' +
    "</table></div></div>";

  var itens = null;
  var fonte = "";

  function visiveis() {
    if (!itens) return [];
    var so = $("cr-so-fora").checked;
    return itens.filter(function (it) {
      return (!fonte || fonteDe(it) === fonte) && (!so || foraDoAr(it));
    }).sort(function (a, b) {
      return (foraDoAr(b) ? 1 : 0) - (foraDoAr(a) ? 1 : 0);
    });
  }

  function pintar() {
    var so = $("cr-so-fora").checked;
    var base = (itens || []).filter(function (it) { return !so || foraDoAr(it); });
    $("cr-chips").innerHTML = FONTES.map(function (f) {
      var n = base.filter(function (it) { return !f.k || fonteDe(it) === f.k; }).length;
      if (f.k && !n) return "";
      return '<button class="cr-chip" type="button" data-fonte="' + f.k + '" aria-pressed="' + (fonte === f.k) + '">' +
        esc(f.rotulo) + "<b>" + n + "</b></button>";
    }).join("");
    var lista = visiveis();
    $("cr-comecar").disabled = !lista.length;
    $("cr-comecar").textContent = lista.length ? "Começar a curadoria (" + lista.length + ")" : "Nada esperando aqui";
    $("cr-corpo").innerHTML = lista.length ? lista.slice(0, 200).map(function (it, i) {
      var pct = it.pct == null ? null : Number(it.pct);
      return "<tr><td><b>" + esc(it.titulo) + "</b><br><span class=\"sub\">" +
          (it.codigo ? "#" + it.codigo + " · " : "sem cadastro · ") + esc([it.tipo, it.bairro, it.status].filter(Boolean).join(" · ")) +
          (it.dono ? " · dono: " + esc(it.dono) : "") + "</span></td>" +
        '<td><span class="cr-fonte">' + esc(rotuloDaFonte(fonteDe(it))) + "</span></td>" +
        "<td>" + (pct == null ? '<span class="sub">—</span>' :
          '<span class="cr-barrinha"><i style="width:' + pct + "%;background:" + cor(pct) + '"></i></span><b style="color:' + cor(pct) + '">' + pct + "%</b>") +
          (it.falta && it.falta.length ? '<div class="sub">falta ' + esc(it.falta.slice(0, 3).join(", ")) + (it.falta.length > 3 ? " +" + (it.falta.length - 3) : "") + "</div>" : "") + "</td>" +
        '<td class="sub">' + esc(it.motivos.join(" · ")) + "</td>" +
        '<td><button class="cr-acao" type="button" data-abrir="' + i + '">Abrir</button></td></tr>';
    }).join("") : '<tr><td colspan="5">Nada esperando aqui — o cadastro está em dia.</td></tr>';
  }

  function carregar(depois) {
    return fetch("/admin/api/imoveis/cadastro-pendente", { credentials: "same-origin" })
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (d) { itens = d.itens || []; pintar(); if (depois) depois(); })
      .catch(function () {
        $("cr-corpo").innerHTML = '<tr><td colspan="5">Não foi possível carregar a fila (a senha do /admin é necessária).</td></tr>';
      });
  }

  aba.addEventListener("click", function () { if (!itens) carregar(); });
  $("cr-so-fora").addEventListener("change", pintar);
  $("cr-chips").addEventListener("click", function (e) {
    var b = e.target.closest("[data-fonte]");
    if (b) { fonte = b.getAttribute("data-fonte"); pintar(); }
  });
  $("cr-comecar").addEventListener("click", function () { abrir(visiveis(), 0); });
  $("cr-corpo").addEventListener("click", function (e) {
    var b = e.target.closest("[data-abrir]");
    if (b) abrir(visiveis(), Number(b.getAttribute("data-abrir")));
  });

  /* ---- o popup -------------------------------------------------------------- */
  var fila = [], pos = 0, veu = null, ocupado = false;
  var feitos = {};          // o que já foi aprovado nesta rodada

  function chave(it) { return it.codigo ? "i" + it.codigo : "f" + it.fichaId; }

  function abrir(lista, inicio) {
    fila = lista.slice();
    pos = Math.max(0, Math.min(inicio || 0, fila.length - 1));
    if (!fila.length) return;
    if (!veu) {
      veu = document.createElement("div");
      veu.className = "cr-veu";
      veu.setAttribute("role", "dialog");
      veu.setAttribute("aria-label", "Cadastro rápido");
      veu.innerHTML =
        '<div class="cr-caixa">' +
          '<div class="cr-faixa">' +
            '<div class="cr-nav"><button type="button" data-ir="-1" aria-label="Anterior">◀</button>' +
              '<span id="cr-pos"></span><button type="button" data-ir="1" aria-label="Próximo">▶</button></div>' +
            '<div class="cr-quem" id="cr-quem"></div>' +
            '<div class="cr-acoes">' +
              '<button class="cr-acao" type="button" id="cr-importar">Importar tudo</button>' +
              '<button class="cr-acao" type="button" id="cr-pular">Pular</button>' +
              '<button class="cr-aprovar" type="button" id="cr-aprovar">Aprovar: fica disponível para a Nay</button>' +
              '<button class="cr-fechar" type="button" id="cr-fechar" aria-label="Fechar">✕</button>' +
            "</div>" +
            '<div class="cr-recado" id="cr-recado" role="status"></div>' +
          "</div>" +
          '<div class="cr-corpo" id="cr-corpo-popup"></div>' +
        "</div>";
      document.body.appendChild(veu);
      veu.addEventListener("click", function (e) {
        var ir = e.target.closest("[data-ir]");
        if (ir) return mover(Number(ir.getAttribute("data-ir")));
        if (e.target.id === "cr-pular") return mover(1);
        if (e.target.id === "cr-fechar") return fechar();
        if (e.target.id === "cr-aprovar") return aprovar();
        if (e.target.id === "cr-importar") return importar();
        if (e.target.id === "cr-criar") return criarDaFicha();
      });
      document.addEventListener("keydown", function (e) { if (veu && !veu.hidden && e.key === "Escape") fechar(); });
    }
    veu.hidden = false;
    document.body.style.overflow = "hidden";
    mostrar();
  }

  function fechar() {
    if (!veu) return;
    veu.hidden = true;
    document.body.style.overflow = "";
    $("cr-corpo-popup").innerHTML = "";
    carregar();                      // a lista volta com o que mudou
  }

  function mover(passo) {
    if (ocupado) return;
    var p = pos + passo;
    if (p < 0 || p >= fila.length) {
      if (p >= fila.length) recado("Fim da fila. " + Object.keys(feitos).length + " aprovado(s) nesta rodada.", "ok");
      return;
    }
    pos = p;
    mostrar();
  }

  function recado(texto, tipo) {
    var r = $("cr-recado");
    r.className = "cr-recado" + (tipo ? " cr-recado--" + tipo : "");
    r.textContent = texto || "";
  }

  function mostrar() {
    var it = fila[pos];
    recado("");
    $("cr-pos").textContent = (pos + 1) + " de " + fila.length;
    veu.querySelector('[data-ir="-1"]').disabled = pos === 0;
    veu.querySelector('[data-ir="1"]').disabled = pos >= fila.length - 1;
    var pct = it.pct == null ? null : Number(it.pct);
    $("cr-quem").innerHTML =
      '<span class="cr-fonte">' + esc(rotuloDaFonte(fonteDe(it))) + "</span>" +
      "<b>" + esc(it.titulo) + "</b>" + (it.codigo ? " · #" + it.codigo : "") +
      (pct == null ? "" : ' · <b style="color:' + cor(pct) + '">' + pct + "%</b>") +
      '<span class="cr-sub">' + esc([it.status, it.tipo, it.bairro, it.dono && "dono: " + it.dono].filter(Boolean).join(" · ")) +
        " — " + esc(it.motivos.join(" · ")) + "</span>" +
      (it.falta && it.falta.length ? '<span class="cr-sub cr-falta">Falta: ' + esc(it.falta.join(", ")) + "</span>" : "");
    $("cr-importar").hidden = !it.codigo;
    $("cr-aprovar").disabled = !it.codigo || !!feitos[chave(it)];
    $("cr-aprovar").textContent = feitos[chave(it)] ? "Aprovado ✓"
      : it.status === "Disponível" ? "Salvar e próximo" : "Aprovar: fica disponível para a Nay";
    var corpo = $("cr-corpo-popup");
    if (it.codigo) {
      corpo.innerHTML = '<iframe title="Editor do imóvel ' + esc(it.codigo) + '" src="imovel-editar.html?codigo=' +
        encodeURIComponent(it.codigo) + '&rapido=1"></iframe>';
      var f = corpo.querySelector("iframe");
      f.addEventListener("load", function () { semMenu(f); });
    } else {
      corpo.innerHTML = fichaHtml(it);
    }
  }

  /* o editor dentro do popup, sem o menu do site (no CRM o tema já esconde) */
  function semMenu(f) {
    try {
      var d = f.contentDocument;
      if (!d || d.getElementById("cr-sem-menu")) return;
      var s = d.createElement("style");
      s.id = "cr-sem-menu";
      s.textContent = ".barra-topo,.nav-principal,.rodape-sistema,.pular-conteudo,.nv__voltar,[data-layout-topo],[data-layout-rodape]{display:none!important}" +
        "body::before{display:none!important}";
      d.head.appendChild(s);
    } catch (e) { /* outra origem: fica como está */ }
  }

  var ROTULO_DA_FICHA = { tipo: "Tipo", bairro: "Bairro", condominio: "Condomínio", quartos: "Quartos", suites: "Suítes",
    banheiros: "Banheiros", vagas: "Vagas", area: "Área", valor: "Valor", negocio: "Negócio", mobilia: "Mobília",
    condominio_valor: "Taxa de condomínio", iptu: "IPTU", incluso: "Incluso", detalhes: "Detalhes", fotos: "Fotos" };
  function fichaHtml(it) {
    var d = it.dados || {};
    var linhas = Object.keys(d).filter(function (k) {
      return k.charAt(0) !== "_" && d[k] != null && String(d[k]).trim() !== "";
    }).map(function (k) {
      return "<dt>" + esc(ROTULO_DA_FICHA[k] || k) + "</dt><dd>" + esc(String(d[k]).slice(0, 300)) + "</dd>";
    }).join("");
    return '<div class="cr-ficha">' +
      "<h3>O que o dono contou na conversa</h3>" +
      '<p class="cr-nota">Este imóvel ainda não existe no cadastro' + (it.dono ? " (dono: " + esc(it.dono) + ")" : "") +
      ". Criar faz o pré-cadastro com o que está aqui, ligado ao dono e com as fotos que ele mandou; em seguida o editor abre para completar e aprovar.</p>" +
      (linhas ? "<dl>" + linhas + "</dl>" : '<p class="cr-nota">A ficha ainda está vazia.</p>') +
      '<button class="cr-aprovar" type="button" id="cr-criar">Criar o imóvel com esta ficha</button>' +
      "</div>";
  }

  function json(r) {
    return r.json().catch(function () { return {}; }).then(function (d) {
      if (!r.ok) throw new Error((d.detalhes && [].concat(d.detalhes).join("; ")) || d.detalhe || d.erro || ("HTTP " + r.status));
      return d;
    });
  }

  function criarDaFicha() {
    var it = fila[pos];
    if (ocupado || !it || it.codigo) return;
    ocupado = true;
    var b = $("cr-criar"); if (b) { b.disabled = true; b.textContent = "Criando…"; }
    fetch("/admin/api/imoveis/da-ficha/" + encodeURIComponent(it.fichaId), { method: "POST", credentials: "same-origin" })
      .then(json)
      .then(function (d) {
        it.codigo = d.codigo; it.status = "Rascunho"; it.fonte = "imovel";
        ocupado = false;
        mostrar();
        recado("Pré-cadastro #" + d.codigo + " criado" + (d.fotos ? " com " + d.fotos + " foto(s)" : "") + ". Complete o que falta e aprove.", "ok");
      })
      .catch(function (e) {
        ocupado = false;
        if (b) { b.disabled = false; b.textContent = "Criar o imóvel com esta ficha"; }
        recado("Não criei: " + e.message, "erro");
      });
  }

  function importar() {
    var it = fila[pos];
    if (ocupado || !it || !it.codigo) return;
    ocupado = true;
    recado("Importando o que já sabemos (só em campo vazio)…");
    fetch("/admin/api/imoveis/" + it.codigo + "/importar", { method: "POST", credentials: "same-origin" })
      .then(json)
      .then(function (d) {
        ocupado = false;
        var partes = [];
        if (d.fotosImportadas) partes.push(d.fotosImportadas + " foto(s) trazida(s)");
        if ((d.entraram || []).length) partes.push("entrou: " + d.entraram.join(", "));
        if (d.pct_antes !== d.pct_depois) { partes.push(d.pct_antes + "% → " + d.pct_depois + "%"); it.pct = d.pct_depois; }
        mostrar();
        recado(partes.length ? partes.join(" · ") : "Não havia nada para puxar: o resto é digitar no editor.", "ok");
      })
      .catch(function (e) { ocupado = false; recado("Não importei: " + e.message, "erro"); });
  }

  /* Aprovar: primeiro o que estiver digitado no editor, depois a situação */
  function salvarOEditor() {
    var f = $("cr-corpo-popup").querySelector("iframe");
    var d = null;
    try { d = f && f.contentDocument; } catch (e) { d = null; }
    var botao = d && d.getElementById("ed-salvar");
    if (!botao || botao.disabled) return Promise.resolve();
    var status = d.getElementById("ed-status-salvar");
    var antes = status ? status.textContent : "";
    botao.click();
    return new Promise(function (ok, falha) {
      var n = 0;
      var t = setInterval(function () {
        n++;
        var c = status ? status.className : "";
        if (c.indexOf("--ok") >= 0 && status.textContent !== antes) { clearInterval(t); ok(); }
        else if (c.indexOf("--erro") >= 0) { clearInterval(t); falha(new Error(status.textContent)); }
        else if (n > 60) { clearInterval(t); falha(new Error("o editor não respondeu ao salvar")); }
      }, 250);
    });
  }

  function aprovar() {
    var it = fila[pos];
    if (ocupado || !it || !it.codigo) return;
    var semFoto = it.motivos.some(function (m) { return /sem nenhuma foto/.test(m); }) ||
      (it.falta || []).some(function (x) { return /foto/i.test(x); });
    ocupado = true;
    $("cr-aprovar").disabled = true;
    recado("Salvando…");
    salvarOEditor()
      .then(function () {
        if (it.status === "Disponível") return { jaEstava: true };
        return fetch("/admin/api/imoveis/" + encodeURIComponent(it.codigo), {
          method: "PUT", credentials: "same-origin", headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ status: "Disponível" })
        }).then(json);
      })
      .then(function (d) {
        ocupado = false;
        feitos[chave(it)] = true;
        it.status = "Disponível";
        var texto = d && d.jaEstava ? "#" + it.codigo + " salvo." : "#" + it.codigo + " aprovado: Disponível, no site e na Nay" +
          (semFoto ? " (ainda sem foto: a Nay manda só o card)" : "") + ".";
        if (pos < fila.length - 1) { mover(1); recado(texto + " Próximo:", "ok"); }
        else { mostrar(); recado(texto + " Fim da fila.", "ok"); }
      })
      .catch(function (e) {
        ocupado = false;
        $("cr-aprovar").disabled = false;
        recado("Não aprovei: " + e.message, "erro");
      });
  }

  /* ---- a OLX: o favorito traz o anúncio para esta página -------------------- */
  // o mesmo leitor do anúncio da aba Captação OLX (captacao-olx.js), com o destino nesta página
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
  var fav = $("cr-fav");
  fav.href = "javascript:" + encodeURIComponent("(" + botaoDaOlx.toString() + ")(" +
    JSON.stringify(location.origin + location.pathname) + ")");
  fav.addEventListener("click", function (e) {
    e.preventDefault();
    $("cr-olx-recado").innerHTML = "Esse botão não funciona aqui: <strong>arraste</strong> ele para a barra de favoritos e use na página do anúncio da OLX.";
  });
  $("cr-olx-form").addEventListener("submit", function (e) {
    e.preventDefault();
    var link = $("cr-olx-link").value.trim();
    if (!/^https?:\/\/([a-z0-9-]+\.)*olx\.com\.br\//i.test(link)) {
      $("cr-olx-recado").textContent = "Esse link não é de um anúncio da OLX.";
      return;
    }
    link = link.replace(/^http:/i, "https:").replace(/^https:\/\/www\.olx\.com\.br\//i, "https://am.olx.com.br/");
    window.open(link, "_blank", "noopener");
    $("cr-olx-recado").innerHTML = "Abri o anúncio numa aba nova. Lá, clique em <strong>Enviar para Imob Easy</strong> na barra de favoritos.";
  });

  function enviarJson(url, metodo, corpo) {
    return fetch(url, { method: metodo, credentials: "same-origin", headers: { "Content-Type": "application/json" },
                        body: JSON.stringify(corpo) }).then(json);
  }

  function importarDaOlx(pacote) {
    aba.click();
    var r = $("cr-olx-recado");
    r.textContent = "Lendo o anúncio da OLX…";
    enviarJson("/admin/api/imoveis/olx/importar", "POST", pacote).then(function (d) {
      var fotos = d.fotos || [];
      var ok = 0, k = 0;
      var cadeia = Promise.resolve();
      fotos.forEach(function (url, i) {
        cadeia = cadeia.then(function () {
          k = i + 1;
          r.textContent = "Pré-cadastro #" + d.codigo + (d.novo ? " criado" : " (já existia)") + ". Baixando foto " + k + " de " + fotos.length + "…";
          return enviarJson("/admin/api/imoveis/olx/" + d.codigo + "/foto", "POST", { url: url, ordem: i + 1 })
            .then(function (x) { if (x.ok) ok++; }).catch(function () {});
        });
      });
      return cadeia.then(function () {
        r.textContent = "Da OLX: pré-cadastro #" + d.codigo + " com " + (ok + (d.fotos_ja || 0)) + " foto(s). Abrindo no cadastro rápido…";
        return carregar(function () {
          var lista = visiveis();
          var i = lista.findIndex(function (x) { return String(x.codigo) === String(d.codigo); });
          if (i < 0) { lista = [{ codigo: d.codigo, titulo: d.titulo || "Anúncio da OLX", origem: "olx", status: "Rascunho",
                                   fonte: "imovel", motivos: ["pré-cadastro (Rascunho)"], falta: [] }].concat(lista); i = 0; }
          abrir(lista, i);
        });
      });
    }).catch(function (e) { r.textContent = "Não importei da OLX: " + e.message; });
  }

  // chegou pelo favorito: #olx=... (a aba abre sozinha)
  var h = location.hash;
  if (h.indexOf("#olx=") === 0) {
    var pacote = null;
    try { pacote = JSON.parse(decodeURIComponent(h.slice(5))); } catch (e) { pacote = null; }
    history.replaceState(null, "", location.pathname + location.search);
    if (pacote) setTimeout(function () { importarDaOlx(pacote); }, 300);
  } else if (h === "#rapido") {
    setTimeout(function () { aba.click(); }, 300);
  }
})();
