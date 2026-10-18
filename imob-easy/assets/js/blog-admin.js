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

  /* ---- abas ---- */
  document.querySelector(".bg-abas").addEventListener("click", function (e) {
    var b = e.target.closest("[data-aba]"); if (!b) return;
    document.querySelectorAll(".bg-abas [data-aba]").forEach(function (x) { x.setAttribute("aria-selected", String(x === b)); });
    document.querySelectorAll(".bg-aba").forEach(function (s) { s.hidden = s.dataset.aba !== b.dataset.aba; });
    if (b.dataset.aba === "metricas") metricas();
    if (b.dataset.aba === "newsletter") newsletter();
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
          "<td>" + (a.publicado ? '<span class="bg-status bg-status--pub">no ar</span>' : '<span class="bg-status bg-status--rasc">rascunho</span>') + "</td>" +
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
