/* O admin do blog (406, 17/10/2026): a lista dos artigos (com a nota de SEO e as visitas), as visitas por origem e a
   newsletter de corretores. As rotas são /admin/api/blog/* (a API do site, atrás da senha do admin). */
(function () {
  "use strict";
  var $ = function (id) { return document.getElementById(id); };
  var BLOG = "https://blog.imobeasy.online";
  var artigos = [], categorias = [];

  function esc(s) { return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]; }); }
  function n(v) { return Number(v || 0).toLocaleString("pt-BR"); }
  function dm(iso) { return iso ? new Date(iso).toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit", year: "2-digit" }) : "—"; }
  function pedir(url, op) {
    return fetch(url, Object.assign({ credentials: "same-origin", headers: { "Content-Type": "application/json" } }, op || {}))
      .then(function (r) { return r.json().catch(function () { return {}; }).then(function (j) {
        if (r.status === 401) throw new Error("a senha do painel não foi aceita: recarregue a página");
        if (!r.ok) throw new Error(j.erro || ("HTTP " + r.status)); return j; }); });
  }
  function nota(v) {
    if (v == null) return '<span class="bg-nota" title="ainda sem verificação">—</span>';
    var c = v >= 80 ? "boa" : v >= 55 ? "media" : "ruim";
    return '<span class="bg-nota bg-nota--' + c + '" title="nota de SEO">' + v + "</span>";
  }

  /* TUDO EM HORA DE MANAUS (o relógio do Pedro é Brasília, 1 h na frente): o que se vê e o que se digita é Manaus,
     e vai ao banco com -04:00 (Manaus não tem horário de verão). */
  var FUSO = "America/Manaus", DESLOC = "-04:00";
  function dmh(iso) { return iso ? new Date(iso).toLocaleString("pt-BR", { timeZone: FUSO, day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" }) : "—"; }
  function toast(msg, erro) {
    var t = document.getElementById("bg-toast");
    if (!t) { t = document.createElement("div"); t.id = "bg-toast"; t.className = "bg-toast"; document.body.appendChild(t); }
    t.textContent = msg; t.classList.toggle("erro", !!erro); t.hidden = false; clearTimeout(t._t); t._t = setTimeout(function () { t.hidden = true; }, erro ? 6000 : 2600);
  }
  /* "AAAA-MM-DDTHH:MM" digitado como hora de Manaus -> ISO com -04:00 */
  function isoLocal(valor) { return String(valor).slice(0, 16) + ":00" + DESLOC; }
  /* ISO qualquer -> "AAAA-MM-DDTHH:MM" na hora de Manaus (para o input datetime-local) */
  function paraInputLocal(iso) {
    var d = new Date(iso), f = new Intl.DateTimeFormat("en-CA", { timeZone: FUSO, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hour12: false });
    var o = {}; f.formatToParts(d).forEach(function (x) { o[x.type] = x.value; });
    return o.year + "-" + o.month + "-" + o.day + "T" + (o.hour === "24" ? "00" : o.hour) + ":" + o.minute;
  }

  /* ================================================================ AGENDA (412) */
  function agenda() {
    $("ag-lista").innerHTML = '<p class="bg-vazio">Carregando…</p>';
    pedir("api/blog/artigos").then(function (j) {
      var todos = j.artigos || [];
      var agendados = todos.filter(function (a) { return !a.publicado && a.agendado_para; }).sort(function (a, b) { return new Date(a.agendado_para) - new Date(b.agendado_para); });
      var desde = new Date(); desde.setDate(desde.getDate() - 7);
      var recentes = todos.filter(function (a) { return a.publicado && a.publicado_em && new Date(a.publicado_em) >= desde; }).sort(function (a, b) { return new Date(b.publicado_em) - new Date(a.publicado_em); });
      var semCapa = agendados.filter(function (a) { return !a.capa_url; }).length;
      var prox7 = agendados.filter(function (a) { return new Date(a.agendado_para) - Date.now() < 7 * 86400000; }).length;
      $("ag-resumo").innerHTML =
        "<div><span>Agendados</span><strong>" + agendados.length + "</strong></div>" +
        "<div><span>Nos próximos 7 dias</span><strong>" + prox7 + "</strong></div>" +
        "<div><span>Sem capa</span><strong>" + semCapa + "</strong></div>" +
        "<div><span>Publicados na última semana</span><strong>" + recentes.length + "</strong></div>" +
        "<div><span>Rascunhos</span><strong>" + todos.filter(function (a) { return !a.publicado && !a.agendado_para; }).length + "</strong></div>";
      var porDia = {};
      agendados.forEach(function (a) { var k = new Date(a.agendado_para).toLocaleDateString("pt-BR", { timeZone: FUSO, weekday: "long", day: "2-digit", month: "2-digit" }); (porDia[k] = porDia[k] || []).push(a); });
      var h = "";
      Object.keys(porDia).forEach(function (dia) {
        h += '<div class="ag-dia"><h3>' + esc(dia) + " <small>" + porDia[dia].length + " post" + (porDia[dia].length === 1 ? "" : "s") + "</small></h3>" + porDia[dia].map(linhaAgenda).join("") + "</div>";
      });
      if (!agendados.length) h += '<p class="bg-vazio">Nenhum artigo agendado. Use a aba "Importar posts" ou marque uma data no editor.</p>';
      if (recentes.length) h += '<div class="ag-dia ag-dia--pub"><h3>Saíram na última semana</h3>' + recentes.map(linhaAgenda).join("") + "</div>";
      $("ag-lista").innerHTML = h;
    }).catch(function (e) { $("ag-lista").innerHTML = '<p class="bg-vazio">' + esc(e.message) + "</p>"; });
  }
  function linhaAgenda(a) {
    var pub = !!a.publicado, quando = pub ? a.publicado_em : a.agendado_para;
    return '<article class="ag-item" data-id="' + a.id + '">' +
      (a.capa_url ? '<img class="ag-capa" src="' + esc(a.capa_url) + '" alt="">' : '<div class="ag-capa ag-capa--vazia" title="sem capa">sem capa</div>') +
      '<div class="ag-corpo"><div class="bg-titulo"><a href="blog-editar.html?id=' + a.id + '">' + esc(a.titulo) + "</a><small>" + esc(a.categoria_nome || a.categoria) + " · " + nota(a.seo_nota).replace(/<[^>]+>/g, "") + " de SEO · " + n(a.palavras) + " palavras" + (a.palavra_chave ? " · “" + esc(a.palavra_chave) + "”" : "") + "</small></div>" +
      '<div class="ag-acoes">' + (pub
        ? '<span class="bg-status bg-status--pub">no ar ' + dmh(quando) + "</span>"
        : '<label>sai em <input type="datetime-local" value="' + paraInputLocal(quando) + '" data-data></label>' +
          '<button type="button" class="btn-neutro" data-acao="salvar-data">Salvar data</button>' +
          '<button type="button" class="btn-neutro" data-acao="publicar">Publicar agora</button>' +
          (a.capa_url ? "" : '<button type="button" class="btn-neutro" data-acao="capa">Buscar capa</button>')) +
      "</div></div></article>";
  }
  function carregarArtigo(id) { return pedir("api/blog/artigos/" + id); }
  function salvarArtigo(a, mud) {
    var corpo = { id: a.id, titulo: a.titulo, slug: a.slug, resumo: a.resumo, categoria: a.categoria, tipo: a.tipo, codigo: a.codigo, bairro: a.bairro, corpo: a.corpo,
                  capa_url: a.capa_url, capa_alt: a.capa_alt, autor: a.autor, palavra_chave: a.palavra_chave, faq: a.faq || [], imoveis_relacionados: a.imoveis_relacionados || [],
                  publicado: a.publicado, publicado_em: a.publicado_em, agendado_para: a.agendado_para, seo_nota: a.seo_nota };
    Object.keys(mud || {}).forEach(function (k) { corpo[k] = mud[k]; });
    return pedir("api/blog/artigos", { method: "POST", body: JSON.stringify(corpo) });
  }
  $("ag-lista").addEventListener("click", function (e) {
    var b = e.target.closest("[data-acao]"); if (!b) return;
    var item = b.closest("[data-id]"), id = item.dataset.id, acao = b.dataset.acao;
    b.disabled = true;
    carregarArtigo(id).then(function (a) {
      if (acao === "salvar-data") { var v = item.querySelector("[data-data]").value; if (!v) throw new Error("escolha a data"); return salvarArtigo(a, { agendado_para: isoLocal(v) }).then(function () { toast("Data salva (hora de Manaus)"); }); }
      if (acao === "publicar") { if (!confirm("Publicar “" + a.titulo + "” agora?")) return; return salvarArtigo(a, { publicado: true, agendado_para: null }).then(function () { toast("No ar"); }); }
      if (acao === "capa") return escolherCapa(a);
    }).then(function () { agenda(); }).catch(function (err) { toast(err.message, true); b.disabled = false; });
  });
  /* buscar e escolher a capa de um artigo já criado */
  function escolherCapa(a) {
    var q = prompt("Buscar imagem de capa (em inglês acha mais):", a.capa_busca || a.palavra_chave || a.titulo);
    if (!q) return Promise.resolve();
    return pedir("api/blog/imagens?q=" + encodeURIComponent(q) + "&n=10").then(function (j) {
      var c = j.candidatas || [];
      if (!c.length) { toast("Nenhuma imagem para “" + q + "”" + (j.pexels ? "" : " (sem a chave do Pexels acha pouco)"), true); return; }
      return new Promise(function (resolve) {
        var caixa = document.createElement("div"); caixa.className = "im-escolha";
        caixa.innerHTML = '<div class="im-escolha__caixa"><h3>Capa para “' + esc(a.titulo) + '”</h3><div class="im-cands">' + c.map(function (x, i) {
          return '<figure data-i="' + i + '"><img src="' + esc(x.thumb || x.url) + '" alt="" loading="lazy"><figcaption>' + esc(x.credito || x.fonte) + " · " + (x.largura || "?") + "×" + (x.altura || "?") + "</figcaption></figure>"; }).join("") +
          '</div><div class="bg-acoes"><button type="button" class="btn-neutro" data-fechar>Cancelar</button></div></div>';
        document.body.appendChild(caixa);
        caixa.addEventListener("click", function (ev) {
          if (ev.target.closest("[data-fechar]") || ev.target === caixa) { caixa.remove(); resolve(); return; }
          var f = ev.target.closest("figure[data-i]"); if (!f) return;
          var x = c[Number(f.dataset.i)]; caixa.remove();
          toast("Baixando e convertendo…");
          pedir("api/blog/imagens/guardar", { method: "POST", body: JSON.stringify({ url: x.url, capa: true }) }).then(function (g) {
            var corpo = a.corpo || ""; if (x.credito && corpo.indexOf(x.credito) < 0) corpo = corpo.trim() + "\n\n*Foto da capa: " + x.credito + "*";
            return salvarArtigo(a, { capa_url: g.url, capa_alt: a.capa_alt || a.titulo, corpo: corpo });
          }).then(function () { toast("Capa salva"); resolve(); }).catch(function (err) { toast(err.message, true); resolve(); });
        });
      });
    });
  }

  /* ================================================================ IMPORTAR POSTS (412) */
  var imPosts = [], imPreparado = false;
  function importarPreparar() {
    if (imPreparado) return; imPreparado = true;
    var amanha = new Date(); amanha.setDate(amanha.getDate() + 1);
    $("im-de").value = amanha.toISOString().slice(0, 10);
    $("im-ler").addEventListener("click", importarLer);
    $("im-recalcular").addEventListener("click", function () { calcularDatas(); pintarImport(); });
    $("im-criar").addEventListener("click", importarCriar);
    $("im-posts").addEventListener("click", importarClique);
    $("im-posts").addEventListener("change", function (e) {
      var t = e.target, card = t.closest("[data-k]"); if (!card) return;
      var p = imPosts[Number(card.dataset.k)];
      if (t.dataset.campo) { p[t.dataset.campo] = t.value; if (t.dataset.campo !== "agendado_local") p.seo = avaliarPost(p); }
      if (t.dataset.campo === "agendado_local") p.agendado_para = isoLocal(t.value);
      pintarCabecalhoImport(card, p);
    });
  }
  function importarLer() {
    var arq = $("im-arquivo").files[0], texto = $("im-texto").value;
    var ler = arq ? arq.text() : Promise.resolve(texto);
    $("im-estado").textContent = "lendo e buscando imagens… (uns segundos por post)"; $("im-ler").disabled = true;
    ler.then(function (t) {
      if (!t || !t.trim()) throw new Error("escolha o arquivo ou cole o texto");
      $("im-texto").value = t;
      return pedir("api/blog/importar/previa", { method: "POST", body: JSON.stringify({ texto: t, imagens: !$("im-sem-imagens").checked }) });
    }).then(function (j) {
      /* a 1ª candidata só entra sozinha quando vem do Pexels; do Openverse/Wikimedia (sem chave) a escolha é à mão,
         porque em 19/10 a escolha automática trouxe envelope antigo e foto de político como capa */
      imPosts = (j.posts || []).map(function (p, k) {
        p.k = k; p.capa = j.pexels ? ((p.capa_candidatas || [])[0] || null) : null;
        p.imagens = {}; (p.imagens_pedidas || []).forEach(function (im) { p.imagens[im.marcador] = j.pexels ? ((im.candidatas || [])[0] || null) : null; });
        p.seo = avaliarPost(p); return p;
      });
      $("im-aviso-pexels").hidden = !!j.pexels;
      $("im-agendamento").hidden = false; $("im-rodape").hidden = false;
      calcularDatas(); pintarImport();
      $("im-estado").textContent = imPosts.length + " post" + (imPosts.length === 1 ? "" : "s") + " lidos";
    }).catch(function (e) { $("im-estado").textContent = ""; toast(e.message, true); }).then(function () { $("im-ler").disabled = false; });
  }
  function avaliarPost(p) {
    if (!window.BlogSEO) return null;
    try { return window.BlogSEO.avaliar({ titulo: p.titulo, slug: p.slug, resumo: p.resumo, corpo: p.corpo, palavra_chave: p.palavra_chave, faq: p.faq, categoria: p.categoria, capa_url: p.capa ? "x" : "", capa_alt: p.capa_alt, codigo: p.codigo, tipo: p.tipo }); }
    catch (e) { return null; }
  }
  /* 2 por dia (Pedro), nos horários dados, alternando categorias para não sair dois de corretores seguidos */
  function calcularDatas() {
    var de = $("im-de").value ? new Date($("im-de").value + "T00:00:00") : new Date();
    var porDia = Math.max(1, Math.min(6, Number($("im-por-dia").value) || 2));
    var horas = $("im-horas").value.split(",").map(function (s) { return s.trim(); }).filter(Boolean);
    while (horas.length < porDia) horas.push(horas.length ? horas[horas.length - 1] : "09:00");
    var ordem = imPosts.slice();
    if ($("im-alternar").checked) {
      var grupos = {}; ordem.forEach(function (p) { (grupos[p.categoria] = grupos[p.categoria] || []).push(p); });
      var chaves = Object.keys(grupos), out = []; var resta = true;
      while (resta) { resta = false; chaves.forEach(function (c) { if (grupos[c].length) { out.push(grupos[c].shift()); resta = true; } }); }
      ordem = out;
    }
    ordem.forEach(function (p, i) {
      var d = new Date(de); d.setDate(de.getDate() + Math.floor(i / porDia));
      var hm = horas[i % porDia].split(":"), pp = function (n) { return String(n).padStart(2, "0"); };
      // a data do calendário + o horário digitado = hora de Manaus
      p.agendado_para = isoLocal(d.getFullYear() + "-" + pp(d.getMonth() + 1) + "-" + pp(d.getDate()) + "T" + pp(Number(hm[0]) || 9) + ":" + pp(Number(hm[1]) || 0)); p.ordem = i;
    });
    imPosts.sort(function (a, b) { return a.ordem - b.ordem; }).forEach(function (p, k) { p.k = k; });
  }
  function pintarCabecalhoImport(card, p) {
    var s = p.seo; var cab = card.querySelector(".im-cab");
    if (cab) cab.innerHTML = '<span class="bg-status bg-status--ag">' + dmh(p.agendado_para) + "</span> " + esc(p.titulo) + " " + (s ? nota(s.nota) : "") +
      (p.avisos && p.avisos.length ? ' <span class="bg-status bg-status--rasc" title="' + esc(p.avisos.join("; ")) + '">' + p.avisos.length + " aviso(s)</span>" : "");
  }
  function cands(lista, escolhido, tipo, marcador) {
    if (!lista || !lista.length) return '<p class="im-nada">nenhuma imagem encontrada <button type="button" class="sc-link" data-buscar="' + esc(tipo) + '" data-marcador="' + esc(marcador || "") + '">buscar com outras palavras</button></p>';
    return '<div class="im-cands im-cands--mini">' + lista.map(function (x, i) {
      var on = escolhido && escolhido.url === x.url;
      return '<figure data-escolher="' + esc(tipo) + '" data-marcador="' + esc(marcador || "") + '" data-i="' + i + '" class="' + (on ? "on" : "") + '"><img src="' + esc(x.thumb || x.url) + '" alt="" loading="lazy"><figcaption>' + esc(x.credito || x.fonte) + "</figcaption></figure>";
    }).join("") + '<figure data-escolher="' + esc(tipo) + '" data-marcador="' + esc(marcador || "") + '" data-i="-1" class="im-sem ' + (escolhido ? "" : "on") + '"><span>sem imagem</span></figure></div>' +
      '<button type="button" class="sc-link" data-buscar="' + esc(tipo) + '" data-marcador="' + esc(marcador || "") + '">buscar com outras palavras</button>';
  }
  function pintarImport() {
    $("im-posts").innerHTML = imPosts.map(function (p) {
      return '<article class="ed-cartao im-post" data-k="' + p.k + '">' +
        '<h2 class="im-cab"></h2>' +
        '<div class="ed-linha">' +
          '<label class="ed-campo"><span>Título</span><input class="entrada" data-campo="titulo" value="' + esc(p.titulo) + '"></label>' +
          '<label class="ed-campo"><span>Slug</span><input class="entrada" data-campo="slug" value="' + esc(p.slug || "") + '"></label>' +
        "</div>" +
        '<div class="ed-linha">' +
          '<label class="ed-campo"><span>Categoria</span><select class="selecao" data-campo="categoria">' + categorias.map(function (c) { return '<option value="' + c[0] + '"' + (c[0] === p.categoria ? " selected" : "") + ">" + esc(c[1]) + "</option>"; }).join("") + "</select></label>" +
          '<label class="ed-campo"><span>Palavra-chave</span><input class="entrada" data-campo="palavra_chave" value="' + esc(p.palavra_chave || "") + '"></label>' +
        "</div>" +
        '<label class="ed-campo"><span>Resumo <span class="conta">' + (p.resumo || "").length + " caracteres</span></span><input class=\"entrada\" data-campo=\"resumo\" value=\"" + esc(p.resumo || "") + '"></label>' +
        '<div class="ed-linha">' +
          '<label class="ed-campo"><span>Sai em</span><input type="datetime-local" class="entrada" data-campo="agendado_local" value="' + paraInputLocal(p.agendado_para) + '"></label>' +
          '<label class="ed-campo"><span>Alt da capa</span><input class="entrada" data-campo="capa_alt" value="' + esc(p.capa_alt || "") + '"></label>' +
        "</div>" +
        '<div class="ed-campo"><span class="rot">Capa <span class="dica">busca: “' + esc(p.capa_busca || "") + "” · " + esc(p.capa_fontes || "") + "</span></span>" + cands(p.capa_candidatas, p.capa, "capa", "") + "</div>" +
        (p.imagens_pedidas || []).map(function (im, j) {
          return '<div class="ed-campo"><span class="rot">Imagem do texto ' + (j + 1) + ' <span class="dica">busca: “' + esc(im.busca) + "” · alt: " + esc(im.alt) + "</span></span>" + cands(im.candidatas, p.imagens[im.marcador], "texto", im.marcador) + "</div>";
        }).join("") +
        "<details><summary>" + n((p.corpo || "").split(/\s+/).length) + " palavras · " + (p.faq || []).length + " perguntas no FAQ · ver o corpo</summary><pre class=\"im-corpo\">" + esc(p.corpo) + "</pre></details>" +
        "</article>";
    }).join("");
    document.querySelectorAll("#im-posts [data-k]").forEach(function (card) { pintarCabecalhoImport(card, imPosts[Number(card.dataset.k)]); });
  }
  function importarClique(e) {
    var f = e.target.closest("figure[data-escolher]"), bb = e.target.closest("[data-buscar]");
    var card = e.target.closest("[data-k]"); if (!card) return;
    var p = imPosts[Number(card.dataset.k)];
    if (f) {
      var i = Number(f.dataset.i), tipo = f.dataset.escolher, marcador = f.dataset.marcador;
      if (tipo === "capa") p.capa = i >= 0 ? p.capa_candidatas[i] : null;
      else p.imagens[marcador] = i >= 0 ? (p.imagens_pedidas.find(function (im) { return im.marcador === marcador; }) || {}).candidatas[i] : null;
      p.seo = avaliarPost(p); pintarImport(); return;
    }
    if (bb) {
      var tipo2 = bb.dataset.buscar, marcador2 = bb.dataset.marcador;
      var atual = tipo2 === "capa" ? p.capa_busca : ((p.imagens_pedidas.find(function (im) { return im.marcador === marcador2; }) || {}).busca);
      var q = prompt("Buscar imagem (em inglês acha mais):", atual || p.palavra_chave); if (!q) return;
      bb.disabled = true;
      pedir("api/blog/imagens?q=" + encodeURIComponent(q) + "&n=10").then(function (j) {
        if (tipo2 === "capa") { p.capa_busca = q; p.capa_candidatas = j.candidatas || []; p.capa_fontes = j.fontes; p.capa = p.capa_candidatas[0] || null; }
        else { var im = p.imagens_pedidas.find(function (x) { return x.marcador === marcador2; }); im.busca = q; im.candidatas = j.candidatas || []; im.fontes = j.fontes; p.imagens[marcador2] = im.candidatas[0] || null; }
        p.seo = avaliarPost(p); pintarImport();
      }).catch(function (err) { toast(err.message, true); });
    }
  }
  function importarCriar() {
    if (!imPosts.length) return;
    var semCapa = imPosts.filter(function (p) { return !p.capa; }).length;
    if (!confirm("Criar " + imPosts.length + " artigos agendados" + (semCapa ? " (" + semCapa + " sem capa)" : "") + "?")) return;
    $("im-criar").disabled = true; $("im-resultado").textContent = "baixando imagens e criando… (uns segundos por post)";
    var corpo = { posts: imPosts.map(function (p) {
      return { titulo: p.titulo, slug: p.slug, resumo: p.resumo, categoria: p.categoria, tipo: p.tipo, codigo: p.codigo, bairro: p.bairro, corpo: p.corpo, capa_alt: p.capa_alt,
               palavra_chave: p.palavra_chave, faq: p.faq, imagens_pedidas: p.imagens_pedidas.map(function (im) { return { marcador: im.marcador, alt: im.alt, legenda: im.legenda }; }),
               capa: p.capa ? { url: p.capa.url, credito: p.capa.credito } : null,
               imagens: Object.keys(p.imagens).reduce(function (o, k) { if (p.imagens[k]) o[k] = { url: p.imagens[k].url, credito: p.imagens[k].credito }; return o; }, {}),
               agendado_para: p.agendado_para, seo_nota: p.seo ? p.seo.nota : null };
    }) };
    pedir("api/blog/importar/criar", { method: "POST", body: JSON.stringify(corpo) }).then(function (j) {
      var ok = (j.resultados || []).filter(function (r) { return r.ok; }).length, erros = (j.resultados || []).filter(function (r) { return !r.ok; });
      $("im-resultado").innerHTML = ok + " criado" + (ok === 1 ? "" : "s") + (erros.length ? " · " + erros.length + " com erro: " + esc(erros.map(function (r) { return r.titulo + " (" + (r.erro || "?") + ")"; }).join("; ")) : "") + ' · <a href="#" data-ir-agenda>ver a agenda</a>';
      toast(ok + " artigos agendados");
      if (!erros.length) { imPosts = []; $("im-posts").innerHTML = ""; $("im-agendamento").hidden = true; $("im-rodape").hidden = false; }
      listar();
    }).catch(function (e) { $("im-resultado").textContent = e.message; toast(e.message, true); }).then(function () { $("im-criar").disabled = false; });
  }
  document.addEventListener("click", function (e) { if (e.target.closest("[data-ir-agenda]")) { e.preventDefault(); document.querySelector('.bg-abas [data-aba="agenda"]').click(); } });

  /* ---- abas ---- */
  document.querySelector(".bg-abas").addEventListener("click", function (e) {
    var b = e.target.closest("[data-aba]"); if (!b) return;
    document.querySelectorAll(".bg-abas [data-aba]").forEach(function (x) { x.setAttribute("aria-selected", String(x === b)); });
    document.querySelectorAll(".bg-aba").forEach(function (s) { s.hidden = s.dataset.aba !== b.dataset.aba; });
    if (b.dataset.aba === "metricas") metricas();
    if (b.dataset.aba === "newsletter") newsletter();
    if (b.dataset.aba === "agenda") agenda();
    if (b.dataset.aba === "importar") importarPreparar();
  });

  /* ---- artigos ---- */
  function listar() {
    pedir("api/blog/artigos").then(function (j) {
      artigos = j.artigos || []; categorias = j.categorias || [];
      $("bg-f-cat").innerHTML = '<option value="">Todas as categorias</option>' + categorias.map(function (c) { return '<option value="' + c[0] + '">' + esc(c[1]) + "</option>"; }).join("");
      var pub = artigos.filter(function (a) { return a.publicado; });
      $("bg-resumo").innerHTML =
        "<div><span>Publicados</span><strong>" + pub.length + "</strong></div>" +
        "<div><span>Rascunhos</span><strong>" + (artigos.length - pub.length) + "</strong></div>" +
        "<div><span>Visitas (30 dias)</span><strong>" + n(artigos.reduce(function (s, a) { return s + Number(a.visitas_30d || 0); }, 0)) + "</strong></div>" +
        "<div><span>Leituras de robôs (30 dias)</span><strong>" + n(artigos.reduce(function (s, a) { return s + Number(a.rastreadores_30d || 0); }, 0)) + "</strong></div>" +
        "<div><span>Nota média de SEO</span><strong>" + (pub.length ? Math.round(pub.reduce(function (s, a) { return s + Number(a.seo_nota || 0); }, 0) / pub.length) : "—") + "</strong></div>";
      pintar();
    }).catch(function (e) { $("bg-artigos").innerHTML = '<p class="bg-vazio">' + esc(e.message) + "</p>"; });
  }
  function pintar() {
    var cat = $("bg-f-cat").value, st = $("bg-f-status").value, q = $("bg-f-busca").value.trim().toLowerCase();
    var lista = artigos.filter(function (a) {
      return (!cat || a.categoria === cat) && (!st || (st === "pub") === !!a.publicado) && (!q || (a.titulo || "").toLowerCase().indexOf(q) >= 0);
    });
    if (!lista.length) { $("bg-artigos").innerHTML = '<p class="bg-vazio">' + (artigos.length ? "Nada com esse filtro." : "Nenhum artigo ainda. Clique em + Novo artigo.") + "</p>"; return; }
    $("bg-artigos").innerHTML = '<table class="bg-tabela"><thead><tr><th>Artigo</th><th>Categoria</th><th>Situação</th><th class="num" title="nota do verificador de SEO">SEO</th>' +
      '<th class="num">7 dias</th><th class="num">30 dias</th><th class="num" title="leituras de Googlebot, GPTBot, ClaudeBot… (30 dias)">Robôs</th><th>Atualizado</th><th></th></tr></thead><tbody>' +
      lista.map(function (a) {
        return "<tr><td class=\"bg-titulo\"><a href=\"blog-editar.html?id=" + a.id + '">' + esc(a.titulo) + "</a><small>" + (a.tipo === "imovel" ? "post de imóvel · cód. " + esc(a.codigo) + " · " : "") + n(a.palavras) + " palavras · /" + esc(a.slug) + "</small></td>" +
          "<td>" + esc(a.categoria_nome) + "</td>" +
          "<td>" + (a.publicado ? '<span class="bg-status bg-status--pub">no ar</span>' : a.agendado_para ? '<span class="bg-status bg-status--ag" title="sai sozinho na hora marcada">agendado ' + dmh(a.agendado_para) + "</span>" : '<span class="bg-status bg-status--rasc">rascunho</span>') + "</td>" +
          '<td class="num">' + nota(a.seo_nota) + "</td>" +
          '<td class="num">' + n(a.visitas_7d) + '</td><td class="num">' + n(a.visitas_30d) + '</td><td class="num">' + n(a.rastreadores_30d) + "</td>" +
          "<td>" + dm(a.atualizado_em) + "</td>" +
          '<td style="white-space:nowrap"><a class="btn-mini" href="blog-editar.html?id=' + a.id + '">Editar</a> ' +
          (a.publicado ? '<a class="btn-mini" href="' + BLOG + "/artigo/" + esc(a.slug) + '" target="_blank" rel="noopener">Ver</a>' : "") + "</td></tr>";
      }).join("") + "</tbody></table>";
  }
  ["bg-f-cat", "bg-f-status"].forEach(function (id) { $(id).addEventListener("change", pintar); });
  $("bg-f-busca").addEventListener("input", pintar);

  /* ---- visitas ---- */
  var grafico = null;
  function metricas() {
    var dias = Number($("bg-periodo").value), hoje = new Date();
    var de = new Date(hoje.getTime() - (dias - 1) * 864e5).toISOString().slice(0, 10);
    pedir("api/blog/metricas?de=" + de + "&ate=" + hoje.toISOString().slice(0, 10)).then(function (m) {
      var po = m.por_origem || {}, rot = (m.dias || []).map(function (d) { return d.slice(8, 10) + "/" + d.slice(5, 7); });
      var soma = function (k) { return (po[k] || []).reduce(function (s, v) { return s + v; }, 0); };
      $("bg-m-resumo").innerHTML =
        "<div><span>Visitas de gente</span><strong>" + n(m.total) + "</strong></div>" +
        "<div><span>Vindas do Google</span><strong>" + n(soma("google")) + "</strong></div>" +
        "<div><span>Vindas de IAs (ChatGPT…)</span><strong>" + n(soma("ia")) + "</strong></div>" +
        "<div><span>Redes e WhatsApp</span><strong>" + n(soma("social")) + "</strong></div>" +
        "<div><span>Leituras de robôs</span><strong>" + n(soma("rastreador")) + "</strong></div>";
      var cores = { google: "#2563eb", ia: "#7c3aed", social: "#e07bc4", direto: "#5cb98c", outro: "#9aa0ac" };
      var nomes = { google: "Google", ia: "IAs", social: "Redes/WhatsApp", direto: "Direto", outro: "Outros" };
      if (grafico) grafico.destroy();
      grafico = new Chart($("bg-g-visitas"), {
        data: { labels: rot, datasets: Object.keys(nomes).map(function (k) {
          return { type: "bar", label: nomes[k], data: po[k] || [], backgroundColor: cores[k], stack: "g", borderRadius: 2 };
        }).concat([{ type: "line", label: "Robôs (Googlebot, GPTBot…)", data: po.rastreador || [], borderColor: "#f59e0b", backgroundColor: "#f59e0b", borderDash: [4, 3], pointRadius: 2, yAxisID: "y1", tension: .3 }]) },
        options: { responsive: true, maintainAspectRatio: false, interaction: { mode: "index", intersect: false },
          plugins: { legend: { position: "bottom", labels: { boxWidth: 10 } } },
          scales: { x: { stacked: true, grid: { display: false } }, y: { stacked: true, beginAtZero: true, ticks: { precision: 0 } },
                    y1: { position: "right", beginAtZero: true, grid: { display: false }, ticks: { precision: 0 } } } }
      });
      var arts = m.artigos || [];
      $("bg-m-artigos").innerHTML = arts.length ? '<table class="bg-tabela"><thead><tr><th>Artigo</th><th class="num">Gente</th><th class="num">Google</th><th class="num">IAs</th><th class="num">Robôs</th></tr></thead><tbody>' +
        arts.map(function (a) {
          return '<tr><td class="bg-titulo"><a href="blog-editar.html?id=' + a.id + '">' + esc(a.titulo) + "</a></td><td class=\"num\"><b>" + n(a.visitas) + '</b></td><td class="num">' + n(a.google) + '</td><td class="num">' + n(a.ia) + '</td><td class="num">' + n(a.rastreadores) + "</td></tr>";
        }).join("") + "</tbody></table>" : '<p class="bg-vazio">Nenhuma visita no período ainda.</p>';
      var robos = m.rastreadores || {}, ks = Object.keys(robos).sort(function (a, b) { return robos[b] - robos[a]; });
      $("bg-m-robos").innerHTML = ks.length ? ks.map(function (k) { return "<div><span>" + esc(k) + "</span><b>" + n(robos[k]) + "</b></div>"; }).join("")
        : '<div><span style="color:var(--texto-fraco)">Nenhum robô passou ainda. O Google costuma levar alguns dias depois de o sitemap ser enviado.</span></div>';
    }).catch(function (e) { $("bg-m-artigos").innerHTML = '<p class="bg-vazio">' + esc(e.message) + "</p>"; });
  }
  $("bg-periodo").addEventListener("change", metricas);

  /* ---- newsletter ---- */
  function newsletter() {
    pedir("api/blog/newsletter").then(function (j) {
      $("bg-n-resumo").innerHTML =
        "<div><span>Cadastrados ativos</span><strong>" + n(j.ativos) + "</strong></div>" +
        "<div><span>Já se cadastraram</span><strong>" + n(j.total) + "</strong></div>" +
        "<div><span>Imóveis enviados (30 dias)</span><strong>" + n(j.envios_30d) + "</strong></div>";
      var lista = j.corretores || [];
      $("bg-news").innerHTML = lista.length ? '<table class="bg-tabela"><thead><tr><th>Nome</th><th>WhatsApp</th><th>CRECI</th><th>Cadastro</th><th class="num">Imóveis recebidos</th><th>Último envio</th><th>Situação</th><th></th></tr></thead><tbody>' +
        lista.map(function (c) {
          return "<tr><td><b>" + esc(c.nome || "—") + "</b>" + (c.ja_corretor ? ' <span class="bg-status bg-status--pub" title="já está no cadastro de corretores (grupos ou site antigo)">conhecido</span>' : "") + "</td><td>" + esc(c.telefone) + "</td><td>" + esc(c.creci || "—") + "</td><td>" + dm(c.criado_em) + '</td><td class="num">' + n(c.envios) + "</td><td>" + dm(c.ultimo_envio_em) + "</td>" +
            "<td>" + (c.ativo ? '<span class="bg-status bg-status--pub">recebe</span>' : '<span class="bg-status bg-status--rasc">saiu ' + dm(c.saiu_em) + "</span>") + "</td>" +
            "<td>" + (c.ativo ? '<button class="btn-mini btn-mini--perigo" type="button" data-sair="' + esc(c.telefone) + '">Tirar da lista</button>' : "") + "</td></tr>";
        }).join("") + "</tbody></table>" : '<p class="bg-vazio">Ninguém cadastrado ainda. O link para divulgar aos corretores: ' + BLOG + "/newsletter</p>";
    }).catch(function (e) { $("bg-news").innerHTML = '<p class="bg-vazio">' + esc(e.message) + "</p>"; });
  }
  $("bg-news").addEventListener("click", function (e) {
    var b = e.target.closest("[data-sair]"); if (!b) return;
    if (!confirm("Tirar " + b.dataset.sair + " da lista? Ele para de receber os imóveis novos.")) return;
    pedir("api/blog/newsletter/sair", { method: "POST", body: JSON.stringify({ telefone: b.dataset.sair }) }).then(newsletter);
  });

  listar();
})();
