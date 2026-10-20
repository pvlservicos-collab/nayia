/* ==========================================================================
   Imob Easy — a página pública do imóvel (imobeasy.online/imovel/<código>-<nome>)

   O desenho é o do arquivo Novateladeverimovel.html (Pedro, 02/10/2026): a
   marcação e o CSS estão em imovel.html, iguais ao desenho. Aqui só entra o
   que no desenho era exemplo:
     - os dados vêm de GET /api/imovel-publico/<código> (sem senha; a função
       do banco não devolve rua, número, CEP nem andar);
     - "Me envia o imóvel" e "Enviar lista" chamam POST /api/me-envia, que
       manda o card e as fotos pela Nay para o WhatsApp digitado;
     - o mapa é de verdade (Leaflet) e mostra a REGIÃO, não a porta.
   ========================================================================== */
(function () {
  "use strict";

  var API = window.API_BASE || "https://api.imobeasy.online";
  var $ = function (s) { return document.querySelector(s); };
  var has = function (v) { return v !== undefined && v !== null && String(v).trim() !== ""; };
  var esc = function (s) { return String(s).replace(/[&<>"]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]; }); };
  var i = function (n) { return '<i data-lucide="' + n + '"></i>'; };
  var drawIcons = function () { try { window.lucide && lucide.createIcons(); } catch (e) { /* sem ícone, a página segue */ } };
  var reais = function (v) { return Number(v).toLocaleString("pt-BR", { maximumFractionDigits: 0 }); };
  var numero = function (v) { var n = Number(v); return isFinite(n) ? n.toLocaleString("pt-BR", { maximumFractionDigits: 2 }) : String(v); };
  var lista = function (v) { return has(v) ? String(v).split(/\s*[,;]\s*/).filter(has) : []; };

  /* o código vem do endereço: /imovel/5717-apartamento-..., /imovel/5717 ou ?codigo=5717 */
  function codigoDoEndereco() {
    var m = /\/imovel\/(\d{1,6})/.exec(location.pathname) || /[?&]codigo=(\d{1,6})/.exec(location.search);
    return m ? m[1] : null;
  }

  var CAMPOS = {
    imovel: [["tipo", "Tipo"], ["quartos", "Quartos"], ["suites", "Suítes"], ["banheiros", "Banheiros"], ["salas", "Salas"], ["vagas", "Vagas"], ["vagascob", "Vagas cobertas"], ["mobilia", "Mobília"], ["face", "Face solar"]],
    medidas: [["areautil", "Área útil", "m²"], ["areatotal", "Área total", "m²"], ["areacons", "Área construída", "m²"], ["terreno", "Terreno", "m²"], ["frente", "Frente", "m"], ["fundo", "Fundo", "m"], ["pedireito", "Pé-direito", "m"]],
    predio: [["andares", "Andares"], ["elevadores", "Elevadores"], ["escadas", "Lances de escada"], ["cobertura", "Cobertura"]]
  };
  var ICONE = [[/ar.?condicionado|split|climatiz/, "snowflake"], [/piscina/, "waves"], [/academia|fitness/, "dumbbell"], [/churrasq|gourmet/, "flame"], [/varanda|sacada/, "sunset"], [/elevador/, "arrow-up-down"], [/portaria|porteiro/, "concierge-bell"], [/seguran|vigil/, "shield-check"], [/c[aâ]mera|cftv/, "cctv"], [/playground|brinquedo/, "baby"], [/\bpet\b/, "paw-print"], [/festa/, "party-popper"], [/quadra/, "trophy"], [/sauna/, "thermometer"], [/garagem/, "car"], [/mobiliad/, "sofa"], [/arm[aá]rio|closet/, "door-closed"], [/cozinha/, "cooking-pot"], [/lavanderia|[aá]rea de servi/, "washing-machine"], [/banheira|hidro/, "bath"], [/solar/, "sun"], [/gerador/, "zap"], [/internet|wi.?fi/, "wifi"], [/jardim|quintal|verde/, "trees"], [/fechado/, "lock"], [/vista/, "mountain"]];
  var ico = function (v) { var s = v.toLowerCase(); var m = ICONE.find(function (p) { return p[0].test(s); }); return m ? m[1] : "check"; };
  // os 4 níveis (344): o que o cadastro grava e as redações antigas
  var MOBILIA = { mobiliado: "Mobiliado", semi: "Com modulados e ar", "semi-mobiliado": "Com modulados e ar", nao: "Sem mobília",
                  "com modulados e ar": "Com modulados e ar", "só climatizado": "Só climatizado", "sem nada": "Sem mobília" };

  var I = null, L = null, C = null, V = null, FOTOS = [], cur = 0;

  /* ---------- sem foto cadastrada: um quadro neutro, sem inventar imagem ---------- */
  var SEM_FOTO = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 500"><rect width="800" height="500" fill="#EDE6F7"/>' +
    '<text x="400" y="260" text-anchor="middle" font-family="Arial,sans-serif" font-size="26" fill="#7A7290">Imóvel sem foto cadastrada</text></svg>');

  function showPhoto(n) {
    cur = (n + FOTOS.length) % FOTOS.length;
    $("#mainImg").src = FOTOS[cur].src; $("#mainImg").alt = FOTOS[cur].alt;
    $("#count").textContent = (cur + 1) + " / " + FOTOS.length;
    document.querySelectorAll(".thumbs button").forEach(function (b, k) {
      b.classList.toggle("on", k === cur);
      // com a foto grande aberta, a faixa acompanha (fechada, não mexe na rolagem da página)
      if (k === cur && !$("#lbx").hidden) b.scrollIntoView({ inline: "nearest", block: "nearest" });
    });
  }

  /* 16/10: a faixa de fotos do site antigo; tocar numa foto abre a foto grande */
  function abrirFoto(n) { showPhoto(n); $("#lbx").hidden = false; document.body.style.overflow = "hidden"; $("#lbClose").focus(); }
  function fecharFoto() { $("#lbx").hidden = true; document.body.style.overflow = ""; }
  function rolarFaixa(dir) {
    var f = $("#thumbs"), b = f.querySelector("button");
    f.scrollBy({ left: dir * (b ? b.getBoundingClientRect().width + 3 : f.clientWidth / 2), behavior: "smooth" });
  }

  function kvList(campos, src) {
    var itens = campos.filter(function (c) { return has(src[c[0]]); }).map(function (c) {
      var v = src[c[0]];
      if (c[2]) v = numero(v) + " " + c[2];
      return "<div><small>" + c[1] + "</small><b>" + esc(v) + "</b></div>";
    }).join("");
    return itens ? '<div class="kv">' + itens + "</div>" : "";
  }

  function render() {
    var pl1 = function (v, um, varios) { return String(v) === "1" ? um : varios; };
    var specs = [["ruler", has(C.areautil) ? numero(C.areautil) : "", "m²"], ["bed-double", C.quartos, pl1(C.quartos, "quarto", "quartos")],
      ["bath", C.suites, pl1(C.suites, "suíte", "suítes")], ["shower-head", C.banheiros, pl1(C.banheiros, "banheiro", "banheiros")],
      ["car", C.vagas, pl1(C.vagas, "vaga", "vagas")]].filter(function (s) { return has(s[1]) && String(s[1]) !== "0"; });
    var negocio = has(V.aluguel) && has(V.venda) ? "Aluguel e venda" : has(V.aluguel) ? "Aluguel" : "Venda";
    $("#fic").innerHTML =
      '<div class="fic-top">' + (has(C.tipo) ? '<span class="tag-t">' + esc(C.tipo) + "</span>" : "") +
      '<span class="tag-t">' + negocio + '</span><span class="code">' + i("hash") + "Código " + esc(I.codigo) + "</span></div>" +
      "<h1>" + esc(I.titulo) + "</h1>" +
      (has(L.condominio) ? '<p class="condo">Condomínio: <b>' + esc(L.condominio) + "</b></p>" : "") +
      '<div class="loc">' + i("map-pin") + esc([L.bairro, [L.cidade, L.estado].filter(has).join(" - ")].filter(has).join(" · ")) + "</div>" +
      '<div class="specs">' + specs.map(function (s) { return '<div class="spec">' + i(s[0]) + "<b>" + esc(s[1]) + "</b>" + s[2] + "</div>"; }).join("") + "</div>";

    $("#thumbs").innerHTML = FOTOS.map(function (f, k) {
      return '<button aria-label="Ver foto ' + (k + 1) + '" data-ph="' + k + '"><img src="' + esc(f.src) + '" alt="" loading="lazy"></button>';
    }).join("");
    showPhoto(0);

    var ch = has(I.desc) ? '<p class="sub-t">Descrição</p><p class="desc">' + esc(I.desc) + "</p>" : "";
    [["O imóvel", CAMPOS.imovel], ["Medidas", CAMPOS.medidas], ["Prédio", CAMPOS.predio]].forEach(function (g) {
      var k = kvList(g[1], C); if (k) ch += '<p class="sub-t">' + g[0] + "</p>" + k;
    });
    $("#caracB").innerHTML = ch || '<p class="none">Nada cadastrado.</p>';

    var pills = function (a, icone) {
      return a.length ? '<div class="pills">' + a.map(function (v) { return '<span class="pill">' + i(icone ? icone(v) : "check") + esc(v) + "</span>"; }).join("") + "</div>" : null;
    };
    $("#oqtB").innerHTML =
      '<div><p class="sub-t">Características do imóvel</p>' + (pills(I.tagsimovel || [], ico) || '<p class="none">Nada cadastrado.</p>') + "</div>" +
      '<div><p class="sub-t">Características do condomínio</p>' + (pills(I.tagscondo || [], ico) || '<p class="none">Nada cadastrado.</p>') + "</div>";

    var dinheiro = [["aluguel", "Aluguel"], ["venda", "Venda"], ["condo", "Condomínio"], ["iptu", "IPTU"]].filter(function (c) { return has(V[c[0]]); })
      .map(function (c) { return "<div><small>" + c[1] + "</small><b>R$ " + reais(V[c[0]]) + "</b></div>"; }).join("") +
      "<div><small>Honorários</small><b>50/50</b></div>";
    var neg = [["fin", "Aceita financiamento"], ["permuta", "Permuta"]].filter(function (c) { return has(V[c[0]]); })
      .map(function (c) { return "<div><small>" + c[1] + "</small><b>" + esc(V[c[0]]) + "</b></div>"; }).join("");
    // 448: o que a taxa de condomínio inclui vem da ficha do condomínio (vale para todos os imóveis dele)
    var inclusoTaxa = I.condo && Array.isArray(I.condo.taxa_inclui) ? pills(I.condo.taxa_inclui) : null;
    $("#valB").innerHTML = '<div class="kv">' + dinheiro + neg + "</div>" +
      (inclusoTaxa ? '<div style="margin-top:14px"><p class="sub-t">Incluso na taxa de condomínio</p>' + inclusoTaxa + "</div>" : "") +
      '<div class="two" style="margin-top:14px"><div><p class="sub-t">Incluso no aluguel</p>' + (pills(lista(I.incluso)) || '<p class="none">Não informado</p>') + "</div>" +
      '<div><p class="sub-t">Garantia de aluguel</p>' + (pills(lista(I.garantia)) || '<p class="none">Não informado</p>') + "</div></div>";

    renderPrice(); renderLocal(); renderNav(); drawIcons();
  }

  function renderPrice() {
    var aluga = has(V.aluguel), principal = aluga ? V.aluguel : V.venda;
    if (!has(principal)) {
      var consulte = "<small>Valor</small><div class=\"big\">Consulte</div>";
      $("#priceCard").innerHTML = consulte; $("#priceMobile").innerHTML = consulte; return;
    }
    var na = '<span class="na">não informado</span>';
    var linhas = "<div><span>" + (aluga ? "Aluguel" : "Venda") + "</span><b>R$ " + reais(principal) + "</b></div>";
    if (aluga && has(V.venda)) linhas += "<div><span>Venda</span><b>R$ " + reais(V.venda) + "</b></div>";
    linhas += "<div><span>Condomínio</span>" + (has(V.condo) ? "<b>R$ " + reais(V.condo) + "</b>" : na) + "</div>";
    linhas += "<div><span>IPTU</span>" + (has(V.iptu) ? "<b>R$ " + reais(V.iptu) + "</b>" : na) + "</div>";
    if (aluga && has(V.condo)) linhas += '<div class="tot"><span>Aluguel + condomínio</span><b>R$ ' + reais(Number(V.aluguel) + Number(V.condo)) + "</b></div>";
    var html = "<small>" + (aluga ? "Aluguel" : "Venda") + '</small><div class="big">R$ ' + reais(principal) + (aluga ? "<span>/mês</span>" : "") + '</div><div class="rows">' + linhas + "</div>";
    $("#priceCard").innerHTML = html; $("#priceMobile").innerHTML = html;
  }

  (function () {
    var b = document.getElementById("voltar"); if (!b) return;
    b.addEventListener("click", function () {
      var veioDaqui = false;
      try { veioDaqui = !!document.referrer && new URL(document.referrer).origin === location.origin; } catch (e) { /* idem */ }
      if (veioDaqui && history.length > 1) history.back(); else location.href = "/imoveis";
    });
  })();

  /* A página é aberta: mostra a REGIÃO (condomínio, bairro, cidade), nunca a rua nem o número. */
  function renderLocal() {
    var campos = [["condominio", "Condomínio"], ["bairro", "Bairro"], ["cidade", "Cidade"]];
    var temMapa = I.geo && has(I.geo.lat) && has(I.geo.lon);
    $("#locB").innerHTML =
      (temMapa ? '<div class="map mapa--escuro" id="mapa"><span class="maptag" style="z-index:500">' + i("map-pin") + "Região aproximada</span></div>" : "") +
      '<div class="addr"><b>' + esc(L.condominio || L.bairro || "") + "</b><small>" +
      esc([L.bairro, [L.cidade, L.estado].filter(has).join(" - ")].filter(has).join(", ")) + "</small></div>" + kvList(campos, L);
    if (temMapa) carregarMapa(Number(I.geo.lat), Number(I.geo.lon));
  }

  function carregarMapa(lat, lon) {
    var css = document.createElement("link");
    css.rel = "stylesheet"; css.href = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.css";
    document.head.appendChild(css);
    var js = document.createElement("script");
    js.src = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.js";
    js.onload = function () {
      try {
        /* O MESMO MAPA DO /imoveis (Pedro, 06/10): escuro, com as divisas e os nomes dos bairros e o pino roxo
           com o preço. No computador a rodinha dá zoom; no celular, a pinça. O ponto é o mesmo de lá (arredondado). */
        var LL = window.L, toque = window.matchMedia("(pointer:coarse)").matches;
        var mapa = LL.map("mapa", { scrollWheelZoom: !toque, attributionControl: true, zoomControl: false, minZoom: 10 }).setView([lat, lon], 14);
        mapa.attributionControl.setPrefix(false);
        LL.control.zoom({ position: "bottomright" }).addTo(mapa);
        LL.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", { maxZoom: 19, subdomains: "abc", attribution: "&copy; OpenStreetMap" }).addTo(mapa);
        var valor = Number(has(V.aluguel) ? V.aluguel : V.venda) || 0;
        var curto = !valor ? "Imóvel" : valor >= 1e6 ? (valor / 1e6).toLocaleString("pt-BR", { maximumFractionDigits: 2 }) + " mi"
          : valor >= 1e4 ? Math.round(valor / 1e3).toLocaleString("pt-BR") + " mil"
          : (valor / 1e3).toLocaleString("pt-BR", { maximumFractionDigits: 1 }) + " mil";
        LL.marker([lat, lon], { keyboard: false, interactive: false, zIndexOffset: 900,
          icon: LL.divIcon({ className: "pinw", iconSize: null, html: '<span class="ux-preco-pin">' + esc(curto) + "</span>" }) }).addTo(mapa);
        mapa.createPane("rotulosBairro"); mapa.getPane("rotulosBairro").style.zIndex = 450; mapa.getPane("rotulosBairro").style.pointerEvents = "none";
        fetch(API + "/api/mapa/bairros").then(function (r) { return r.ok ? r.json() : []; }).then(function (bs) {
          bs.forEach(function (b) {
            if (b.poligono) LL.geoJSON(b.poligono, { interactive: false, style: { color: "#c4b5fd", weight: 1.2, opacity: .6, fillColor: "#c4b5fd", fillOpacity: .04 } }).addTo(mapa);
            LL.tooltip({ permanent: true, direction: "center", className: "ux-rotulo-bairro", interactive: false, pane: "rotulosBairro" })
              .setLatLng([b.lat, b.lon]).setContent(esc(b.bairro)).addTo(mapa);
          });
        }).catch(function () { /* sem as divisas o mapa continua servindo */ });
      } catch (e) { var m = $("#mapa"); if (m) m.remove(); }
    };
    js.onerror = function () { var m = $("#mapa"); if (m) m.remove(); };
    document.head.appendChild(js);
  }

  var NAV = [["s-fotos", "Fotos", "images"], ["s-carac", "Características", "layout-list"], ["s-oquetem", "O que tem", "sparkles"], ["s-valores", "Valores", "banknote"], ["s-local", "Localização", "map-pin"]];
  function renderNav() {
    $("#nav").innerHTML = NAV.map(function (n, k) {
      return '<button data-go="' + n[0] + '" aria-label="' + (k + 1) + ". " + n[1] + '"><span class="n">' + (k + 1) + "</span>" + i(n[2]) + "<span>" + n[1] + "</span></button>";
    }).join("");
  }

  /* ===== lista de envio: fica salva no navegador e acompanha a navegação ===== */
  var KEY = "imobeasy_lista_envio", lista_envio;
  try { lista_envio = JSON.parse(localStorage.getItem(KEY) || "null"); } catch (e) { lista_envio = null; }
  if (!Array.isArray(lista_envio)) lista_envio = [];
  var save = function () { try { localStorage.setItem(KEY, JSON.stringify(lista_envio)); } catch (e) { /* navegador sem armazenamento */ } };
  var inList = function () { return !!I && lista_envio.some(function (x) { return String(x.codigo) === String(I.codigo); }); };
  function renderList(novo) {
    var n = lista_envio.length;
    $("#badge").textContent = n;
    $("#dockSub").textContent = n + " " + (n === 1 ? "imóvel selecionado" : "imóveis selecionados");
    $("#sendListBtn").innerHTML = i("send") + (n ? "Enviar " + (n === 1 ? "o imóvel" : "os " + n + " imóveis") : "Enviar lista");
    $("#items").innerHTML = n ? lista_envio.map(function (x) {
      return '<div class="item' + (String(x.codigo) === String(novo) ? " new" : "") + '"><img src="' + esc(x.foto || SEM_FOTO) + '" alt=""><div><b>' + esc(x.titulo) +
        "</b><small>" + esc(x.sub) + '</small></div><button data-rm="' + esc(x.codigo) + '" aria-label="Tirar da lista">' + i("trash-2") + "</button></div>";
    }).join("") : '<div class="empty">Sua lista está vazia.<br>Use “Incluir na lista de envio” nos imóveis.</div>';
    var on = inList();
    document.querySelectorAll(".add").forEach(function (b) {
      var m = !!b.closest(".mbar"); b.setAttribute("aria-pressed", on);
      b.innerHTML = on ? i("list-checks") + (m ? "Na lista" : "Está na lista de envio") : i("list-plus") + (m ? "Incluir na lista" : "Incluir na lista de envio");
    });
    drawIcons();
  }
  function openDock(o) { $("#dock").classList.toggle("open", o); $("#dockBtn").setAttribute("aria-expanded", o); }
  function toast(t) { var el = $("#toast"); el.textContent = t; el.classList.add("show"); clearTimeout(toast.t); toast.t = setTimeout(function () { el.classList.remove("show"); }, 4200); }

  /* número do WhatsApp: um só, usado nos dois campos e lembrado no navegador */
  var PKEY = "imobeasy_whatsapp";
  var digits = function (s) { return String(s || "").replace(/\D/g, "").slice(0, 11); };
  function fmt(s) {
    var d = digits(s); if (!d) return "";
    if (d.length <= 2) return "(" + d;
    if (d.length <= 6) return "(" + d.slice(0, 2) + ") " + d.slice(2);
    if (d.length <= 10) return "(" + d.slice(0, 2) + ") " + d.slice(2, 6) + "-" + d.slice(6);
    return "(" + d.slice(0, 2) + ") " + d.slice(2, 7) + "-" + d.slice(7);
  }
  var phone = ""; try { phone = localStorage.getItem(PKEY) || ""; } catch (e) { /* idem */ }
  function syncPhones(src) {
    document.querySelectorAll("[data-phone]").forEach(function (el) { if (el !== src) el.value = fmt(phone); el.classList.remove("bad"); });
    ["err1", "err2"].forEach(function (id) { $("#" + id).textContent = ""; });
  }
  function checkPhone(inputId, errId) {
    var ok = digits(phone).length >= 10, el = $("#" + inputId);
    el.classList.toggle("bad", !ok); $("#" + errId).textContent = ok ? "" : "Digite seu WhatsApp com DDD";
    if (!ok) el.focus(); return ok;
  }

  /* ===== o envio de verdade: a Nay manda o card e as fotos para o número digitado ===== */
  var enviando = false;
  function meEnvia(codigos, aoTerminar) {
    if (enviando) return;
    enviando = true;
    document.querySelectorAll('[data-act="send"],[data-act="sendm"],[data-act="sendlist"]').forEach(function (b) { b.disabled = true; b.style.opacity = ".6"; });
    toast("Enviando para " + fmt(phone) + "…");
    fetch(API + "/api/me-envia", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ telefone: phone, codigos: codigos }) })
      .then(function (r) { return r.json().catch(function () { return {}; }); })
      .then(function (r) { toast(r.mensagem || (r.ok ? "Pronto! Em instantes chega no seu WhatsApp." : "Não foi possível enviar agora.")); if (r.ok && aoTerminar) aoTerminar(r); })
      .catch(function () { toast("Sem conexão. Tente de novo em instantes."); })
      .then(function () {
        enviando = false;
        document.querySelectorAll('[data-act="send"],[data-act="sendm"],[data-act="sendlist"]').forEach(function (b) { b.disabled = false; b.style.opacity = ""; });
      });
  }

  document.addEventListener("input", function (e) {
    if (!e.target.matches("[data-phone]")) return;
    phone = digits(e.target.value); e.target.value = fmt(phone);
    try { localStorage.setItem(PKEY, phone); } catch (err) { /* idem */ }
    syncPhones(e.target);
  });

  document.addEventListener("click", function (e) {
    var t = e.target.closest("button,a[data-act]"); if (!t) return;
    if (t.dataset.ph) abrirFoto(+t.dataset.ph);
    if (t.dataset.go) document.getElementById(t.dataset.go).scrollIntoView({ block: "start" });
    if (t.dataset.rm) { lista_envio = lista_envio.filter(function (x) { return String(x.codigo) !== t.dataset.rm; }); save(); renderList(); }
    var a = t.dataset.act;
    if (a === "send" && I) { if (checkPhone("phone1", "err1")) meEnvia([I.codigo]); }
    if (a === "sendm" && I) {
      if (digits(phone).length >= 10) meEnvia([I.codigo]);
      else { $("#sendCard").scrollIntoView({ block: "center" }); setTimeout(function () { $("#phone1").focus(); }, 350); }
    }
    if (a === "add" && I) {
      if (inList()) { lista_envio = lista_envio.filter(function (x) { return String(x.codigo) !== String(I.codigo); }); save(); renderList(); toast("Tirado da lista de envio"); }
      else {
        var preco = has(V.aluguel) ? "R$ " + reais(V.aluguel) + "/mês" : has(V.venda) ? "R$ " + reais(V.venda) : "Consulte";
        lista_envio.push({ codigo: I.codigo, titulo: I.titulo, sub: [L.bairro, preco].filter(has).join(" · "), foto: FOTOS[0] && FOTOS[0].real ? FOTOS[0].src : "" });
        save(); renderList(I.codigo); openDock(true);
        var b = $("#dockBtn"); b.classList.remove("pulse"); void b.offsetWidth; b.classList.add("pulse");
      }
    }
    if (a === "toggle") openDock(!$("#dock").classList.contains("open"));
    if (a === "close") openDock(false);
    if (a === "sendlist") {
      if (!lista_envio.length) toast("A lista está vazia");
      else if (checkPhone("phone2", "err2")) meEnvia(lista_envio.map(function (x) { return x.codigo; }));
    }
    if (a === "clear") { lista_envio = []; save(); renderList(); }
  });
  $("#prev").onclick = function () { rolarFaixa(-1); };
  $("#next").onclick = function () { rolarFaixa(1); };
  $("#lbPrev").onclick = function () { if (FOTOS.length) showPhoto(cur - 1); };
  $("#lbNext").onclick = function () { if (FOTOS.length) showPhoto(cur + 1); };
  $("#lbClose").onclick = fecharFoto;
  $("#lbx").addEventListener("click", function (e) { if (e.target === this) fecharFoto(); });
  document.addEventListener("keydown", function (e) {
    if (e.target.matches("input,textarea")) return;
    var grande = !$("#lbx").hidden;
    if (grande && FOTOS.length && e.key === "ArrowLeft") showPhoto(cur - 1);
    if (grande && FOTOS.length && e.key === "ArrowRight") showPhoto(cur + 1);
    if (e.key === "Escape") { if (grande) fecharFoto(); else { openDock(false); fecharDono(); } }
  });
  var sx = null, stg = $("#lbx");
  stg.addEventListener("touchstart", function (e) { sx = e.touches[0].clientX; }, { passive: true });
  stg.addEventListener("touchend", function (e) {
    if (sx === null || !FOTOS.length) return;
    var d = e.changedTouches[0].clientX - sx; if (Math.abs(d) > 40) showPhoto(cur + (d < 0 ? 1 : -1)); sx = null;
  });

  /* ---------- quando o imóvel não existe mais (ou o endereço veio errado) ---------- */
  function semImovel(texto) {
    document.title = "Imóvel não encontrado · Imob Easy";
    document.querySelector(".layout").innerHTML =
      '<div></div><main><section class="fic"><h1>' + esc(texto) + '</h1><p class="condo">Ele pode ter sido alugado, vendido ou tirado do site.</p>' +
      '<p style="margin:14px 0 0"><a class="btn-o" href="/">Ver outros imóveis</a></p></section></main><div></div>';
    document.querySelector(".mbar").style.display = "none";
    renderList(); syncPhones();
  }

  function mostrar(imovel) {
    I = imovel; L = I.local || {}; C = I.carac || {}; V = I.valores || {};
    if (has(C.mobilia) && MOBILIA[String(C.mobilia).toLowerCase()]) C.mobilia = MOBILIA[String(C.mobilia).toLowerCase()];
    FOTOS = (I.fotos || []).map(function (u, k) { return { src: u, alt: "Foto " + (k + 1) + " do imóvel " + I.codigo, real: true }; });
    if (!FOTOS.length) FOTOS = [{ src: SEM_FOTO, alt: "Imóvel sem foto cadastrada", real: false }];
    document.title = I.titulo + " · Imob Easy";
    /* o endereço fica limpo e com o nome do imóvel, igual ao do desenho */
    try { if (I.slug) history.replaceState(null, "", "/imovel/" + I.codigo + "-" + I.slug); } catch (e) { /* endereço fica como veio */ }
    render();
    /* imóvel de parceiro não sai pela Nay: a página não oferece o envio */
    if (!I.pode_enviar) {
      $("#sendCard").style.display = "none";
      document.querySelector(".mbar").style.display = "none";
    }
    renderList(); syncPhones();
    menuDaEquipe(I.codigo);
    var io = new IntersectionObserver(function (en) {
      en.forEach(function (x) {
        if (x.isIntersecting) document.querySelectorAll(".nav button").forEach(function (b) { b.classList.toggle("act", b.dataset.go === x.target.id); });
      });
    }, { rootMargin: "-35% 0px -60% 0px" });
    NAV.forEach(function (n) { io.observe(document.getElementById(n[0])); });
  }

  /* ===== 16/10 (Pedro): "quando eu estiver logado no sistema e abrir um imóvel, um botão de menu lá em cima, ver
     proprietário, mas só se eu estiver logado". O admin (/admin/*, com a senha) deixa uma marca neste navegador
     (layout.js); sem ela o menu nem aparece, e o visitante comum não vê nada nem é perguntado por senha. O dono vem
     de /admin/api/imoveis/<código>/privado, que pede a senha do admin: os dados continuam só para a equipe. ===== */
  var EQUIPE = "imobeasy_equipe";
  function daEquipe() {
    var em = 0; try { em = Number(localStorage.getItem(EQUIPE) || 0); } catch (e) { /* sem armazenamento */ }
    return em > 0 && Date.now() - em < 60 * 86400000;
  }
  function fecharDono() { var b = $("#donoBox"); if (b) { b.hidden = true; $("#admDono").setAttribute("aria-expanded", "false"); } }
  function menuDaEquipe(cod) {
    if (!daEquipe() || !$("#adm")) return;
    $("#adm").hidden = false;
    $("#admEditar").href = "/admin/imovel-editar.html?codigo=" + encodeURIComponent(cod);
    $("#admDono").onclick = function (e) {
      e.stopPropagation();
      var box = $("#donoBox");
      if (!box.hidden) { fecharDono(); return; }
      box.hidden = false; $("#admDono").setAttribute("aria-expanded", "true");
      box.innerHTML = "<h4>Proprietário</h4><p>Carregando…</p>";
      fetch("/admin/api/imoveis/" + encodeURIComponent(cod) + "/privado", { credentials: "same-origin" })
        .then(function (r) { if (!r.ok) throw new Error(r.status === 401 ? "Entre no admin para ver o proprietário." : "Não consegui agora."); return r.json(); })
        .then(function (d) {
          var p = d.proprietario;
          if (!p) { box.innerHTML = "<h4>Proprietário</h4><p>Nenhum proprietário ligado a este imóvel.</p>"; return; }
          var fone = String(p.telefone || "").replace(/\D/g, "");
          var zap = fone ? (fone.length <= 11 ? "55" + fone : fone) : "";
          box.innerHTML = "<h4>Proprietário</h4>" +
            '<p class="nome">' + esc([p.tratamento, p.nome].filter(has).join(" ") || "(sem nome)") + "</p>" +
            (has(p.telefone) ? '<div class="lin">' + i("phone") + '<a href="tel:+' + esc(zap) + '">' + esc(p.telefone) + "</a></div>" : "") +
            (has(p.email) ? '<div class="lin">' + i("mail") + '<a href="mailto:' + esc(p.email) + '">' + esc(p.email) + "</a></div>" : "") +
            (has(p.documento) ? '<div class="lin">' + i("id-card") + esc(p.documento) + "</div>" : "") +
            (zap ? '<a class="zap" href="https://wa.me/' + esc(zap) + '" target="_blank" rel="noopener">' + i("message-circle") + "Chamar no WhatsApp</a>" : "") +
            ((p.outros_imoveis || []).length ? '<div class="outros">Outros imóveis dele: ' + p.outros_imoveis.map(function (c) {
              return '<a href="/imovel/' + encodeURIComponent(c) + '">' + esc(c) + "</a>"; }).join("") + "</div>" : "");
          drawIcons();
        })
        .catch(function (err) { box.innerHTML = "<h4>Proprietário</h4><p>" + esc(err.message) + "</p>"; });
    };
    document.addEventListener("click", function (e) { if (!e.target.closest("#adm")) fecharDono(); });
    drawIcons();
  }

  var codigo = codigoDoEndereco();
  if (!codigo) { semImovel("Imóvel não encontrado"); return; }
  fetch(API + "/api/imovel-publico/" + codigo)
    .then(function (r) { return r.ok ? r.json() : null; })
    .then(function (imovel) { if (imovel && imovel.codigo) mostrar(imovel); else semImovel("Este imóvel não está mais disponível"); })
    .catch(function () { semImovel("Não foi possível carregar o imóvel agora"); });
})();
