/* ==========================================================================
   Imob Easy — Visualização de uma lista (tela cheia)

   A lista salva no banco é uma fotografia com poucos campos. A API completa
   ela na leitura com o que veio do admin real (endereço, situação atual,
   contato do proprietário, outros imóveis dele). Aqui a gente só desenha.
   ========================================================================== */
(function () {
  "use strict";

  var params = new URLSearchParams(window.location.search);
  var id = params.get("id");

  var titulo = document.getElementById("titulo-lista");
  var subtitulo = document.getElementById("subtitulo-lista");
  var acoes = document.getElementById("acoes-lista");
  var cabecalho = document.getElementById("cabecalho-lista");
  var corpo = document.getElementById("corpo-lista");
  var painel = document.getElementById("painel-whatsapp");
  var sobrepor = document.getElementById("sobrepor-lead");
  var leadTitulo = document.getElementById("lead-titulo");
  var leadCorpo = document.getElementById("lead-corpo");

  function esc(txt) {
    return String(txt == null ? "" : txt)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }

  function formatarData(iso) {
    var d = new Date(iso);
    return d.toLocaleDateString("pt-BR") + " " +
           d.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" });
  }

  /* ---- Colunas -----------------------------------------------------------
     Ordem fixa pro que a gente conhece; qualquer campo novo que a API passe
     a mandar entra no fim sozinho, sem precisar mexer aqui. */
  var ORDEM = [
    // identificacao e localizacao
    "codigo", "tipo", "endereco", "bairro", "condominio", "andar",
    // o imovel
    "area", "quartos", "suites", "banheiros", "vagas", "caracteristicas",
    // o contrato
    "valor_aluguel", "garantia_aluguel", "incluso_no_aluguel",
    "vencimento_conferido", "vencimento", "status_admin", "status",
    // historico
    "captado_em", "visitas_30d",
    // o lead
    "proprietario_nome", "proprietario_telefone", "proprietario_email",
    "etapa_proprietario", "etapa_desde",
    "prop_qtd_imoveis", "prop_outros_imoveis",
  ];
  var ROTULOS = {
    codigo: "Código", tipo: "Tipo", endereco: "Endereço", bairro: "Bairro",
    condominio: "Condomínio", vencimento: "Vencimento (na lista)",
    vencimento_conferido: "Vencimento", status_admin: "Imóvel hoje",
    status: "Status de renovação", valor_aluguel: "Aluguel",
    proprietario_nome: "Proprietário", proprietario_telefone: "Telefone",
    proprietario_email: "E-mail", prop_qtd_imoveis: "Imóveis do proprietário",
    prop_outros_imoveis: "Outros imóveis dele",
    nome: "Nome", telefone: "Telefone", email: "E-mail",
    ultima_interacao: "Última interação",
    andar: "Andar", area: "Área", quartos: "Quartos", suites: "Suítes",
    banheiros: "Banheiros", vagas: "Vagas", caracteristicas: "Mobília",
    garantia_aluguel: "Garantia", incluso_no_aluguel: "Incluso no aluguel",
    captado_em: "Captado em", visitas_30d: "Visitas (30d)",
    etapa_proprietario: "Etapa no CRM", etapa_desde: "Etapa desde",
  };
  var OCULTAS = ["proprietario_id"];

  function ordenarColunas(itens) {
    var presentes = {};
    itens.forEach(function (i) { Object.keys(i).forEach(function (k) { presentes[k] = true; }); });
    OCULTAS.forEach(function (k) { delete presentes[k]; });

    /* A lista guarda o vencimento congelado e a API traz o conferido no admin.
       Quando batem em todas as linhas -- que é o normal -- mostrar as duas
       colunas é só ruído. A congelada só aparece se houver divergência,
       que é justamente quando ela importa. */
    var divergiu = itens.some(function (i) {
      return i.vencimento && i.vencimento_conferido && i.vencimento !== i.vencimento_conferido;
    });
    if (presentes.vencimento_conferido && !divergiu) delete presentes.vencimento;
    var cols = ORDEM.filter(function (c) { return presentes[c]; });
    Object.keys(presentes).forEach(function (c) {
      if (cols.indexOf(c) === -1) cols.push(c);
    });
    return cols;
  }

  var VAZIO = '<span style="color:var(--texto-fraco)">—</span>';

  function formatarCelula(coluna, valor, item) {
    if (valor == null || valor === "" || valor === "—") return VAZIO;

    if (coluna === "codigo") {
      return '<a href="imovel-editar.html?codigo=' + esc(valor) + '">#' + esc(valor) + "</a>";
    }
    if (/^vencimento/.test(coluna) && /^\d{4}-\d{2}-\d{2}/.test(valor)) {
      var d = new Date(valor + "T00:00:00");
      var atrasado = d < new Date(new Date().toDateString());
      var txt = d.toLocaleDateString("pt-BR");
      return atrasado
        ? '<span style="color:var(--vermelho);font-weight:600">' + esc(txt) + "</span>"
        : esc(txt);
    }
    if (coluna === "status_admin") {
      var cor = valor === "Alugado" ? "verde" : "laranja";
      return '<span class="etiqueta etiqueta--' + cor + '">' + esc(valor) + "</span>";
    }
    if (coluna === "proprietario_telefone" || coluna === "telefone") {
      var zap = linkWhatsapp(valor);
      return '<a href="tel:' + esc(valor.replace(/\D/g, "")) + '">' + esc(valor) + "</a>" +
             (zap ? ' <a href="' + esc(zap.url) + '" target="_blank" rel="noopener" ' +
                    'title="Abrir no WhatsApp" style="text-decoration:none">💬</a>' : "");
    }
    if (coluna === "proprietario_email" || coluna === "email") {
      return '<a href="mailto:' + esc(valor) + '">' + esc(valor) + "</a>";
    }
    if (coluna === "prop_outros_imoveis") {
      return String(valor).split(/,\s*/).map(function (c) {
        return '<a href="imovel-editar.html?codigo=' + esc(c) + '">#' + esc(c) + "</a>";
      }).join(" ");
    }
    if (coluna === "captado_em" || coluna === "etapa_desde") {
      var dt = new Date(valor + "T00:00:00");
      var anos = (Date.now() - dt) / 31557600000;
      var rot = dt.toLocaleDateString("pt-BR");
      /* Mais de 3 anos parado e' sinal de cadastro esquecido -- vale o
         destaque, porque muda a ordem de quem ligar primeiro. */
      return anos >= 3
        ? esc(rot) + ' <span style="color:var(--texto-fraco)">(' +
          Math.floor(anos) + " anos)</span>"
        : esc(rot);
    }
    if (coluna === "area") {
      return esc(String(valor).replace(".", ",")) + " m²";
    }
    if (coluna === "etapa_proprietario") {
      var neutro = ["Arquivado", "Sem Especialista", "Sem Retorno"].indexOf(valor) !== -1;
      return '<span class="etiqueta etiqueta--' + (neutro ? "laranja" : "azul") + '">' +
             esc(valor) + "</span>";
    }
    if (coluna === "valor_aluguel") {
      var n = Number(valor);
      return isNaN(n) ? esc(valor)
        : "R$ " + n.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    }
    return esc(valor);
  }

  /* ---- WhatsApp ----------------------------------------------------------
     Formato pedido: https://api.whatsapp.com/send/?phone=55DDDNUMERO

     Número de 11 dígitos (DDD + 9 dígitos) é celular atual e funciona. O de
     10 dígitos é do formato antigo, de antes do nono dígito. NÃO inserimos o
     9 automaticamente: um palpite errado abre conversa com outra pessoa. O
     link é gerado como está e a linha sai marcada pra conferência. */
  function linkWhatsapp(telefone) {
    if (!telefone) return null;
    var d = String(telefone).replace(/\D/g, "");
    if (d.length < 10) return null;
    return {
      url: "https://api.whatsapp.com/send/?phone=55" + d,
      conferir: d.length === 10,
    };
  }

  function copiar(texto, quantos) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(texto)
        .then(function () { alert(quantos + " link(s) copiado(s)."); })
        .catch(function () { prompt("Copie abaixo:", texto); });
    } else {
      prompt("Copie abaixo:", texto);
    }
  }

  /* ---- Ficha do lead --------------------------------------------------
     Clicar na linha abre tudo que se sabe daquele imovel e daquele dono. A
     tabela tem 28 colunas e rola na horizontal, entao nome e telefone ficam
     fora da tela -- aqui aparece tudo de uma vez, sem precisar arrastar. */
  var MOEDA = ["valor_aluguel", "valor_venda", "taxa_condominio", "iptu"];
  var LARGOS = ["observacoes", "observacao_aluguel", "caracteristicas", "incluso"];
  var NOMES = {
    codigo: "Código", tipo: "Tipo", status: "Situação do imóvel",
    condominio: "Condomínio", logradouro: "Logradouro", numero: "Número",
    bloco: "Bloco", casa: "Casa", torre: "Torre", apartamento: "Apartamento",
    andar: "Andar", cep: "CEP", bairro: "Bairro", cidade: "Cidade", estado: "Estado",
    area: "Área útil", terreno: "Tamanho do terreno", area_construida: "Área construída",
    quartos: "Quartos", suites: "Suítes", banheiros: "Banheiros", vagas: "Vagas",
    vagas_cobertas: "Vagas cobertas", lances_escada: "Lances de escada", sol: "Sol",
    caracteristicas: "Características", observacoes: "Observações",
    inspecionado_por: "Inspecionado por", captado_em: "Captado em",
    visitas_30d: "Visitas (30 dias)",
    vencimento: "Contrato válido até", valor_aluguel: "Valor do aluguel",
    valor_venda: "Valor de venda", taxa_condominio: "Taxa de condomínio", iptu: "IPTU",
    garantia: "Garantia", incluso: "Incluso no aluguel",
    financiamento: "Aceita financiamento", observacao_aluguel: "Observação de aluguel",
    locatario_nome: "Nome do locatário", locatario_contato: "Contato do locatário",
    id: "ID no admin", nome: "Nome", telefone: "Telefone", email: "E-mail",
    cpf: "CPF", corretor: "Corretor responsável", etapa: "Etapa no CRM",
    etapa_em: "Nessa etapa desde", cadastrado_em: "Cadastrado em",
    qtd_imoveis: "Imóveis do proprietário"
  };

  function valorFicha(chave, v) {
    if (v === null || v === undefined || v === "") return null;
    if (MOEDA.indexOf(chave) !== -1) {
      return "R$ " + Number(v).toLocaleString("pt-BR",
        { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    }
    if (/^(vencimento|captado_em|etapa_em|cadastrado_em)$/.test(chave) &&
        /^\d{4}-\d{2}-\d{2}$/.test(v)) {
      return new Date(v + "T00:00:00").toLocaleDateString("pt-BR");
    }
    if (chave === "area" || chave === "terreno" || chave === "area_construida") {
      return String(v).replace(".", ",") + " m²";
    }
    if (chave === "telefone" || chave === "locatario_contato") {
      var z = linkWhatsapp(v);
      return esc(v) + (z ? ' <a href="' + esc(z.url) + '" target="_blank" rel="noopener" ' +
                           'title="Abrir no WhatsApp" style="text-decoration:none">💬</a>' : "");
    }
    if (chave === "email") return '<a href="mailto:' + esc(v) + '">' + esc(v) + "</a>";
    return esc(v);
  }

  /* O Flask devolve o JSON com as chaves em ordem alfabetica, o que joga
     "Etapa no CRM" na frente de "Nome". A ordem de leitura vem daqui; campo
     que nao esteja na lista entra no fim. */
  var ORDEM_FICHA = [
    // proprietario
    "nome", "telefone", "email", "cpf", "corretor", "etapa", "etapa_em",
    "cadastrado_em", "qtd_imoveis", "id",
    // contrato
    "vencimento", "valor_aluguel", "garantia", "incluso", "taxa_condominio",
    "iptu", "valor_venda", "financiamento",
    "locatario_nome", "locatario_contato", "observacao_aluguel",
    // imovel
    "status", "tipo", "condominio", "logradouro", "numero", "bloco", "casa",
    "torre", "apartamento", "andar", "bairro", "cidade", "estado", "cep",
    "area", "terreno", "area_construida", "quartos", "suites", "banheiros",
    "vagas", "vagas_cobertas", "lances_escada", "sol", "caracteristicas",
    "observacoes", "captado_em", "inspecionado_por", "visitas_30d"
  ];

  function secaoFicha(titulo, obj, pular) {
    var campos = Object.keys(obj).filter(function (k) {
      return (pular || []).indexOf(k) === -1 &&
             obj[k] !== null && obj[k] !== undefined && obj[k] !== "";
    });
    campos.sort(function (a, b) {
      var ia = ORDEM_FICHA.indexOf(a), ib = ORDEM_FICHA.indexOf(b);
      if (ia === -1) ia = 999;
      if (ib === -1) ib = 999;
      return ia - ib || a.localeCompare(b);
    });
    if (!campos.length) {
      return '<div class="lead-secao"><div class="lead-secao__titulo">' + esc(titulo) +
             '</div><p class="lead-vazio">Nada preenchido no admin.</p></div>';
    }
    return '<div class="lead-secao"><div class="lead-secao__titulo">' + esc(titulo) + "</div>" +
      '<dl class="lead-campos">' + campos.map(function (k) {
        var largo = LARGOS.indexOf(k) !== -1 ? " lead-campo--largo" : "";
        return '<div class="lead-campo' + largo + '"><dt>' + esc(NOMES[k] || k) + "</dt>" +
               "<dd>" + valorFicha(k, obj[k]) + "</dd></div>";
      }).join("") + "</dl></div>";
  }

  function abrirLead(codigo) {
    sobrepor.hidden = false;
    leadTitulo.textContent = "Lead #" + codigo;
    leadCorpo.innerHTML = "Carregando...";
    fetch(window.API_BASE + "/api/lead/" + encodeURIComponent(codigo))
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (d) {
        var p = d.proprietario || {};
        leadTitulo.textContent = "#" + codigo + (p.nome ? " — " + p.nome : "");
        var html = secaoFicha("Proprietário", p) +
                   secaoFicha("Contrato e valores", d.contrato || {}) +
                   secaoFicha("Imóvel", d.imovel || {}, ["codigo"]);
        var outros = d.outros_imoveis || [];
        if (outros.length) {
          html += '<div class="lead-secao"><div class="lead-secao__titulo">' +
            "Outros imóveis deste proprietário (" + outros.length + ")</div>" +
            '<div class="tabela-envolucro"><div class="tabela-rolagem"><table class="tabela"><thead><tr>' +
            '<th scope="col">Código</th><th scope="col">Endereço</th>' +
            '<th scope="col">Situação</th><th scope="col">Vencimento</th></tr></thead><tbody>' +
            outros.map(function (o) {
              return '<tr><td><a href="#" data-lead="' + esc(o.codigo) + '">#' + esc(o.codigo) + "</a></td>" +
                "<td>" + esc([o.condominio, o.endereco].filter(Boolean).join(" — ") || "—") + "</td>" +
                "<td>" + esc(o.status || "—") + "</td>" +
                "<td>" + (o.vencimento
                  ? esc(new Date(o.vencimento + "T00:00:00").toLocaleDateString("pt-BR")) : "—") +
                "</td></tr>";
            }).join("") + "</tbody></table></div></div></div>";
        }
        html += '<div style="display:flex;gap:8px;flex-wrap:wrap">' +
          '<a class="btn-azul btn-mini" href="imovel-editar.html?codigo=' + esc(codigo) + '">Editar imóvel</a>' +
          '<a class="btn-neutro btn-mini" target="_blank" rel="noopener" ' +
             'href="https://imobeasy.com/admin/imoveis/' + esc(codigo) + '">Abrir no admin antigo</a>' +
          "</div>";
        leadCorpo.innerHTML = html;
      })
      .catch(function () {
        leadCorpo.innerHTML = '<p class="lead-vazio">Não foi possível carregar esta ficha.</p>';
      });
  }

  function fecharLead() { sobrepor.hidden = true; leadCorpo.innerHTML = ""; }
  document.getElementById("lead-fechar").addEventListener("click", fecharLead);
  sobrepor.addEventListener("click", function (ev) { if (ev.target === sobrepor) fecharLead(); });
  document.addEventListener("keydown", function (ev) {
    if (ev.key === "Escape" && !sobrepor.hidden) fecharLead();
  });
  /* Delegacao: pega o clique na linha da tabela e tambem nos links de "outros
     imoveis" dentro da propria ficha. */
  document.addEventListener("click", function (ev) {
    var link = ev.target.closest("[data-lead]");
    if (link) { ev.preventDefault(); abrirLead(link.getAttribute("data-lead")); return; }
    var tr = ev.target.closest("#corpo-lista tr");
    if (tr && !ev.target.closest("a")) {
      var cod = tr.getAttribute("data-codigo");
      if (cod) abrirLead(cod);
    }
  });

  fetch(window.API_BASE + "/api/listas/" + encodeURIComponent(id))
    .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
    .then(function (lista) {
      document.title = lista.nome + " — Imob Easy";
      titulo.textContent = lista.nome;
      subtitulo.textContent =
        lista.quantidade + " item(ns) · filtro: " + lista.filtro +
        " · criada em " + formatarData(lista.criado_em) + " por " + lista.exportado_por;

      var itens = lista.itens || [];
      if (!itens.length) {
        corpo.innerHTML = '<tr><td>Lista vazia.</td></tr>';
        return;
      }

      var colunas = ordenarColunas(itens);

      /* "Alugado" com contrato vencido nao e' contradicao: sao dois campos
         independentes no admin antigo -- o Status do imovel e a data de fim do
         contrato. O admin NAO guarda se o inquilino continua la; ocupacao e'
         inferencia nossa a partir do status, e a legenda diz isso. O
         descasamento entre os dois campos e' o que faz a lista valer. */
      if (colunas.indexOf("status_admin") !== -1) {
        var ocupados = itens.filter(function (i) { return i.status_admin === "Alugado"; }).length;
        var legenda = document.createElement("p");
        legenda.style.cssText =
          "font-size:var(--fs-sm);color:var(--texto-medio);margin-bottom:16px;" +
          "border-left:3px solid var(--roxo);padding-left:12px;line-height:1.6";
        legenda.innerHTML =
          '<strong>Imóvel hoje</strong> é o campo Status do imóvel no admin antigo — ' +
          'não é o status do contrato. <strong>Alugado</strong> quer dizer que o cadastro ' +
          'está marcado como alugado; o admin não registra em lugar nenhum se o inquilino ' +
          'continua no imóvel — isso só a ligação apura. ' +
          'Quando o status é Alugado e a data do contrato já passou, ou renovaram sem ' +
          'atualizar o sistema, ou o cadastro está desatualizado. ' +
          '<strong>São esses que valem a ligação: ' + ocupados + ' de ' + itens.length +
          '.</strong> Nos outros o imóvel já saiu da locação no cadastro ' +
          '(vendido, arquivado ou disponível).';
        acoes.parentNode.insertBefore(legenda, acoes);
      }
      cabecalho.innerHTML = colunas.map(function (c) {
        return '<th scope="col">' + esc(ROTULOS[c] || c) + "</th>";
      }).join("");
      corpo.innerHTML = itens.map(function (item) {
        return '<tr data-codigo="' + esc(item.codigo || "") + '" style="cursor:pointer" ' +
               'title="Clique para ver a ficha completa">' + colunas.map(function (c) {
          return "<td>" + formatarCelula(c, item[c], item) + "</td>";
        }).join("") + "</tr>";
      }).join("");

      acoes.innerHTML =
        '<button class="btn-azul btn-mini" id="btn-zap" type="button">Gerar links de WhatsApp</button>' +
        '<button class="btn-neutro btn-mini" id="btn-pegar-links" type="button">Links dos imóveis</button>' +
        '<button class="btn-neutro btn-mini" id="btn-csv" type="button">Baixar CSV</button>';

      /* ---- Gerar links de WhatsApp ----
         Agrupa por telefone. A lista e' por imovel, entao quem tem mais de um
         imovel no mesmo filtro aparece varias vezes -- sem agrupar, a mesma
         pessoa receberia a mesma mensagem duas ou tres vezes. Um contato,
         uma linha, com os codigos dos imoveis dele juntos. */
      document.getElementById("btn-zap").addEventListener("click", function () {
        var porTelefone = {}, ordem = [], semTel = 0, aConferir = 0;
        itens.forEach(function (i) {
          var tel = i.proprietario_telefone || i.telefone;
          var z = linkWhatsapp(tel);
          if (!z) { semTel++; return; }
          var chave = tel.replace(/\D/g, "");
          if (!porTelefone[chave]) {
            if (z.conferir) aConferir++;
            porTelefone[chave] = {
              nome: i.proprietario_nome || i.nome || "(sem nome)",
              url: z.url,
              conferir: z.conferir,
              codigos: [],
            };
            ordem.push(chave);
          }
          if (i.codigo) porTelefone[chave].codigos.push(i.codigo);
        });

        var contatos = ordem.map(function (k) { return porTelefone[k]; });
        if (!contatos.length) { alert("Nenhum item dessa lista tem telefone."); return; }

        var repetidos = itens.length - semTel - contatos.length;

        var texto = contatos.map(function (c) {
          return c.nome + "\n" + c.url;
        }).join("\n\n");

        painel.hidden = false;
        painel.innerHTML =
          '<div style="display:flex;align-items:center;justify-content:space-between;' +
               'gap:12px;flex-wrap:wrap;margin-bottom:12px">' +
            '<h2 style="font-size:var(--fs-md)">' + contatos.length + ' contatos</h2>' +
            '<div style="display:flex;gap:8px">' +
              '<button class="btn-azul btn-mini" id="zap-copiar" type="button">Copiar tudo</button>' +
              '<button class="btn-neutro btn-mini" id="zap-fechar" type="button">Fechar</button>' +
            '</div>' +
          '</div>' +
          '<p style="font-size:var(--fs-sm);color:var(--texto-medio);margin-bottom:12px">' +
            contatos.length + " contato(s) para " + (itens.length - semTel) + " imóvel(is)." +
            (repetidos > 0
              ? " <strong>" + repetidos + " linha(s) eram do mesmo telefone e foram juntadas</strong> — " +
                "sem isso a mesma pessoa receberia a mensagem mais de uma vez."
              : "") +
            (semTel ? " " + semTel + " item(ns) sem telefone ficaram de fora." : "") +
            (aConferir
              ? ' ' + aConferir + ' número(s) marcado(s) "conferir": são de 8 dígitos, ' +
                "de antes do nono dígito. Não inseri o 9 por conta própria."
              : "") +
          "</p>" +
          '<div style="max-height:60vh;overflow:auto;font-size:var(--fs-sm);line-height:1.7">' +
            contatos.map(function (c) {
              return '<div style="padding:8px 0;border-bottom:1px solid var(--borda)">' +
                '<div style="font-weight:600;color:var(--texto)">' + esc(c.nome) +
                  (c.codigos.length > 1
                    ? ' <span class="etiqueta etiqueta--azul">' + c.codigos.length + " imóveis</span>"
                    : "") +
                  (c.conferir ? ' <span class="etiqueta etiqueta--alerta">conferir</span>' : "") +
                  (c.codigos.length
                    ? '<span style="font-weight:400;color:var(--texto-fraco)"> · #' +
                      c.codigos.map(esc).join(" #") + "</span>"
                    : "") +
                "</div>" +
                '<a href="' + esc(c.url) + '" target="_blank" rel="noopener" ' +
                   'style="word-break:break-all">' + esc(c.url) + "</a>" +
              "</div>";
            }).join("") +
          "</div>";

        painel.scrollIntoView({ behavior: "smooth", block: "start" });
        document.getElementById("zap-copiar").addEventListener("click", function () {
          copiar(texto, contatos.length);
        });
        document.getElementById("zap-fechar").addEventListener("click", function () {
          painel.hidden = true; painel.innerHTML = "";
        });
      });

      /* ---- Links públicos dos imóveis ---- */
      document.getElementById("btn-pegar-links").addEventListener("click", function () {
        var links = itens
          .map(function (i) { return i.codigo ? "https://imobeasy.com/anuncios/" + i.codigo : null; })
          .filter(Boolean);
        if (!links.length) { alert("Os itens dessa lista não têm código de imóvel."); return; }
        copiar(links.join("\n"), links.length);
      });

      /* ---- CSV ---- */
      document.getElementById("btn-csv").addEventListener("click", function () {
        var linhasCsv = [colunas.map(function (c) { return ROTULOS[c] || c; }).join(",")]
          .concat(itens.map(function (item) {
            return colunas.map(function (c) {
              var v = item[c] == null ? "" : String(item[c]);
              return '"' + v.replace(/"/g, '""') + '"';
            }).join(",");
          }));
        var blob = new Blob(["﻿" + linhasCsv.join("\n")], { type: "text/csv;charset=utf-8;" });
        var url = URL.createObjectURL(blob);
        var a = document.createElement("a");
        a.href = url;
        a.download = lista.nome.replace(/[^a-z0-9]+/gi, "_") + ".csv";
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
      });
    })
    .catch(function () {
      titulo.textContent = "Lista não encontrada";
      corpo.innerHTML = '<tr><td>Não foi possível carregar essa lista.</td></tr>';
    });
})();
