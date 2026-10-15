/* ==========================================================================
   Ver imóvel: popup central, cadastro COMPLETO, papelzinho em cada campo

   Tel (11/10): "transforma a opção ver imovel de uma barra lateral, em um
   popup no meio da tela com todas as informaççoes do imovel bem dividinho
   compactado, todos os campos com um papelzinho dando para copiar"

   Tel (12/10): "não tem todas as informações que tem em editar imovel la em
   ver imovel, no ver tem que ter todas incluindo as do condominio" · "as
   sugestões fiquem sempre la no ultimo quadrado e as fotos no topo" · "nas do
   condominio ve se acha um icone preto demonstrando a categoria para ficar
   junto com o numero" · "onde aparece se o imovel é mobiliado ... faz uma
   barrinha colorida que se completa com estágios"

   POR QUE FORA DO imoveis-ux.js: aquele arquivo tem 90 KB e `abrirFicha()`
   monta a ficha com UMA atribuição de innerHTML de 70 linhas. Aqui eu espero
   a ficha nascer e completo o que nasceu -- um lugar só, e `abrirFicha`
   segue intocado.

   DE ONDE VEM O "TUDO" (as mesmas fontes que a tela de editar usa):
     /api/imoveis/<cod>                 público   -- o imóvel e os `extras`
     /admin/api/imoveis/<cod>/privado   com senha -- torre, dono, locação
     /api/condominios/<cid>/ficha       público   -- a ficha do condomínio
   A fila de fetch é cancelada por código: clicar numa sugestão abre outra
   ficha, e a resposta atrasada da anterior não pode escrever nesta.

   ARMADILHAS QUE DITARAM O DESENHO:

   a) `abrirFicha` escreve a ficha e DEPOIS três fetch() dela enchem
      #ux-ao-redor, #ux-sugestoes e #ux-fotos. Cada resposta acorda o meu
      observer. Por isso `arrumando` corta a reentrância e todo trabalho é
      idempotente (`data-uxp-ok` por campo, `.uxp-corpo` por ficha).

   b) mover nó NÃO muda id: #ux-ao-redor continua achável por
      getElementById depois de entrar no `.uxp-corpo`.

   c) `fecharFicha()` fecha pondo o atributo `hidden`. Nada aqui pode dar
      `display` fixo a `.ux-ficha` -- ver a nota no CSS, que foi exatamente
      o bug do X não funcionar.
   ========================================================================== */
