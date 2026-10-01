/* ==========================================================================
   Imob Easy — Novo imóvel: o progresso do cadastro (Pedro, 01/10/2026)

   O que este arquivo faz: o menu lateral das seções, a fita de completude na
   faixa de cima, a porcentagem, o ✓ do campo preenchido, o resumo em emoji e
   o botão de cadastrar sempre à vista.

   O que ele NÃO faz: gravar. Quem grava, quem acha o condomínio, quem cuida
   do proprietário e quem avisa "falta o dono" é o imovel-editar.js -- aqui só
   se LÊ o formulário que ele desenhou. O botão da faixa de cima é um atalho
   que clica no botão de verdade, então o caminho do salvar é um só.

   Por isso ele não conhece a lista de campos: descobre tudo pelo que está na
   tela (os cartões, os `data-envolve`). Campo novo no imovel-editar.js aparece
   aqui sozinho, com peso 1.

   O PESO (3 o que a Nay precisa para oferecer, 2 o que o corretor pergunta,
   1 o complemento) é o único juízo daqui -- e é o mesmo do desenho aprovado.
   ========================================================================== */
(function () {
  "use strict";

  var topo = document.querySelector(".nv__topo");
  var cartoes = document.getElementById("ed-cartoes");
  var lado = document.getElementById("nv-lado");
  var fita = document.getElementById("nv-fita");
  var pct = document.getElementById("nv-pct");
  var cta = document.getElementById("nv-cta");
  if (!cartoes || !lado || !fita || !pct) return;

  var PESO = {
    condominio: 2, logradouro: 2, numero: 1, complemento: 1, bairro: 3, cidade: 1, estado: 1, cep: 1, andar: 1,
    "p:torre": 1, "p:bloco": 1, "p:unidade": 2, "p:casa": 1, "p:lote": 1,
    "o:nome": 2, "o:tratamento": 1, "o:telefone": 3, "o:email": 1, "o:documento": 1,
    tipo: 3, quartos: 3, suites: 2, banheiros: 2, "x:salas": 1, vagas: 2, vagas_cobertas: 1, mobilia: 2, sol: 1,
    area_util: 3, area_total: 1, "x:area construida": 1, "x:tamanho do terreno": 1,
    "x:frente": 1, "x:fundo": 1, "x:pe direito": 1,
    "x:andares": 1, "x:elevadores": 1, "x:lances de escada": 1, "x:tipo de cobertura": 1,
    caracteristicas: 2,
    valor_aluguel: 3, valor_venda: 3, taxa_condominio: 2, iptu: 2,
    "x:aceita financiamento": 1, "x:permuta": 1, "x:incluso no aluguel": 1, "x:garantia de aluguel": 2,
    descricao: 2,
    captado_por: 1, captado_em: 1, "x:indicado por": 1, "x:inspecionado por": 1,
    "p:locatario_nome": 1, "p:locatario_contato": 1, "p:vencimento": 1, "p:observacao_aluguel": 1,
    "p:observacoes": 1
  };
  /* aluguel e venda contam como UM: quem só vende não fica devendo o aluguel */
  var JUNTOS = { valor_aluguel: "preco", valor_venda: "preco" };

  var EMOJI = [
    [/ar.?condicionado|split|climatiz/, "❄️"], [/piscina/, "🏊"], [/academia|fitness|muscula/, "🏋️"],
    [/churrasq|gourmet/, "🍖"], [/varanda|sacada/, "🌇"], [/elevador/, "🛗"],
    [/portaria|porteiro|seguran|vigil/, "🛡️"], [/c[aâ]mera|cftv|monitorad/, "📹"],
    [/playground|parquinho/, "🛝"], [/brinquedoteca|kids/, "🧸"], [/\bpet\b/, "🐾"],
    [/sal[aã]o de festa|festa/, "🎉"], [/quadra|futebol|esporte/, "⚽"], [/sauna/, "🧖"],
    [/garagem|estacionamento/, "🚗"], [/mobiliad|m[oó]vei/, "🛋️"], [/arm[aá]rio|embutid|closet/, "🚪"],
    [/cozinha|planejad/, "🍳"], [/lavanderia|[aá]rea de servi/, "🧺"], [/banheira|hidro|jacuzzi/, "🛁"],
    [/aquecedor|[aá]gua quente/, "🔥"], [/solar/, "☀️"], [/gerador/, "⚡"], [/internet|wi.?fi|fibra/, "📶"],
    [/jardim|quintal|[aá]rea verde|bosque/, "🌳"], [/cowork|escrit[oó]rio/, "💻"], [/vista|panor[aâ]m/, "🏙️"],
    [/acess[ií]bil|rampa|pcd/, "♿"], [/biciclet/, "🚲"], [/cinema/, "🎬"], [/jogos/, "🎮"],
    [/horta|pomar/, "🥬"], [/interfone/, "📞"]
  ];
  function emoji(v) {
    var s = String(v).toLowerCase();
    for (var i = 0; i < EMOJI.length; i++) if (EMOJI[i][0].test(s)) return EMOJI[i][1];
    return "✨";
  }

  /* A ALTURA DA FAIXA, MEDIDA: o rolar para uma seção e a barra de situação
     presa (no editar) se apoiam nela. Chutar um valor fixo faria a barra cobrir
     o título do cartão quando o texto da faixa quebra em duas linhas. */
  function medirTopo() {
    if (!topo) return;
    document.body.style.setProperty("--nv-topo-alt", Math.round(topo.getBoundingClientRect().height) + "px");
  }
  medirTopo();
  window.addEventListener("resize", medirTopo);
  if (window.ResizeObserver && topo) new ResizeObserver(medirTopo).observe(topo);

  function esc(t) {
    return String(t == null ? "" : t)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }
  function tituloDo(cartao) {
    var h = cartao.querySelector(".ed__cartao-titulo");
    if (!h) return "Seção";
    var t = "";
    Array.prototype.forEach.call(h.childNodes, function (n) { if (n.nodeType === 3) t += n.textContent; });
    return t.trim() || "Seção";
  }

  /* ---- o que está preenchido ---------------------------------------------
     Cada campo é um bloco com data-envolve. O que vale como "preenchido"
     depende do tipo de controle -- e a chave de ligar/desligar não vale:
     desligada é uma resposta, não um campo em branco. */
  function preenchido(bloco) {
    var grupos = bloco.querySelector("[data-grupos]");
    if (grupos) return !!grupos.querySelector(".ed__chip");
    var marcar = bloco.querySelector("[data-marcar]");
    if (marcar) return !!marcar.querySelector("input:checked");
    var condo = bloco.querySelector("#ed-condominio");
    if (condo) return String(condo.value || "").trim() !== "";
    var el = bloco.querySelector("[data-campo]");
    if (!el || el.type === "checkbox" || el.type === "hidden") return null;   // null = não conta
    return String(el.value == null ? "" : el.value).trim() !== "";
  }

  function medir(cartao) {
    var total = 0, feito = 0, nCampos = 0, nFeitos = 0, juntosVistos = {};
    Array.prototype.forEach.call(cartao.querySelectorAll("[data-envolve]"), function (bloco) {
      var nome = bloco.getAttribute("data-envolve");
      var ok = preenchido(bloco);
      if (ok === null) return;
      // o ✓ é sempre do próprio campo: quem só vende não ganha ✓ no aluguel
      marcarBloco(bloco, ok);
      var peso = PESO[nome] || 1;
      var par = JUNTOS[nome];
      if (par) {
        if (juntosVistos[par]) return;      // o par já contou por nós dois
        juntosVistos[par] = true;
        var algum = false;
        Array.prototype.forEach.call(cartao.querySelectorAll("[data-envolve]"), function (b) {
          if (JUNTOS[b.getAttribute("data-envolve")] === par && preenchido(b)) algum = true;
        });
        total += peso; nCampos++;
        if (algum) { feito += peso; nFeitos++; }
        return;
      }
      total += peso; nCampos++;
      if (ok) { feito += peso; nFeitos++; }
    });
    return { total: total, feito: feito, nCampos: nCampos, nFeitos: nFeitos };
  }
  function marcarBloco(bloco, ok) { bloco.classList.toggle("ed__campo--cheio", !!ok); }

  /* ---- o resumo em emoji, no menu lateral -------------------------------- */
  function emosDoCartao(cartao, titulo) {
    if (/que tem/i.test(titulo)) {
      var vistos = {}, saida = "";
      Array.prototype.forEach.call(cartao.querySelectorAll(".ed__chip"), function (c) {
        var v = c.getAttribute("data-item") || c.textContent;
        var e = emoji(v);
        if (e !== "✨" && vistos[e]) return;
        vistos[e] = true;
        saida += '<span title="' + esc(v) + '">' + e + "</span>";
      });
      return saida;
    }
    if (/caracter/i.test(titulo)) {
      var nums = [["quartos", "🛏️", "quartos", ""], ["suites", "🛁", "suítes", ""],
        ["banheiros", "🚿", "banheiros", ""], ["vagas", "🚗", "vagas", ""], ["area_util", "📐", "de área útil", "m²"]];
      var c = "";
      nums.forEach(function (n) {
        var el = cartao.querySelector('[data-campo="' + n[0] + '"]');
        var v = el ? String(el.value || "").trim() : "";
        if (!v) return;
        c += '<span title="' + esc(v + " " + n[2]) + '">' + n[1] + "<b>" + esc(v + n[3]) + "</b></span>";
      });
      var mob = cartao.querySelector('[data-campo="mobilia"]');
      var m = mob ? String(mob.value || "").trim() : "";
      if (m && !/^(sem|n[aã]o)/i.test(m)) c += '<span title="Mobília: ' + esc(m) + '">🛋️</span>';
      return c;
    }
    return "";
  }

  /* ---- desenhar o menu e a fita ------------------------------------------ */
  var lista = [];      // os cartões, na ordem da tela
  function montar() {
    lista = Array.prototype.slice.call(cartoes.querySelectorAll(".ed__cartao"));
    lado.innerHTML = "";
    fita.innerHTML = "";
    lista.forEach(function (cartao, i) {
      var titulo = tituloDo(cartao);
      var ico = cartao.querySelector(".ed__icone");
      var cor = (cartao.style.getPropertyValue("--gc") || "#6d28d9").trim();
      var interno = cartao.classList.contains("ed__cartao--privado");
      lado.insertAdjacentHTML("beforeend",
        '<button class="nv__item" type="button" data-ir="' + i + '" style="--c:' + esc(cor) + '">' +
          '<span class="nv__sw" aria-hidden="true">' + esc(ico ? ico.textContent : "•") + "</span>" +
          "<span>" + esc(titulo) + (interno ? '<span class="nv__interno">interno</span>' : "") + "</span>" +
          '<span class="nv__conta"></span>' +
          '<span class="nv__mini"><i></i></span>' +
          '<span class="nv__emos"></span>' +
        "</button>");
      fita.insertAdjacentHTML("beforeend",
        '<button type="button" data-ir="' + i + '" style="--c:' + esc(cor) + '" aria-label="' + esc(titulo) + '"><i></i></button>');
      if (!cartao.querySelector(".nv__badge")) {
        var h = cartao.querySelector(".ed__cartao-titulo");
        if (h) h.insertAdjacentHTML("beforeend", '<span class="nv__badge"></span>');
      }
    });
    espiar();
    atualizar();
    medirTopo();
  }

  function atualizar() {
    var T = 0, G = 0;
    lista.forEach(function (cartao, i) {
      var m = medir(cartao);
      T += m.total; G += m.feito;
      var p = m.total ? m.feito / m.total : 0;
      var cheio = m.nCampos > 0 && m.nFeitos === m.nCampos;
      var item = lado.querySelector('.nv__item[data-ir="' + i + '"]');
      var seg = fita.querySelector('button[data-ir="' + i + '"]');
      if (seg) {
        seg.style.flex = String(m.total || 1);
        seg.querySelector("i").style.width = (p * 100) + "%";
        seg.title = tituloDo(cartao) + ": " + Math.round(p * 100) + "%";
      }
      if (item) {
        item.querySelector(".nv__mini i").style.width = (p * 100) + "%";
        var conta = item.querySelector(".nv__conta");
        conta.textContent = cheio ? "✓" : m.nFeitos + "/" + m.nCampos;
        conta.classList.toggle("nv__conta--cheio", cheio);
        item.querySelector(".nv__emos").innerHTML = emosDoCartao(cartao, tituloDo(cartao));
      }
      var badge = cartao.querySelector(".nv__badge");
      if (badge) {
        badge.textContent = cheio ? "✓ Completo" : m.nFeitos + " de " + m.nCampos;
        badge.classList.toggle("nv__badge--cheio", cheio);
      }
    });
    pct.innerHTML = Math.round(T ? (G / T) * 100 : 0) + "<small>%</small>";
  }

  /* ---- o botão de cima é atalho para o de verdade ------------------------ */
  function botaoReal() { return document.getElementById("ed-salvar"); }
  if (cta) {
    cta.addEventListener("click", function () {
      var b = botaoReal();
      if (b) b.click();
    });
  }
  function espelharBotao() {
    var b = botaoReal();
    if (!cta || !b) return;
    cta.disabled = b.disabled;
    cta.textContent = b.textContent || "Cadastrar imóvel";
  }

  /* ---- em qual seção ele está -------------------------------------------- */
  var olho = null;
  function espiar() {
    if (olho) olho.disconnect();
    if (!window.IntersectionObserver) return;
    olho = new IntersectionObserver(function (ents) {
      ents.forEach(function (en) {
        if (!en.isIntersecting) return;
        var i = lista.indexOf(en.target);
        Array.prototype.forEach.call(lado.querySelectorAll(".nv__item"), function (n) {
          n.classList.toggle("nv__item--aqui", Number(n.getAttribute("data-ir")) === i);
        });
        var aqui = lado.querySelector(".nv__item--aqui");
        if (aqui && window.innerWidth <= 960) aqui.scrollIntoView({ inline: "center", block: "nearest" });
      });
    }, { rootMargin: "-45% 0px -50% 0px" });
    lista.forEach(function (c) { olho.observe(c); });
  }

  /* ---- quando redesenhar ------------------------------------------------- */
  var pedido = null;
  function agendar() {
    if (pedido) return;
    pedido = requestAnimationFrame(function () { pedido = null; atualizar(); espelharBotao(); });
  }
  document.addEventListener("input", agendar, true);
  document.addEventListener("change", agendar, true);
  document.addEventListener("click", agendar, true);     // tirar/passar etiqueta, marcar pastilha

  // o motor desenha os cartões depois de ler o servidor, e redesenha o do dono
  new MutationObserver(function () { montar(); espelharBotao(); }).observe(cartoes, { childList: true });
  var estado = document.getElementById("ed-estado");
  if (estado) new MutationObserver(espelharBotao).observe(estado, { childList: true, subtree: true, attributes: true });

  lado.addEventListener("click", irPara);
  fita.addEventListener("click", irPara);
  function irPara(e) {
    var b = e.target.closest ? e.target.closest("[data-ir]") : null;
    if (!b) return;
    var cartao = lista[Number(b.getAttribute("data-ir"))];
    if (cartao) cartao.scrollIntoView({ block: "start" });
  }

  if (cartoes.children.length) montar();
})();
