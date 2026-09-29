/* ==========================================================================
   Imob Easy — Imóveis vindos da conversa da captação (28/09/2026)

   Pedro: "precisa pedir as informações certinhas do imóvel para recadastrar
   qualquer coisa, ou se ele mandar um imóvel novo, cadastrar o imóvel novo".

   A Nay monta a FICHA na conversa (captacao_ficha, no banco) e guarda as fotos
   que o dono manda. Aqui um humano confere e decide -- a mesma regra da OLX:
     - imóvel da campanha que ficou disponível -> "Aplicar e pôr no site e na Nay"
     - imóvel novo que o dono ofereceu       -> "Criar pré-cadastro" (Rascunho,
       ligado ao dono), e o editor abre para conferir
   Tudo pelo próprio domínio (/admin/api), atrás da senha do painel.
   ========================================================================== */
(function () {
  "use strict";

  var alvo = document.getElementById("cap-cadastros");
  if (!alvo) return;

  function esc(t) {
    return String(t == null ? "" : t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }
  function fone(t) {
    var d = String(t || "").replace(/\D/g, "");
    if (d.indexOf("55") === 0) d = d.slice(2);
    return d.length === 11 ? "(" + d.slice(0, 2) + ") " + d.slice(2, 7) + "-" + d.slice(7)
         : d.length === 10 ? "(" + d.slice(0, 2) + ") " + d.slice(2, 6) + "-" + d.slice(6) : t;
  }
  var ROTULOS = [
    ["tipo", "Tipo"], ["bairro", "Bairro"], ["condominio", "Condomínio"], ["negocio", "Negócio"],
    ["quartos", "Quartos"], ["suites", "Suítes"], ["banheiros", "Banheiros"], ["vagas", "Vagas"], ["area", "Área"],
    ["valor", "Valor"], ["condominio_valor", "Taxa de condomínio"], ["iptu", "IPTU"], ["incluso", "Incluso no aluguel"],
    ["mobilia", "Mobília"], ["fotos", "Fotos"], ["detalhes", "O que ele contou"]
  ];

  function cartao(c) {
    var d = c.dados || {};
    if (!d.valor && c.tipo === "atualizar" && c.valor_locacao_pedido) d.valor = c.valor_locacao_pedido;
    var quem = [c.tratamento, c.nome].filter(Boolean).join(" ") || "Proprietário";
    var qual = c.tipo === "atualizar"
      ? (c.disponivel ? "Disponível: imóvel " : "Imóvel da campanha: ") + (c.codigo ? '<a href="imovel-editar.html?codigo=' + encodeURIComponent(c.codigo) + '">' + esc(c.codigo) + "</a>" : "(sem código)") +
        esc([" ·", c.imovel_tipo, c.imovel_condominio || c.imovel_bairro].filter(Boolean).join(" ")) +
        (c.imovel_status ? ' <span class="cad__hoje">hoje: ' + esc(c.imovel_status) + "</span>" : "")
      : "Imóvel novo" + (d.negocio ? " (" + esc(String(d.negocio).replace(/loca[cç][aã]o/i, "locação")) + ")" : "");
    var dados = ROTULOS.filter(function (r) { return d[r[0]]; }).map(function (r) {
      return '<div class="cad__dado"><dt>' + r[1] + "</dt><dd>" + esc(d[r[0]]) + "</dd></div>";
    }).join("");
    var fotos = (c.fotos || []).filter(function (u) { return typeof u === "string"; });
    var completa = c.estado === "pronto";
    // o imóvel da campanha só vai ao ar se o dono disse que está disponível; a
    // ficha dele pode existir só porque ele mandou foto antes (a API recusa aplicar)
    var soFotos = c.tipo === "atualizar" && !c.disponivel;
    return '<article class="cad" data-ficha="' + c.id + '">' +
      '<header class="cad__topo"><div><b>' + esc(quem) + '</b> <span class="cad__fone">' + esc(fone(c.telefone)) + "</span>" +
        '<div class="cad__qual">' + qual + "</div></div>" +
        '<span class="cad__estado cad__estado--' + (completa && !soFotos ? "pronto" : "coletando") + '">' +
          (soFotos ? "Não está disponível" : completa ? "Ficha completa" : "A Nay ainda está perguntando") + "</span></header>" +
      (dados ? '<dl class="cad__dados">' + dados + "</dl>" : '<p class="cad__nota">Ainda sem dados.</p>') +
      (fotos.length ? '<div class="cad__fotos">' + fotos.slice(0, 12).map(function (u) {
          return '<a href="' + esc(u) + '" target="_blank" rel="noopener"><img src="' + esc(u) + '" alt="" loading="lazy"></a>';
        }).join("") + (fotos.length > 12 ? '<span class="cad__mais">+' + (fotos.length - 12) + "</span>" : "") + "</div>" : "") +
      (d._origem ? '<p class="cad__nota">' + esc(d._origem) + "</p>" : "") +
      (d._parou ? '<p class="cad__nota">Ele preferiu não responder o resto; a Nay não insistiu.</p>' : "") +
      (soFotos ? '<p class="cad__nota">Ele mandou fotos, mas não disse que o imóvel está disponível: não dá para pôr no ar por aqui.</p>' : "") +
      '<div class="cad__acoes">' +
        (soFotos ? "" : '<button class="btn-azul" type="button" data-aplicar="' + c.id + '">' +
          (c.tipo === "atualizar" ? "Aplicar e pôr no site e na Nay" : "Criar pré-cadastro") + "</button>") +
        '<button class="btn-neutro" type="button" data-descartar="' + c.id + '">Descartar</button>' +
        '<span class="cad__recado" role="status"></span>' +
      "</div></article>";
  }

  function carregar() {
    fetch("api/captacao/cadastros", { credentials: "same-origin" })
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (d) {
        var itens = d.itens || [];
        var titulo = document.getElementById("cap-cadastros-titulo");
        if (titulo) titulo.textContent = "Imóveis vindos da conversa" + (itens.length ? " (" + itens.length + ")" : "");
        alvo.innerHTML = itens.length ? itens.map(cartao).join("")
          : '<p class="cad__nota">Nenhum ainda. Quando um dono disser que o imóvel está disponível, ou oferecer outro imóvel, a ficha aparece aqui.</p>';
      })
      .catch(function () { alvo.innerHTML = '<p class="cad__nota">Não consegui carregar os imóveis da conversa.</p>'; });
  }

  function acao(botao, rota, textoOk) {
    var art = botao.closest(".cad");
    var recado = art.querySelector(".cad__recado");
    art.querySelectorAll("button").forEach(function (b) { b.disabled = true; });
    recado.textContent = "Salvando…";
    fetch(rota, { method: "POST", credentials: "same-origin", headers: { "Content-Type": "application/json" }, body: "{}" })
      .then(function (r) { return r.json().catch(function () { return {}; }).then(function (d) { return { ok: r.ok, d: d }; }); })
      .then(function (res) {
        if (!res.ok) throw new Error(res.d.erro || "erro");
        recado.innerHTML = textoOk(res.d);
        art.classList.add("cad--feito");
      })
      .catch(function (e) {
        recado.textContent = "Não deu certo: " + e.message;
        art.querySelectorAll("button").forEach(function (b) { b.disabled = false; });
      });
  }

  alvo.addEventListener("click", function (e) {
    var a = e.target.closest("[data-aplicar]");
    if (a) {
      acao(a, "api/captacao/cadastros/" + a.getAttribute("data-aplicar") + "/aplicar", function (d) {
        return d.tipo === "atualizar"
          ? "Pronto: o " + esc(d.codigo) + " está disponível, no site e na Nay" + (d.fotos ? " (+" + d.fotos + " fotos)" : "") + "."
          : 'Pré-cadastro criado: <a href="imovel-editar.html?codigo=' + encodeURIComponent(d.codigo) + '">abrir o ' + esc(d.codigo) +
            " para conferir</a>" + (d.fotos ? " (" + d.fotos + " fotos)" : "") + ".";
      });
      return;
    }
    var x = e.target.closest("[data-descartar]");
    if (x) acao(x, "api/captacao/cadastros/" + x.getAttribute("data-descartar") + "/descartar", function () { return "Descartado."; });
  });

  carregar();
  setInterval(carregar, 120000);
})();