(function () {
  "use strict";

  var API = window.API_BASE || "";

  /* ---- ESPELHO de imovel-editar.js (CAMPOS, linha ~70, e GRUPOS, ~160) ----
     Os rótulos e a divisão em seções moram num IIFE da outra página, que esta
     aqui não enxerga -- não dá para ler, só para copiar. Para a cópia não
     apodrecer calada: todo campo que vier do servidor e não estiver em grupo
     nenhum cai em "Outros" E reclama no console. Some da tela, nunca. */
  var ROTULO = {
    condominio: "Condomínio", logradouro: "Rua / avenida", numero: "Número",
    complemento: "Complemento", bairro: "Bairro", cidade: "Cidade", estado: "Estado",
    cep: "CEP", andar: "Andar",
    "p:torre": "Torre", "p:bloco": "Bloco", "p:unidade": "Apartamento",
    "p:casa": "Número da casa", "p:lote": "Lote",
    "o:nome": "Nome", "o:telefone": "Telefone / WhatsApp", "o:email": "E-mail",
    "o:documento": "CPF ou CNPJ", "o:tratamento": "Tratamento",
    tipo: "Tipo", quartos: "Quartos", suites: "Suítes", banheiros: "Banheiros",
    "x:salas": "Salas", vagas: "Vagas", vagas_cobertas: "Vagas cobertas",
    area_util: "Área útil", area_total: "Área total",
    "x:tamanho do terreno": "Terreno", "x:frente": "Frente", "x:fundo": "Fundo",
    "x:pe direito": "Pé-direito", "x:andares": "Andares", "x:elevadores": "Elevadores",
    "x:lances de escada": "Lances de escada",
    cobertura: "É cobertura", "x:tipo de cobertura": "Tipo da cobertura",
    sol: "Face solar", mobilia: "Mobília", observacao: "Observação do imóvel",
    valor_aluguel: "Aluguel", valor_venda: "Venda",
    taxa_condominio: "Condomínio", iptu: "IPTU",
    "x:aceita financiamento": "Aceita financiamento", "x:permuta": "Permuta",
    "x:incluso no aluguel": "Incluso no aluguel", "x:garantia de aluguel": "Garantia de aluguel",
    descricao: "Descrição do anúncio", caracteristicas: "Características",
    "x:caracteristicas do condominio": "Características do condomínio",
    captado_por: "Captado por", captado_em: "Captado em",
    "x:indicado por": "Indicado por", "x:inspecionado por": "Inspecionado por",
    "p:locatario_nome": "Locatário", "p:locatario_contato": "Contato do locatário",
    "p:vencimento": "Vencimento do contrato", "p:observacao_aluguel": "Observação do aluguel",
    "p:observacoes": "Observações", bloqueado: "Bloqueado para a Nay",
    motivo_bloqueio: "Motivo do bloqueio"
  };

  var GRUPOS = [
    { id: "endereco", titulo: "Condomínio e endereço", icone: "⌖", cor: "#2f6fb8",
      campos: ["condominio", "logradouro", "numero", "complemento", "bairro", "cidade", "estado", "cep"] },
    { id: "unidade", titulo: "Unidade", icone: "⌗", cor: "#4338ca", privado: true,
      campos: ["p:torre", "p:bloco", "p:unidade", "p:casa", "p:lote", "andar", "x:lances de escada"] },
    { id: "carac", titulo: "Características", icone: "⌂", cor: "#6d28d9",
      campos: ["tipo", "quartos", "suites", "banheiros", "x:salas", "vagas", "vagas_cobertas",
               "area_util", "area_total", "x:tamanho do terreno", "x:frente", "x:fundo",
               "x:pe direito", "x:andares", "x:elevadores", "cobertura", "x:tipo de cobertura",
               "sol", "mobilia", "observacao"] },
    { id: "tem", titulo: "O que tem", icone: "✓", cor: "#0e7490", largo: true,
      campos: ["caracteristicas", "x:caracteristicas do condominio"] },
    { id: "valores", titulo: "Valores e negócio", icone: "$", cor: "#c4762f",
      campos: ["valor_aluguel", "valor_venda", "taxa_condominio", "iptu",
               "x:aceita financiamento", "x:permuta", "x:incluso no aluguel", "x:garantia de aluguel"] },
    { id: "descricao", titulo: "Descrição", icone: "✎", cor: "#4b5563", largo: true,
      campos: ["descricao"] },
    { id: "captacao", titulo: "Captação", icone: "✦", cor: "#0f766e",
      campos: ["captado_por", "captado_em", "x:indicado por", "x:inspecionado por"] },
    { id: "locacao", titulo: "Locação atual", icone: "⚿", cor: "#be185d", privado: true,
      campos: ["p:locatario_nome", "p:locatario_contato", "p:vencimento", "p:observacao_aluguel"] },
    { id: "dono", titulo: "Proprietário (cadastro)", icone: "✆", cor: "#0369a1", privado: true,
      campos: ["o:tratamento", "o:nome", "o:telefone", "o:email", "o:documento"] },
    { id: "interno", titulo: "Uso interno", icone: "⚑", cor: "#b42323",
      campos: ["p:observacoes", "bloqueado", "motivo_bloqueio"] },
    { id: "outros", titulo: "Outros", icone: "·", cor: "#6b7280", campos: [] }
  ];

  /* O CONTATO PESSOAL NÃO É IMPRESSO. imoveis-ux.js:783 guarda o dono atrás do
     botão "Ver contato" e escreve na própria ficha: "Contato de proprietário
     nunca vai para corretor" -- e esta mesma tela é servida dentro do CRM,
     onde quem olha é corretor. Então o campo aparece (o Tel vê QUE existe)
     com o valor coberto; o número continua saindo só pelo botão de sempre. */
  var SIGILO = ["o:telefone", "o:email", "o:documento", "p:locatario_contato"];

  var DINHEIRO = ["valor_aluguel", "valor_venda", "taxa_condominio", "iptu"];
  var METRO = ["area_util", "area_total", "x:tamanho do terreno", "x:frente", "x:fundo", "x:pe direito"];

  /* os 4 níveis de mobília (imovel-editar.js:117). Os dois últimos nomes
     também chegam do cadastro antigo escritos de outro jeito, daí os apelidos. */
  var MOBILIA = [
    { nivel: 1, re: /^(sem nada|pelad|sem mob)/i, rotulo: "Sem nada" },
    { nivel: 2, re: /^(s[óo] climatizado|climatizado)/i, rotulo: "Só climatizado" },
    { nivel: 3, re: /(modulados|semi.?mobiliad)/i, rotulo: "Com modulados e ar" },
    { nivel: 4, re: /^mobiliad/i, rotulo: "Mobiliado" }
  ];

  /* ---- ícones pretos do condomínio ------------------------------------
     Tel: "um icone preto mesmo demonstrando a categoria para ficar junto com
     o numero só para diferenciar visualmente". Traço, não preenchimento: num
     tamanho de 13px o ícone cheio vira borrão. */
  function svg(d) {
    return '<svg class="uxp-ic" viewBox="0 0 24 24" fill="none" stroke="currentColor"' +
      ' stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + d + "</svg>";
  }
  var ICONE = {
    torres: svg('<path d="M4 21V7l6-4v18"/><path d="M10 21V11l8-3v13"/><path d="M2 21h20"/>'),
    andares: svg('<path d="M3 20h18"/><path d="M3 15h18"/><path d="M3 10h18"/><path d="M3 5h18"/>'),
    aptos_por_andar: svg('<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/>' +
                         '<rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>'),
    unidades: svg('<path d="M3 11.5 12 4l9 7.5"/><path d="M5 10v10h14V10"/><path d="M10 20v-6h4v6"/>'),
    elevador: svg('<rect x="4" y="3" width="16" height="18" rx="2"/><path d="M12 3v18"/>' +
                  '<path d="m8 9 1.6-2L11 9"/><path d="m13 15 1.6 2 1.4-2"/>'),
    elevadores: svg('<rect x="4" y="3" width="16" height="18" rx="2"/><path d="M12 3v18"/>' +
                    '<path d="m8 9 1.6-2L11 9"/><path d="m13 15 1.6 2 1.4-2"/>'),
    ano: svg('<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M8 3v4M16 3v4M3 11h18"/>'),
    construtora: svg('<path d="M3 17h18"/><path d="M5 17a7 7 0 0 1 14 0"/><path d="M12 3v3"/><path d="m7.5 6 1.5 2M16.5 6 15 8"/>'),
    revestimento: svg('<rect x="3" y="4" width="18" height="7" rx="1"/><rect x="3" y="13" width="8" height="7" rx="1"/>' +
                      '<rect x="13" y="13" width="8" height="7" rx="1"/>'),
    tipo: svg('<path d="M3 11.5 12 4l9 7.5"/><path d="M5 10v10h14V10"/>'),
    taxas: svg('<path d="M12 2v20"/><path d="M17 6.5c0-1.9-2.2-3-5-3s-5 1.1-5 3 2.2 2.6 5 3 5 1.3 5 3.2-2.2 3.3-5 3.3-5-1.2-5-3.1"/>'),
    lazer: svg('<circle cx="12" cy="12" r="9"/><path d="M12 3a9 9 0 0 0 0 18"/><path d="M3 12h18"/>'),
    seguranca: svg('<path d="M12 3 5 6v6c0 4.2 2.9 7.8 7 9 4.1-1.2 7-4.8 7-9V6z"/>'),
    comodidades: svg('<path d="M20 7h-9"/><path d="M14 17H5"/><circle cx="17" cy="17" r="3"/><circle cx="7" cy="7" r="3"/>'),
    endereco: svg('<path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0z"/><circle cx="12" cy="10" r="3"/>')
  };

  /* ---- utilidades ------------------------------------------------------ */
  function esc(t) {
    return String(t == null ? "" : t).replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }
  function vazio(v) {
    return v == null || v === "" || (Array.isArray(v) && !v.length) ||
           (typeof v === "object" && !Array.isArray(v) && !Object.keys(v).length);
  }
  function brl(n) {
    var x = Number(String(n).replace(/[^\d.,-]/g, "").replace(/\./g, "").replace(",", "."));
    if (!isFinite(x) || !x) return null;
    return "R$ " + x.toLocaleString("pt-BR", { minimumFractionDigits: 0, maximumFractionDigits: 2 });
  }
  function dataBr(v) {
    var s = String(v);
    if (/^\d{4}-\d{2}-\d{2}/.test(s)) return s.slice(0, 10).split("-").reverse().join("/");
    return s;
  }

  function nivelMobilia(v) {
    var s = String(v || "").trim();
    if (!s) return null;
    for (var i = 0; i < MOBILIA.length; i++) if (MOBILIA[i].re.test(s)) return MOBILIA[i];
    return null;
  }

  /* a barrinha: 4 quadradinhos, tantos pintados quanto o nível.
     Tel: "mobiliado tem [4] quadradnhos os 4 pintados, e se for pelada é só
     1 quadradinho" -- então "sem nada" NÃO é zero, é um.

     Quem manda na escala é `mobilia-barra.js`, que o editar imóvel usa também:
     a mesma barra nas duas telas, uma definição só. O desenho de reserva
     abaixo é para o caso de aquele arquivo não ter carregado -- o campo não
     pode virar um branco por causa de um <script> que faltou. */
  function barraMobilia(v) {
    if (window.MobiliaBarra && window.MobiliaBarra.html) {
      return nivelMobilia(v) ? window.MobiliaBarra.html(v) : null;
    }
    var m = nivelMobilia(v);
    if (!m) return null;
    var q = "";
    for (var i = 1; i <= 4; i++) {
      q += '<i class="uxp-mb__q' + (i <= m.nivel ? " uxp-mb__q--on" : "") + '"></i>';
    }
    return '<span class="uxp-mb" data-nivel="' + m.nivel + '" title="' + esc(m.rotulo) +
      ' (' + m.nivel + ' de 4)">' + q + "</span>" +
      '<span class="uxp-mb__txt">' + esc(m.rotulo) + "</span>";
  }

  /* o valor de um campo, pelas mesmas regras de `valorGuardado`
     (imovel-editar.js): "x:" vem de `extras`, "p:" do privado, "o:" do
     proprietário dentro do privado, o resto do próprio imóvel. */
  function valorDe(nome, d) {
    if (nome.slice(0, 2) === "x:") return (d.item.extras || {})[nome.slice(2)];
    if (nome.slice(0, 2) === "p:") return d.privado ? d.privado[nome.slice(2)] : null;
    if (nome.slice(0, 2) === "o:") {
      return d.privado && d.privado.proprietario ? d.privado.proprietario[nome.slice(2)] : null;
    }
    if (nome === "condominio") return d.item.condominio_nome;
    return d.item[nome];
  }

  function textoDoValor(nome, v) {
    if (Array.isArray(v)) return v.join(", ");
    if (typeof v === "boolean") return v ? "Sim" : "Não";
    if (DINHEIRO.indexOf(nome) >= 0) return brl(v);
    if (METRO.indexOf(nome) >= 0) return String(v) + " m²";
    if (nome === "captado_em" || nome === "p:vencimento") return dataBr(v);
    if (typeof v === "object") return Object.keys(v).map(function (k) { return k + ": " + v[k]; }).join(" · ");
    return String(v);
  }

  /* ---- montagem dos blocos --------------------------------------------- */
  function celula(rotulo, html, extra) {
    return "<div" + (extra || "") + "><b>" + esc(rotulo) + "</b>" + html + "</div>";
  }

  function blocoHtml(g, pares) {
    if (!pares.length) return "";
    return '<div class="ux-bloco" data-uxp="g:' + g.id + '" style="--uxp-cor:' + g.cor + '">' +
      "<h3><span class=\"uxp-gi\">" + g.icone + "</span>" + esc(g.titulo) +
      (g.privado ? ' <span class="uxp-priv">interno</span>' : "") + "</h3>" +
      '<div class="ux-dois' + (g.largo ? " ux-dois--largo" : "") + '">' + pares.join("") + "</div></div>";
  }

  function blocosDoImovel(d) {
    var usados = {}, html = "", sobrou = [];

    GRUPOS.forEach(function (g) {
      var pares = [];
      g.campos.forEach(function (nome) {
        usados[nome] = 1;
        var v = valorDe(nome, d);
        if (vazio(v)) return;

        if (SIGILO.indexOf(nome) >= 0) {
          pares.push(celula(ROTULO[nome] || nome,
            '<span class="uxp-sig">•••••• <small>no botão “Ver contato”</small></span>',
            ' data-uxp-ok="1"'));           // sem papelzinho: não há o que copiar
          return;
        }
        if (nome === "mobilia") {
          // sem `data-uxp-ok`: o papelzinho fica, e `textoLimpo` tira os
          // quadradinhos antes de copiar -- vai só "Mobiliado"
          var barra = barraMobilia(v);
          if (barra) { pares.push(celula(ROTULO[nome], barra)); return; }
        }
        var t = textoDoValor(nome, v);
        if (!t) return;
        pares.push(celula(ROTULO[nome] || nome, esc(t)));
      });
      html += blocoHtml(g, pares);
    });

    // nada se perde: campo novo no servidor cai em "Outros" e avisa
    var todos = {};
    Object.keys(d.item || {}).forEach(function (k) { todos[k] = d.item[k]; });
    Object.keys((d.item || {}).extras || {}).forEach(function (k) { todos["x:" + k] = d.item.extras[k]; });
    var IGNORAR = ["codigo", "extras", "campos_editaveis", "extras_editaveis", "condo_id",
                   "condominio_nome", "status", "disponivel", "publicado_no_site", "e_parceiro",
                   "criado_em", "sincronizado_em"];
    Object.keys(todos).forEach(function (k) {
      if (usados[k] || IGNORAR.indexOf(k) >= 0 || vazio(todos[k])) return;
      sobrou.push(celula(ROTULO[k] || k, esc(textoDoValor(k, todos[k]) || "")));
      if (!blocosDoImovel._avisou) {
        console.warn("[ficha-popup] campo fora dos GRUPOS (alinhe com imovel-editar.js): " + k);
      }
    });
    if (sobrou.length) {
      blocosDoImovel._avisou = true;
      html += blocoHtml(GRUPOS[GRUPOS.length - 1], sobrou);
    }
    return html;
  }

  /* a ficha do condomínio, com o ícone preto colado no número */
  function blocoDoCondominio(c) {
    if (!c || !c.id) return "";
    var numeros = [
      ["torres", "Torres", c.torres], ["andares", "Andares", c.andares],
      ["aptos_por_andar", "Apartamentos por andar", c.aptos_por_andar],
      ["unidades", "Unidades", c.unidades], ["elevador", "Elevador", c.elevador],
      ["ano", "Ano de construção", c.ano], ["construtora", "Construtora", c.construtora],
      ["revestimento", "Revestimento", c.revestimento]
    ].filter(function (p) { return !vazio(p[2]); }).map(function (p) {
      return celula(p[1], (ICONE[p[0]] || "") + '<span class="uxp-vl">' + esc(String(p[2])) + "</span>");
    });

    var endereco = [c.logradouro, c.numero && "nº " + c.numero, c.complemento,
                    c.bairro, c.cidade, c.estado, c.cep].filter(Boolean).join(", ");
    if (endereco) {
      numeros.unshift(celula("Endereço do condomínio",
        ICONE.endereco + '<span class="uxp-vl">' + esc(endereco) + "</span>", ' class="uxp-largo"'));
    }

    [["lazer", "Lazer", c.lazer], ["seguranca", "Segurança", c.seguranca],
     ["comodidades", "Comodidades", c.comodidades]].forEach(function (p) {
      if (vazio(p[2])) return;
      numeros.push(celula(p[1], (ICONE[p[0]] || "") + '<span class="uxp-vl">' +
        esc((p[2] || []).join(", ")) + "</span>", ' class="uxp-largo"'));
    });

    if (Array.isArray(c.taxas) && c.taxas.length) {
      numeros.push(celula("Taxas", ICONE.taxas + '<span class="uxp-vl">' +
        esc(c.taxas.map(function (t) {
          var quem = t.quartos != null ? t.quartos + " quartos" : (t.metragem ? t.metragem + " m²" : "—");
          return quem + ": " + [t.condominio && brl(t.condominio), t.iptu && "IPTU " + brl(t.iptu)]
            .filter(Boolean).join(" · ");
        }).join(" | ")) + "</span>", ' class="uxp-largo"'));
    }
    if (!vazio(c.taxa_inclui)) {   // 367: o que está incluso na taxa de condomínio
      numeros.push(celula("Incluso na taxa de condomínio", (ICONE.taxas || "") + '<span class="uxp-vl">' +
        esc(c.taxa_inclui.join(", ")) + "</span>", ' class="uxp-largo"'));
    }
    if (c.observacao) {
      numeros.push(celula("Observação do condomínio", esc(c.observacao), ' class="uxp-largo"'));
    }
    if (!numeros.length) return "";

    return '<div class="ux-bloco" data-uxp="g:condominio" style="--uxp-cor:#2f6fb8">' +
      '<h3><span class="uxp-gi">▤</span>Condomínio: ' + esc(c.nome || "") + "</h3>" +
      '<div class="ux-dois">' + numeros.join("") + "</div></div>";
  }

  /* ---- busca ----------------------------------------------------------- */
  var pedido = 0;

  function json(r) { return r.ok ? r.json() : Promise.reject(r.status); }

  function completar(codigo) {
    var meu = ++pedido;
    var f = document.getElementById("ux-ficha");
    if (!f) return;

    Promise.all([
      fetch(API + "/api/imoveis/" + encodeURIComponent(codigo)).then(json),
      // sem senha devolve 401: a tela segue sem os blocos internos
      fetch("api/imoveis/" + encodeURIComponent(codigo) + "/privado", { credentials: "same-origin" })
        .then(json).catch(function () { return null; })
    ]).then(function (r) {
      var item = r[0] || {};
      if (!item.condo_id) return [item, r[1], null];
      return fetch(API + "/api/condominios/" + encodeURIComponent(item.condo_id) + "/ficha")
        .then(json).catch(function () { return null; })
        .then(function (c) { return [item, r[1], c]; });
    }).then(function (r) {
      // resposta atrasada de OUTRO imóvel não escreve nesta ficha
      if (meu !== pedido || f.hidden || String(f.dataset.codigo) !== String(codigo)) return;
      var corpo = f.querySelector(".uxp-corpo");
      if (!corpo) return;

      var html = blocosDoImovel({ item: r[0], privado: r[1] }) + blocoDoCondominio(r[2]);
      if (!html) return;

      /* os blocos entram DIRETO em `.uxp-corpo`, sem embrulho. Um `<div>` por
         volta deles com `display:contents` até funcionaria no layout, mas as
         regras de ordem são `.uxp-corpo > [data-uxp=...]` -- `display` muda o
         desenho, não o parentesco, e os blocos ficariam fora de ordem. */
      var velhos = corpo.querySelectorAll("[data-uxp-completo]");
      for (var v = 0; v < velhos.length; v++) velhos[v].remove();

      var caixa = document.createElement("div");
      caixa.innerHTML = html;
      while (caixa.firstElementChild) {
        var bl = caixa.firstElementChild;
        bl.setAttribute("data-uxp-completo", String(codigo));
        corpo.appendChild(bl);
      }
      // os campos novos precisam do papelzinho AGORA. Não dá para esperar só
      // o observer: `completar` é chamada de dentro de `arrumar`, e se a
      // resposta vier em microtarefa (cache, mock) ela chega antes de
      // `arrumando` voltar a false -- a passada seria descartada.
      arrumarLogo();

      /* só AGORA tiro o bloco curto que `abrirFicha` escreve: as 6
         características dele são um subconjunto do que acabou de entrar.
         Se a busca tivesse falhado, ele continuaria lá. */
      var curto = corpo.querySelector('.ux-bloco[data-uxp="caracteristicas"]');
      if (curto) curto.remove();
    }).catch(function (e) {
      if (meu === pedido) console.warn("[ficha-popup] não consegui completar a ficha:", e);
    });
  }

  /* ---- papelzinho ------------------------------------------------------ */
  var PAPEL =
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"' +
    ' stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
    '<rect x="9" y="9" width="11" height="11" rx="2"/>' +
    '<path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>';
  var CERTO =
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"' +
    ' stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
    '<path d="M20 6 9 17l-5-5"/></svg>';
  var VAZIO = ["", "—", "-", "–", "Consulte"];

  function semAcento(t) {
    return String(t || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
  }
  function nomeDoBloco(h3) {
    var t = semAcento(h3 && h3.textContent);
    if (/oferta/.test(t)) return "oferta";
    if (/caracteristica/.test(t)) return "caracteristicas";
    if (/^datas/.test(t)) return "datas";
    if (/proprietario/.test(t)) return "proprietario";
    if (/ao redor/.test(t)) return "ao-redor";
    if (/sugest/.test(t)) return "sugestoes";
    if (/^fotos/.test(t)) return "fotos";
    return "";
  }

  function textoLimpo(no, tiraRotulo) {
    var c = no.cloneNode(true), i;
    // tira o botão, os ícones e os QUADRADINHOS da barra -- o rótulo do
    // estágio (.mb__t) fica, para copiar "Mobiliado" e não uma linha vazia
    var fora = c.querySelectorAll(".uxp-copiar, .uxp-ic, .uxp-mb, .mb__q");
    for (i = 0; i < fora.length; i++) fora[i].remove();
    if (tiraRotulo) {
      var r = c.querySelectorAll("b, .sub, h3, .ux-dica");
      for (i = 0; i < r.length; i++) r[i].remove();
    }
    var brs = c.querySelectorAll("br");
    for (i = 0; i < brs.length; i++) brs[i].replaceWith(document.createTextNode("\n"));
    return String(c.textContent || "")
      .replace(/[ \t ]+/g, " ").replace(/ ?\n ?/g, "\n").trim();
  }

  function copiar(txt, botao) {
    function deuCerto() {
      botao.innerHTML = CERTO;
      botao.classList.add("uxp-copiar--ok");
      botao.setAttribute("aria-label", "Copiado");
      clearTimeout(botao._t);
      botao._t = setTimeout(function () {
        botao.innerHTML = PAPEL;
        botao.classList.remove("uxp-copiar--ok");
        botao.setAttribute("aria-label", botao.dataset.uxpRotulo || "Copiar");
      }, 1300);
    }
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(txt).then(deuCerto, function () { velho(txt, deuCerto); });
    } else { velho(txt, deuCerto); }
  }
  function velho(txt, ok) {
    try {
      var a = document.createElement("textarea");
      a.value = txt; a.setAttribute("readonly", "");
      a.style.cssText = "position:fixed;top:-100px;opacity:0";
      document.body.appendChild(a); a.select();
      var deu = document.execCommand("copy");
      document.body.removeChild(a);
      if (deu) ok();
    } catch (e) { /* sem clipboard: o campo continua selecionável à mão */ }
  }

  function porBotao(alvo, rotulo, valor) {
    if (!alvo || alvo.dataset.uxpOk) return;
    alvo.dataset.uxpOk = "1";
    if (!valor || VAZIO.indexOf(valor) >= 0) return;
    var b = document.createElement("button");
    b.type = "button";
    b.className = "uxp-copiar";
    b.innerHTML = PAPEL;
    b.dataset.uxpRotulo = "Copiar " + (rotulo || "campo").toLowerCase();
    b.setAttribute("aria-label", b.dataset.uxpRotulo);
    b.title = b.dataset.uxpRotulo;
    b.dataset.uxpValor = valor;
    alvo.appendChild(b);
  }
  function embrulhar(no) {
    if (no && !no.classList.contains("uxp-campo")) no.classList.add("uxp-campo");
    return no;
  }

  /* ---- arrumação ------------------------------------------------------- */
  var arrumando = false;

  function arrumar() {
    var f = document.getElementById("ux-ficha");
    if (!f || f.hidden || arrumando) return;
    var topo = f.querySelector(".ux-ficha__topo");
    if (!topo) return;

    arrumando = true;
    try {
      f.setAttribute("role", "dialog");
      f.setAttribute("aria-modal", "true");

      var corpo = f.querySelector(".uxp-corpo");
      if (!corpo) {
        corpo = document.createElement("div");
        corpo.className = "uxp-corpo";
        while (topo.nextSibling) corpo.appendChild(topo.nextSibling);
        f.appendChild(corpo);

        var rodape = document.createElement("div");
        rodape.className = "uxp-rodape";
        var fim = [];
        for (var n = corpo.lastElementChild; n; n = n.previousElementSibling) {
          if (n.classList.contains("ux-bloco")) break;
          fim.unshift(n);
        }
        if (fim.length) {
          corpo.appendChild(rodape);
          for (var k = 0; k < fim.length; k++) rodape.appendChild(fim[k]);
        }
        corpo.scrollTop = 0;
      }

      var blocos = corpo.querySelectorAll(".ux-bloco:not([data-uxp])");
      for (var i = 0; i < blocos.length; i++) {
        var nome = nomeDoBloco(blocos[i].querySelector("h3"));
        if (nome) blocos[i].setAttribute("data-uxp", nome);
      }

      var pares = corpo.querySelectorAll(".ux-dois > div:not([data-uxp-ok])");
      for (var p = 0; p < pares.length; p++) {
        var rot = pares[p].querySelector("b");
        porBotao(pares[p], rot ? rot.textContent : "", textoLimpo(pares[p], true));
      }

      var cod = topo.querySelector(".etiqueta--azul-suave");
      if (cod && !cod.dataset.uxpOk) {
        porBotao(embrulhar(cod), "código", textoLimpo(cod, false).replace(/^C[óo]d\.\s*/i, ""));
      }
      var h2 = topo.querySelector("h2");
      if (h2 && !h2.dataset.uxpOk) porBotao(embrulhar(h2), "nome", textoLimpo(h2, false));
      var ender = topo.querySelector(".ux-dica");
      if (ender && !ender.dataset.uxpOk) porBotao(embrulhar(ender), "endereço", textoLimpo(ender, false));

      var bd = corpo.querySelector('[data-uxp="datas"]');
      if (bd && !bd.dataset.uxpOk) porBotao(embrulhar(bd), "data", textoLimpo(bd, true));

      var bp = corpo.querySelector('[data-uxp="proprietario"] p:not(.ux-dica)');
      if (bp && !bp.dataset.uxpOk) porBotao(embrulhar(bp), "proprietário", textoLimpo(bp, false));

      // a ficha completa: uma busca por imóvel aberto.
      // o try é de propósito: a busca é um EXTRA. Se ela estourar na cara
      // (sem fetch, CSP, o que for), o popup tem de continuar funcionando com
      // o que `abrirFicha` já escreveu -- e, pior, uma exceção aqui subiria
      // por `arrumar` e deixaria a tela sem a arrumação daí em diante.
      var codigo = f.dataset.codigo;
      if (codigo && corpo.getAttribute("data-uxp-busca") !== String(codigo)) {
        corpo.setAttribute("data-uxp-busca", String(codigo));
        try { completar(codigo); }
        catch (e) { console.warn("[ficha-popup] não consegui buscar o cadastro:", e); }
      }
    } finally {
      setTimeout(function () { arrumando = false; }, 0);
    }
  }

  document.addEventListener("click", function (e) {
    var b = e.target && e.target.closest && e.target.closest(".uxp-copiar");
    if (!b) return;
    e.preventDefault();
    e.stopPropagation();
    copiar(b.dataset.uxpValor || "", b);
  }, true);

  /* junta as rajadas: `abrirFicha` escreve uma vez, os três fetch() dela
     escrevem depois, a busca daqui escreve de novo, e o "copiado" do botão
     também mexe no DOM.
     SEMPRE agenda, mesmo com `arrumando` ligado -- quem corta a reentrância é
     o guarda dentro de `arrumar`. Sair daqui mais cedo perdia a passada
     quando a mutação era a minha própria e a seguinte vinha logo atrás. */
  var relogio;
  function arrumarLogo() {
    clearTimeout(relogio);
    relogio = setTimeout(arrumar, 50);
  }

  function ligar() {
    var f = document.getElementById("ux-ficha");
    if (!f) return;            // esta página não tem a ficha (imoveis.html público)
    /* o observer PRIMEIRO, a primeira passada depois. Na ordem inversa, uma
       exceção na primeira passada impedia o observer de ser instalado, e daí
       em diante nenhuma ficha era arrumada -- falha silenciosa e permanente,
       que só apareceu porque o jsdom não tem `fetch`. */
    if (window.MutationObserver) {
      new MutationObserver(arrumarLogo).observe(f, {
        childList: true, subtree: true, attributes: true, attributeFilter: ["hidden"] });
    }
    arrumar();
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", ligar);
  else ligar();
})();
