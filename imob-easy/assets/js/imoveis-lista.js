/* ==========================================================================
   Imob Easy — Tela Imóveis (revisão 11/09/2026)

   Antes: só os 1.225 do catálogo, corte em 200, só Apartamentos/Casas,
   nenhum filtro lateral fazia nada, e o filtro de vencimento na carga
   inicial reduzia a lista a 1 imóvel. Agora lê /api/imoveis-lista: TODOS
   os imóveis (catálogo + admin antigo, ~5.600) com status, paginado no
   servidor, e cada filtro vira parâmetro de verdade.
   ========================================================================== */
(function () {
  "use strict";
  var API = window.API_BASE;
  var POR_PAGINA = 50;
  var form = document.getElementById("filtros-imoveis");
  var corpo = document.getElementById("corpo-imoveis");
  var paginacao = document.getElementById("paginacao-imoveis");
  var contagem = document.getElementById("contagem-imoveis");
  var resumo = document.getElementById("resumo-imoveis");
  var estado = { page: 1, grupo: "", de: null, ate: null };
  var ultimo = { itens: [], total: 0 };
  var pedido = 0;
  window.IMOVEIS_NA_TELA = {};

  function esc(t) {
    return String(t == null ? "" : t).replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }

  var seletor = window.criarSeletorCondominio(document.getElementById("f-condominio"), { multiplo: true });

  // ?condo=<id>&condo_nome=<nome> vindo da tela de Condomínios (botão "Ver imóveis").
  var qs = new URLSearchParams(location.search);
  if (qs.get("condo")) seletor.definir([{ id: Number(qs.get("condo")), nome: qs.get("condo_nome") || "Condomínio " + qs.get("condo") }]);
  if (qs.get("status")) form.elements.status.value = qs.get("status");

  function escolha(nome) {
    var b = form.querySelector('[data-escolha="' + nome + '"] [aria-pressed="true"]');
    return b ? b.dataset.v : "";
  }

  form.querySelectorAll("[data-escolha]").forEach(function (grupo) {
    grupo.addEventListener("click", function (e) {
      var b = e.target.closest("button[data-v]");
      if (!b) return;
      var jaEstava = b.getAttribute("aria-pressed") === "true";
      grupo.querySelectorAll("button").forEach(function (x) { x.setAttribute("aria-pressed", "false"); });
      if (!jaEstava) b.setAttribute("aria-pressed", "true");
    });
  });

  function parametros(extra) {
    var f = form.elements;
    var p = new URLSearchParams();
    function pos(k, v) { if (v !== null && v !== undefined && String(v).trim() !== "") p.set(k, String(v).trim()); }
    pos("q", f.q.value);
    pos("status", f.status.value);
    pos("tipo", f.tipo.value);
    pos("grupo", estado.grupo);
    pos("condo_ids", seletor.valores().map(function (c) { return c.id; }).join(","));
    pos("bairro", f.bairro.value);
    pos("finalidade", f.finalidade.value);
    pos("vmin", f.vmin.value.replace(/\D/g, ""));
    pos("vmax", f.vmax.value.replace(/\D/g, ""));
    pos("quartos", escolha("quartos"));
    pos("vagas", escolha("vagas"));
    if (f.financia.checked) p.set("financia", "Sim");
    if (f.parceiro_sim.checked && !f.parceiro_nao.checked) p.set("parceiro", "sim");
    if (f.parceiro_nao.checked && !f.parceiro_sim.checked) p.set("parceiro", "nao");
    pos("criado_de", f.criado_de.value);
    pos("criado_ate", f.criado_ate.value);
    pos("ordem", f.ordem.value);
    pos("de", estado.de);
    pos("ate", estado.ate);
    Object.keys(extra || {}).forEach(function (k) { p.set(k, extra[k]); });
    return p;
  }

  var COR = {
    "Disponível": "etiqueta--verde", "Alugado": "etiqueta--azul", "Vendido": "etiqueta--laranja",
    "Arquivado": "etiqueta--cinza", "Removido": "etiqueta--vermelha", "Rascunho": "etiqueta--cinza",
    "Em revisão": "etiqueta--laranja", "Indisponível": "etiqueta--vermelha", "Fora do site": "etiqueta--cinza"
  };

  function linha(i) {
    var acoes = i.noCatalogo
      ? '<a class="btn-mini" href="imovel-editar.html?codigo=' + esc(i.codigo) + '">Editar</a>'
      : '<span class="btn-mini" title="Imóvel só do admin antigo: não está no catálogo, então não abre no editor">só consulta</span>';
    return '<tr data-codigo="' + esc(i.codigo) + '" class="' + (i.noCatalogo ? "" : "fora-catalogo") + '">' +
      "<td><strong>" + esc(i.codigo) + "</strong>" + (i.parceiro ? '<br><span class="etiqueta etiqueta--laranja" style="font-size:10px">parceiro</span>' : "") + "</td>" +
      '<td><span class="etiqueta ' + (COR[i.status] || "etiqueta--cinza") + '">' + esc(i.status) + "</span>" +
        (i.vencimento ? '<br><span style="font-size:var(--fs-xs);color:var(--texto-fraco)">contrato até ' +
          new Date(i.vencimento + "T00:00:00").toLocaleDateString("pt-BR") + "</span>" : "") + "</td>" +
      "<td>" + esc(i.financia) + "</td>" +
      "<td>" + esc(i.valor) + "</td>" +
      "<td>" + esc(i.condominio) + (i.tipo ? '<br><span style="font-size:var(--fs-xs);color:var(--texto-fraco)">' + esc(i.tipo) + "</span>" : "") + "</td>" +
      "<td>" + esc([i.endereco, i.bairro].filter(Boolean).join(" - ")) + "</td>" +
      "<td>" + esc(i.proprietario) + "</td>" +
      '<td class="col-acoes"><span class="acoes-celula"><button class="btn-mini" type="button" data-ver="' + esc(i.codigo) + '">Ver</button>' + acoes + "</span></td>" +
      "</tr>";
  }

  function pintarPaginacao(total) {
    var paginas = Math.max(1, Math.ceil(total / POR_PAGINA));
    var p = estado.page;
    var nums = [];
    for (var n = Math.max(1, p - 2); n <= Math.min(paginas, p + 2); n++) nums.push(n);
    if (nums[0] > 1) nums = [1].concat(nums[0] > 2 ? ["…"] : []).concat(nums);
    if (nums[nums.length - 1] < paginas) nums = nums.concat(nums[nums.length - 1] < paginas - 1 ? ["…"] : []).concat([paginas]);
    paginacao.innerHTML =
      '<button type="button" data-pagina="' + (p - 1) + '"' + (p <= 1 ? " disabled" : "") + ' aria-label="Página anterior">&laquo;</button>' +
      nums.map(function (n) {
        if (n === "…") return '<span class="reticencias" aria-hidden="true">…</span>';
        return n === p ? '<span class="ativo" aria-current="page">' + n + "</span>"
          : '<button type="button" data-pagina="' + n + '">' + n + "</button>";
      }).join("") +
      '<button type="button" data-pagina="' + (p + 1) + '"' + (p >= paginas ? " disabled" : "") + ' aria-label="Próxima página">&raquo;</button>';
  }

  function carregar() {
    var meu = ++pedido;
    corpo.innerHTML = '<tr><td colspan="8">Carregando…</td></tr>';
    return fetch(API + "/api/imoveis-lista?" + parametros({ page: estado.page, per: POR_PAGINA }).toString())
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (d) {
        if (meu !== pedido) return ultimo.itens;
        ultimo = d;
        window.IMOVEIS_NA_TELA = {};
        d.itens.forEach(function (i) { window.IMOVEIS_NA_TELA[i.codigo] = i; });
        corpo.innerHTML = d.itens.length ? d.itens.map(linha).join("")
          : '<tr><td colspan="8" style="text-align:center;color:var(--texto-fraco);padding:24px">Nenhum imóvel com esses filtros.</td></tr>';
        var ini = d.total ? (estado.page - 1) * POR_PAGINA + 1 : 0;
        contagem.textContent = d.total.toLocaleString("pt-BR") + " imóve" + (d.total === 1 ? "l" : "is") +
          (d.total ? " · mostrando " + ini + "–" + Math.min(d.total, estado.page * POR_PAGINA) : "");
        resumo.textContent = "Disponíveis para aluguel: " + d.resumo.aluguel + " / para venda: " + d.resumo.venda +
          " / parceiros: " + d.resumo.parceiros + " / total no sistema: " + d.resumo.todos.toLocaleString("pt-BR");
        pintarPaginacao(d.total);
        return d.itens;
      })
      .catch(function () {
        corpo.innerHTML = '<tr><td colspan="8">Não foi possível carregar os imóveis.</td></tr>';
        return [];
      });
  }

  function recomecar() { estado.page = 1; return carregar(); }

  form.addEventListener("submit", function (e) { e.preventDefault(); recomecar(); });
  form.addEventListener("reset", function () {
    setTimeout(function () {
      seletor.limpar();
      form.querySelectorAll("[data-escolha] button").forEach(function (b) { b.setAttribute("aria-pressed", "false"); });
      recomecar();
    }, 0);
  });
  form.elements.status.addEventListener("change", recomecar);
  form.elements.ordem.addEventListener("change", recomecar);

  document.getElementById("btn-revisao").addEventListener("click", function () {
    form.elements.status.value = "Em revisão";
    recomecar();
  });

  paginacao.addEventListener("click", function (e) {
    var b = e.target.closest("[data-pagina]");
    if (!b || b.disabled) return;
    estado.page = Number(b.dataset.pagina);
    carregar();
    window.scrollTo({ top: 0, behavior: "smooth" });
  });

  document.querySelectorAll("[data-grupo]").forEach(function (aba) {
    aba.addEventListener("click", function () { estado.grupo = aba.dataset.grupo; recomecar(); });
  });

  document.getElementById("btn-exportar").addEventListener("click", function () {
    window.location.href = API + "/api/imoveis-lista?" + parametros({ formato: "csv", per: 6000 }).toString();
  });

  document.getElementById("btn-copiar").addEventListener("click", function () {
    var txt = (ultimo.itens || []).map(function (i) {
      return [i.codigo, i.status, i.valor, i.condominio, i.endereco, i.bairro].filter(Boolean).join(" | ");
    }).join("\n");
    var st = document.getElementById("copiar-status");
    if (!txt) { st.textContent = "Nada na tela para copiar."; return; }
    (navigator.clipboard ? navigator.clipboard.writeText(txt) : Promise.reject())
      .then(function () { st.textContent = (ultimo.itens.length) + " linha(s) copiadas."; })
      .catch(function () { st.textContent = "O navegador não deixou copiar."; });
  });

  corpo.addEventListener("click", function (e) {
    var b = e.target.closest("[data-ver]");
    if (!b) return;
    var tr = b.closest("tr[data-codigo]");
    if (tr) tr.dispatchEvent(new MouseEvent("click", { bubbles: true }));
  });

  // Filtro de vencimento (em cima da tabela). Sem filtro na carga inicial.
  window.criarFiltroVencimento({
    container: document.getElementById("filtro-vencimento-imoveis"),
    area: "imoveis",
    buscar: function (de, ate) { estado.de = de; estado.ate = ate; return recomecar(); },
    renderizar: function () {},
    itensParaLista: function () {
      return fetch(API + "/api/imoveis-lista?" + parametros({ page: 1, per: 2000 }).toString())
        .then(function (r) { return r.ok ? r.json() : { itens: [] }; })
        .then(function (d) { return d.itens; });
    },
    obterResumoItem: function (item) {
      return { codigo: item.codigo, condominio: item.condominio, vencimento: item.vencimento, status: item.status };
    }
  });

  // Aba Anúncios: o que está no catálogo, publicado ou não.
  fetch(API + "/api/anuncios")
    .then(function (r) { return r.json(); })
    .then(function (itens) {
      document.getElementById("corpo-anuncios").innerHTML = itens.map(function (a) {
        return "<tr>" +
          '<td><span class="etiqueta ' + (a.status === "Rascunho" ? "etiqueta--laranja" : "etiqueta--verde") + '">' +
            esc(a.status === "Rascunho" ? "Fora do site" : "Publicado") + "</span></td>" +
          "<td><strong>" + esc(a.codigo) + "</strong> (" + esc(a.referencia) + ")</td>" +
          "<td>" + esc(a.tipo) + "</td><td>" + esc(a.financia) + "</td><td>" + esc(a.valor) + "</td>" +
          '<td class="col-acoes"><a class="btn-mini" href="imovel-editar.html?codigo=' + esc(a.codigo) + '">Editar</a></td></tr>';
      }).join("") || '<tr><td colspan="6">Nenhum anúncio.</td></tr>';
    })
    .catch(function () { document.getElementById("corpo-anuncios").innerHTML = '<tr><td colspan="6">Não foi possível carregar.</td></tr>'; });
})();
