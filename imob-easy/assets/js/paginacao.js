/* Imob Easy — paginação real (revisão 11/09/2026). As telas tinham números
   fixos ("1 2 3 … 282") que não levavam a lugar nenhum.
   pintarPaginacao(nav, pagina, total, porPagina, aoIr) */
(function () {
  "use strict";
  window.pintarPaginacao = function (nav, p, total, por, aoIr) {
    var paginas = Math.max(1, Math.ceil(total / por));
    var nums = [];
    for (var n = Math.max(1, p - 2); n <= Math.min(paginas, p + 2); n++) nums.push(n);
    if (nums[0] > 1) nums = [1].concat(nums[0] > 2 ? ["…"] : []).concat(nums);
    if (nums[nums.length - 1] < paginas) nums = nums.concat(nums[nums.length - 1] < paginas - 1 ? ["…"] : []).concat([paginas]);
    nav.innerHTML =
      '<button type="button" data-pagina="' + (p - 1) + '"' + (p <= 1 ? " disabled" : "") + ' aria-label="Página anterior">&laquo;</button>' +
      nums.map(function (n) {
        if (n === "…") return '<span class="reticencias" aria-hidden="true">…</span>';
        return n === p ? '<span class="ativo" aria-current="page">' + n + "</span>"
          : '<button type="button" data-pagina="' + n + '">' + n + "</button>";
      }).join("") +
      '<button type="button" data-pagina="' + (p + 1) + '"' + (p >= paginas ? " disabled" : "") + ' aria-label="Próxima página">&raquo;</button>';
    nav.onclick = function (e) {
      var b = e.target.closest("[data-pagina]");
      if (!b || b.disabled) return;
      aoIr(Number(b.dataset.pagina));
      window.scrollTo({ top: 0, behavior: "smooth" });
    };
  };
  if (!document.getElementById("estilo-paginacao")) {
    var st = document.createElement("style");
    st.id = "estilo-paginacao";
    st.textContent = ".paginacao-sistema button{border:0;background:transparent;cursor:pointer;font:inherit;color:inherit;padding:4px 8px}" +
      ".paginacao-sistema button[disabled]{opacity:.35;cursor:default}.paginacao-sistema .ativo{font-weight:700}" +
      ".contagem-lista{font-size:var(--fs-sm);color:var(--texto-fraco);margin:0 0 12px;text-align:right}";
    document.head.appendChild(st);
  }
})();
