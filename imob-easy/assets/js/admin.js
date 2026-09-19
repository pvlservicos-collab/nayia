/* ==========================================================================
   Imob Easy — Renderização das telas do sistema
   Cada container declara data-render="<tipo>" e data-fonte="<chave dos dados>".
   ========================================================================== */
(function () {
  "use strict";

  var D = window.DADOS_ADMIN || {};

  function esc(txt) {
    return String(txt == null ? "" : txt)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }

  var SVG_ALERTA =
    '<svg class="icone-alerta" viewBox="0 0 16 16" width="15" height="15" fill="currentColor" aria-hidden="true">' +
    '<path d="M8 1.4 15.2 14H.8Zm-.75 4.3v4h1.5v-4Zm0 5.2v1.5h1.5v-1.5Z"/></svg>';

  var SVG_OLHO =
    '<svg class="icone-olho" viewBox="0 0 16 16" width="16" height="16" fill="currentColor" aria-hidden="true">' +
    '<path d="M8 3.2C4.6 3.2 1.8 5.3.6 8c1.2 2.7 4 4.8 7.4 4.8S14.2 10.7 15.4 8C14.2 5.3 11.4 3.2 8 3.2Zm0 8a3.2 3.2 0 1 1 0-6.4 3.2 3.2 0 0 1 0 6.4Zm0-1.7a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3Z"/></svg>';

  var SVG_ICONES_LINHA =
    '<span class="codigo-icones" aria-hidden="true">' +
    '<svg viewBox="0 0 16 16" fill="currentColor"><path d="M1 4h14v8H1Zm1.5 1.5v5h11v-5Z"/></svg>' +
    '<svg viewBox="0 0 16 16" fill="currentColor"><path d="M7 1a6 6 0 1 0 3.7 10.7l3.3 3.3 1.1-1.1-3.3-3.3A6 6 0 0 0 7 1Zm0 1.6a4.4 4.4 0 1 1 0 8.8 4.4 4.4 0 0 1 0-8.8Z"/></svg>' +
    '<svg viewBox="0 0 16 16" fill="currentColor"><path d="M7.2 1h1.6v3l2.1-2.1 1.1 1.1L9.9 5.1l2.9-.8.4 1.5-2.9.8 2.9.8-.4 1.5-2.9-.8 2.1 2.1-1.1 1.1L8.8 9.2v3H7.2v-3l-2.1 2.1-1.1-1.1L6.1 8.1l-2.9.8-.4-1.5 2.9-.8-2.9-.8.4-1.5 2.9.8L4 3l1.1-1.1L7.2 4Z"/></svg>' +
    "</span>";

  function botoesLinha(rotuloSecundario) {
    return (
      '<span class="acoes-celula">' +
      '<a class="btn-mini" href="#">Ver</a>' +
      '<a class="btn-mini" href="#">' + (rotuloSecundario || "Editar") + "</a>" +
      "</span>"
    );
  }

  /* ---------------------------------------------------------------------
     Listas simples dos painéis do Início
     --------------------------------------------------------------------- */
  function listaSimples(itens) {
    return itens.map(function (item) {
      return (
        '<li class="painel__item"><strong>' + esc(item.nome) + "</strong>" +
        "<span>" + esc(item.info) + "</span></li>"
      );
    }).join("");
  }

  /* ---------------------------------------------------------------------
     Funil lateral
     --------------------------------------------------------------------- */
  function funil(itens) {
    var maior = itens.reduce(function (acc, i) { return Math.max(acc, i.contagem); }, 1);
    return itens.map(function (item) {
      var largura = Math.round((item.contagem / maior) * 100);
      return (
        '<button class="funil__item" type="button" style="--preenchimento:' + largura + '%"' +
        (item.ativo ? ' aria-current="true"' : "") + ">" +
        "<span>" + esc(item.rotulo) + "</span>" +
        '<span class="funil__contagem">' + esc(item.contagem) + "</span></button>"
      );
    }).join("");
  }

  /* ---------------------------------------------------------------------
     Condomínios
     --------------------------------------------------------------------- */
  function linhasCondominios(itens) {
    return itens.map(function (item) {
      return (
        "<tr>" +
        '<td><span class="codigo-linha">' +
          (item.olho ? SVG_OLHO : "") + (item.alerta ? SVG_ALERTA : "") +
          "<span>" + esc(item.nome) + "</span></span></td>" +
        "<td>" + esc(item.endereco) + "</td>" +
        '<td class="num">' + esc(item.imoveis) + "</td>" +
        '<td class="col-acoes">' + botoesLinha() + "</td>" +
        "</tr>"
      );
    }).join("");
  }

  /* ---------------------------------------------------------------------
     Imóveis
     --------------------------------------------------------------------- */
  function linhasImoveis(itens) {
    return itens.map(function (item) {
      return (
        '<tr data-codigo="' + esc(item.codigo) + '">' +
        '<td><span class="codigo-linha">' + SVG_ICONES_LINHA + "</span>" +
          '<span class="codigo-linha">' + esc(item.codigo) + "</span></td>" +
        '<td><span class="etiqueta etiqueta--verde">' + esc(item.status) +
          ' <span class="seta" aria-hidden="true">▾</span></span></td>' +
        "<td>" + esc(item.financia) + "</td>" +
        "<td>" + esc(item.valor) + "</td>" +
        "<td>" + esc(item.condominio) + "</td>" +
        "<td>" + esc(item.endereco) + "</td>" +
        '<td>' + (item.proprietario ? '<a href="#">' + esc(item.proprietario) + "</a>" : "") + "</td>" +
        '<td class="col-acoes"><span class="acoes-celula">' +
          '<a class="btn-mini" href="imovel-editar.html?codigo=' + esc(item.codigo) + '">Ver</a>' +
          '<a class="btn-mini" href="imovel-editar.html?codigo=' + esc(item.codigo) + '">Editar</a>' +
        "</span></td>" +
        "</tr>"
      );
    }).join("");
  }

  /* ---------------------------------------------------------------------
     Anúncios
     --------------------------------------------------------------------- */
  function linhasAnuncios(itens) {
    return itens.map(function (item) {
      var cor = item.status === "Rascunho" ? "etiqueta--laranja" : "etiqueta--verde";
      return (
        "<tr>" +
        '<td></td>' +
        '<td><span class="etiqueta ' + cor + '">' + esc(item.status) +
          ' <span class="seta" aria-hidden="true">▾</span></span></td>' +
        '<td><a href="imovel-editar.html?codigo=' + esc(item.codigo) + '">' + esc(item.codigo) + "</a> <span>(" + esc(item.referencia) + ")</span></td>" +
        "<td>" + esc(item.tipo) + "</td>" +
        "<td>" + esc(item.financia) + "</td>" +
        "<td>" + esc(item.valor) + "</td>" +
        '<td class="col-acoes"><a class="btn-mini" href="imovel-editar.html?codigo=' + esc(item.codigo) + '">Editar</a></td>' +
        "</tr>"
      );
    }).join("");
  }

  /* ---------------------------------------------------------------------
     Proprietários
     --------------------------------------------------------------------- */
  function fichasProprietarios(itens) {
    return itens.map(function (item) {
      return (
        '<article class="ficha">' +
          '<h3 class="ficha__nome">' + esc(item.nome) + "</h3>" +
          '<div class="ficha__etiquetas">' +
            '<span class="etiqueta etiqueta--azul-suave">' + esc(item.etapa) +
            ' <span class="seta" aria-hidden="true">▾</span></span>' +
          "</div>" +
          '<p class="ficha__cpf">' + esc(item.cpf) + "</p>" +
          '<dl class="ficha__dados">' +
            '<div class="ficha__linha"><dt>Imóveis:</dt><dd>' + esc(item.imoveis) + "</dd></div>" +
            '<div class="ficha__linha"><dt>Telefone:</dt><dd>' + esc(item.telefone) + "</dd></div>" +
            '<div class="ficha__linha ficha__linha--empilhada"><dt>Email:</dt><dd>' + esc(item.email) + "</dd></div>" +
          "</dl>" +
          '<a class="btn-azul btn-bloco" href="#">Ver proprietário</a>' +
        "</article>"
      );
    }).join("");
  }

  /* ---------------------------------------------------------------------
     Clientes
     --------------------------------------------------------------------- */
  function fichasClientes(itens) {
    return itens.map(function (item) {
      var temperatura = "";
      if (item.temperatura) {
        var classe = item.temperatura === "Quente" ? "etiqueta--contorno-quente"
                   : item.temperatura === "Morno" ? "etiqueta--contorno-morno"
                   : "etiqueta--contorno-frio";
        temperatura =
          '<div class="ficha__linha"><dt>Temperatura:</dt><dd>' +
          '<span class="etiqueta ' + classe + '">' + esc(item.temperatura) +
          ' <span class="seta" aria-hidden="true">▾</span></span></dd></div>';
      }

      var atencao = item.atencao
        ? '<span class="etiqueta etiqueta--alerta">' + SVG_ALERTA.replace("icone-alerta", "") + " Precisa de Atenção</span>"
        : "";

      return (
        '<article class="ficha">' +
          '<h3 class="ficha__nome' + (item.spam ? " ficha__nome--bloqueado" : "") + '">' + esc(item.nome) + "</h3>" +
          '<div class="ficha__etiquetas">' + atencao +
            '<span class="etiqueta etiqueta--azul-suave">' + esc(item.etapa) +
            ' <span class="seta" aria-hidden="true">▾</span></span>' +
          "</div>" +
          '<dl class="ficha__dados">' + temperatura +
            '<div class="ficha__linha"><dt>Telefone:</dt><dd>' + esc(item.telefone) + "</dd></div>" +
            '<div class="ficha__linha ficha__linha--empilhada"><dt>Email:</dt><dd>' + esc(item.email) + "</dd></div>" +
          "</dl>" +
          '<a class="btn-azul btn-bloco" href="#">Ver cliente</a>' +
        "</article>"
      );
    }).join("");
  }

  /* ---------------------------------------------------------------------
     Auditoria
     --------------------------------------------------------------------- */
  function eventosAuditoria(itens) {
    return itens.map(function (item) {
      var mudancas = item.mudancas.map(function (m) {
        var rotulo = m.campo
          ? esc(m.campo)
          : 'Translation missing: <span class="chave-tecnica">' + esc(m.chave) + "</span>";
        var corpo = m.de
          ? ": de <del>" + esc(m.de) + "</del> para <strong>" + esc(m.para) + "</strong>"
          : ": para <strong>" + esc(m.para) + "</strong>";
        return "<li>" + rotulo + corpo + "</li>";
      }).join("");

      return (
        '<div class="evento">' +
          '<div class="evento__quando">' + esc(item.data) + "<br>" + esc(item.hora) + "</div>" +
          '<div class="evento__marcador"><span class="evento__ponto' +
            (item.tipo === "criado" ? " evento__ponto--criado" : "") + '"></span></div>' +
          '<div class="evento__corpo">' +
            '<p class="evento__titulo">' + esc(item.titulo) + "</p>" +
            '<p class="evento__autor">por <a href="#">' + esc(item.autor) + "</a></p>" +
            (mudancas ? '<ul class="evento__mudancas">' + mudancas + "</ul>" : "") +
            '<a href="#">' + esc(item.link) + "</a>" +
          "</div>" +
        "</div>"
      );
    }).join("");
  }

  /* ---------------------------------------------------------------------
     Avisos (imóveis/contratos perto de vencer e vencidos)
     --------------------------------------------------------------------- */
  function listaAvisos(itens, vazio) {
    if (!itens.length) return '<li class="painel__vazio">' + esc(vazio) + "</li>";
    return itens.map(function (item) {
      var quando = item.vencimento
        ? new Date(item.vencimento + "T00:00:00").toLocaleDateString("pt-BR")
        : "—";
      var contato = item.proprietario_nome || item.proprietario_telefone
        ? esc(item.proprietario_nome || "—") + (item.proprietario_telefone ? " · " + esc(item.proprietario_telefone) : "")
        : "sem proprietário cadastrado";
      return (
        '<li class="painel__item"><strong>#' + esc(item.codigo) + " — " + esc(item.condominio) + "</strong>" +
        "<span>Vencimento: " + esc(quando) + " · " + contato + "</span></li>"
      );
    }).join("");
  }

  function avisos(dados) {
    return (
      '<div class="avisos__coluna">' +
        "<h3>Contratos vencendo (30 dias)</h3>" +
        '<ul class="painel__lista">' + listaAvisos(dados.vencendo, "Nenhum contrato vencendo nos próximos 30 dias.") + "</ul>" +
      "</div>" +
      '<div class="avisos__coluna">' +
        "<h3>Contratos vencidos</h3>" +
        '<ul class="painel__lista">' + listaAvisos(dados.vencidos, "Nenhum contrato vencido.") + "</ul>" +
      "</div>"
    );
  }

  function listaOportunidadeVencidos(dados) {
    return listaAvisos(dados.vencidos, "Nenhum contrato vencido.");
  }
  function listaOportunidadeVencendo(dados) {
    return listaAvisos(dados.vencendo, "Nenhum contrato vencendo nos próximos 30 dias.");
  }

  /* ---------------------------------------------------------------------
     Status do sistema (bolinhas verde/amarela/vermelha)
     --------------------------------------------------------------------- */
  function statusSistema(itens) {
    return itens.map(function (item) {
      var cor = item.status === "ok" ? "bolinha--verde" : item.status === "alerta" ? "bolinha--amarela" : "bolinha--vermelha";
      return (
        '<li class="status-recurso">' +
          '<span class="bolinha ' + cor + '" aria-hidden="true"></span>' +
          '<span class="status-recurso__nome">' + esc(item.recurso) + "</span>" +
          (item.detalhe ? '<span class="status-recurso__detalhe">' + esc(item.detalhe) + "</span>" : "") +
        "</li>"
      );
    }).join("");
  }

  /* ---------------------------------------------------------------------
     Corretores mais ativos (Oportunidades) -- telefone mascarado, sem
     nome porque a API nunca leu a coluna nome de corretores.
     --------------------------------------------------------------------- */
  function corretoresAtivos(itens) {
    return itens.map(function (item, i) {
      return (
        "<tr>" +
        '<td class="num">' + (i + 1) + "</td>" +
        "<td>" + esc(item.telefone) + "</td>" +
        '<td class="num">' + esc(item.mensagens) + "</td>" +
        "</tr>"
      );
    }).join("");
  }

  /* ---------------------------------------------------------------------
     Cartões de corretor (Área Corretores)
     --------------------------------------------------------------------- */
  function cartoesCorretores(itens) {
    return itens.map(function (item) {
      var etiqueta = item.aprovado
        ? '<span class="etiqueta etiqueta--verde">Aprovado</span>'
        : '<span class="etiqueta etiqueta--laranja">Aguardando aprovação</span>';
      var ultima = item.ultima_interacao
        ? new Date(item.ultima_interacao).toLocaleDateString("pt-BR")
        : "sem registro";
      return (
        '<article class="ficha">' +
          '<h3 class="ficha__nome">' + esc(item.nome || item.telefone) + "</h3>" +
          (item.nome ? '<p class="ficha__cpf">' + esc(item.telefone) + "</p>" : "") +
          '<div class="ficha__etiquetas">' + etiqueta +
            (item.ativo ? "" : ' <span class="etiqueta etiqueta--alerta">Inativo</span>') +
          "</div>" +
          '<dl class="ficha__dados">' +
            '<div class="ficha__linha"><dt>No-shows:</dt><dd>' + esc(item.no_shows) + "</dd></div>" +
            '<div class="ficha__linha"><dt>Última interação:</dt><dd>' + esc(ultima) + "</dd></div>" +
          "</dl>" +
        "</article>"
      );
    }).join("");
  }

  /* ---------------------------------------------------------------------
     Contratos de locação (Área Locação)
     --------------------------------------------------------------------- */
  function linhasContratos(itens) {
    if (!itens.length) {
      return '<tr><td colspan="6" style="text-align:center;color:var(--texto-fraco);padding:24px">' +
        "Nenhum contrato nesse período.</td></tr>";
    }
    return itens.map(function (item) {
      var quando = item.vencimento ? new Date(item.vencimento + "T00:00:00").toLocaleDateString("pt-BR") : "—";
      return (
        "<tr>" +
        "<td>" + esc(item.codigo) + "</td>" +
        "<td>" + esc(item.condominio) + "</td>" +
        "<td>" + esc(quando) + "</td>" +
        "<td>" + esc(item.status || "—") + "</td>" +
        "<td>" + esc(item.proprietario_nome || "—") + "</td>" +
        "<td>" + esc(item.proprietario_telefone || "—") + "</td>" +
        "</tr>"
      );
    }).join("");
  }

  /* ---------------------------------------------------------------------
     Dispatcher
     --------------------------------------------------------------------- */
  // Expostos pra scripts inline (widget de filtro de vencimento) chamarem
  // sem duplicar a lógica de montagem de linha/cartão.
  window.RENDERIZAR_IMOVEIS = linhasImoveis;
  window.RENDERIZAR_CONTRATOS = linhasContratos;
  window.RENDERIZAR_ANUNCIOS = linhasAnuncios;
  window.RENDERIZAR_CORRETORES = cartoesCorretores;

  window.RENDERIZAR_PROPRIETARIOS_REAIS = function (itens) {
    if (!itens.length) return '<p class="painel__vazio">Nenhum proprietário nesse período.</p>';
    return itens.map(function (item) {
      var quando = item.vencimento ? new Date(item.vencimento + "T00:00:00").toLocaleDateString("pt-BR") : "—";
      return (
        '<article class="ficha">' +
          '<h3 class="ficha__nome">' + esc(item.nome) + "</h3>" +
          '<dl class="ficha__dados">' +
            '<div class="ficha__linha"><dt>Imóvel:</dt><dd>#' + esc(item.codigo) + " " + esc(item.condominio) + "</dd></div>" +
            '<div class="ficha__linha"><dt>Vencimento:</dt><dd>' + esc(quando) + "</dd></div>" +
            '<div class="ficha__linha"><dt>Telefone:</dt><dd>' + esc(item.telefone || "—") + "</dd></div>" +
            '<div class="ficha__linha ficha__linha--empilhada"><dt>Email:</dt><dd>' + esc(item.email || "—") + "</dd></div>" +
          "</dl>" +
        "</article>"
      );
    }).join("");
  };

  var RENDERIZADORES = {
    lista: listaSimples,
    funil: funil,
    condominios: linhasCondominios,
    imoveis: linhasImoveis,
    anuncios: linhasAnuncios,
    proprietarios: fichasProprietarios,
    clientes: fichasClientes,
    auditoria: eventosAuditoria,
    avisos: avisos,
    statusSistema: statusSistema,
    corretoresAtivos: corretoresAtivos,
    corretores: cartoesCorretores,
    contratos: linhasContratos,
    "lista-vencidos": listaOportunidadeVencidos,
    "lista-vencendo": listaOportunidadeVencendo
  };

  /* Roda uma vez de imediato com o que dados-admin.js tiver (estático, de
     fallback) e de novo quando "dados-admin-atualizados" disparar (API
     respondeu). Sem resposta da API, fica só o estático -- nunca quebra. */
  function renderizarPaineis() {
    D = window.DADOS_ADMIN || {};

    document.querySelectorAll("[data-render]").forEach(function (alvo) {
      var fn = RENDERIZADORES[alvo.dataset.render];
      var dados = D[alvo.dataset.fonte];
      if (fn && dados) alvo.innerHTML = fn(dados);
    });

    document.querySelectorAll("[data-valor]").forEach(function (alvo) {
      var valor = (D.indicadores || {})[alvo.dataset.valor];
      if (valor != null) alvo.textContent = valor;
    });

    document.querySelectorAll("[data-texto]").forEach(function (alvo) {
      var valor = D[alvo.dataset.texto];
      if (valor != null) alvo.textContent = valor;
    });
  }
  renderizarPaineis();
  document.addEventListener("dados-admin-atualizados", renderizarPaineis);

  /* O filtro de vencimento de Todos os Imóveis agora é o widget
     reutilizável (assets/js/filtro-vencimento.js), iniciado inline em
     admin/imoveis.html -- usa /api/imoveis-admin?de=&ate= direto. */

  /* ---------------------------------------------------------------------
     Popup de imóvel -- clique numa linha da tabela de Todos os Imóveis
     (fora dos botões de ação) busca o detalhe na API e mostra um resumo,
     com um botão que leva pra tela de edição de verdade.
     --------------------------------------------------------------------- */
  (function () {
    var overlay = document.getElementById("popup-imovel");
    if (!overlay) return; // só existe em admin/imoveis.html

    var corpo = overlay.querySelector("[data-popup-corpo]");
    var titulo = overlay.querySelector("[data-popup-titulo]");
    var codigoTxt = overlay.querySelector("[data-popup-codigo]");
    var linkVer = overlay.querySelector("[data-popup-ver]");

    function fechar() { overlay.hidden = true; corpo.innerHTML = ""; }

    function abrir(codigo) {
      overlay.hidden = false;
      titulo.textContent = "Carregando...";
      codigoTxt.textContent = "";
      corpo.innerHTML = "";
      linkVer.href = "imovel-editar.html?codigo=" + encodeURIComponent(codigo);
      linkVer.hidden = false;

      if (!window.API_BASE) { titulo.textContent = "API não configurada"; return; }

      fetch(window.API_BASE + "/api/imoveis/" + encodeURIComponent(codigo))
        .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
        .then(function (item) {
          titulo.textContent = item.condominio_nome || item.tipo || "Imóvel";
          codigoTxt.textContent = "Código " + item.codigo;
          var linhas = [
            ["Status", item.status || (item.disponivel ? "Disponível" : "Indisponível")],
            ["Bairro", item.bairro || "—"],
            ["Endereço", [item.logradouro, item.numero].filter(Boolean).join(", ") || "—"],
            ["Quartos", item.quartos != null ? item.quartos : "—"],
            ["Banheiros", item.banheiros != null ? item.banheiros : "—"],
            ["Venda", item.valor_venda != null ? "R$ " + item.valor_venda.toLocaleString("pt-BR") : "—"],
            ["Aluguel", item.valor_aluguel != null ? "R$ " + item.valor_aluguel.toLocaleString("pt-BR") : "—"],
          ];
          corpo.innerHTML = linhas.map(function (l) {
            return "<dt>" + esc(l[0]) + "</dt><dd>" + esc(l[1]) + "</dd>";
          }).join("");
        })
        .catch(function () {
          // Imóvel só do admin antigo (alugado, vendido, arquivado...): não
          // está no catálogo, então o detalhe não existe -- mostra o que a
          // lista já trouxe, em vez de "não foi possível".
          var i = (window.IMOVEIS_NA_TELA || {})[codigo];
          if (!i) { titulo.textContent = "Não foi possível carregar este imóvel."; return; }
          titulo.textContent = i.condominio || i.tipo || "Imóvel";
          codigoTxt.textContent = "Código " + i.codigo + " · só no admin antigo (fora do catálogo)";
          linkVer.hidden = true;
          corpo.innerHTML = [["Status", i.status], ["Tipo", i.tipo || "—"], ["Valor", i.valor],
            ["Endereço", [i.endereco, i.bairro].filter(Boolean).join(" - ") || "—"],
            ["Proprietário", i.proprietario || "—"],
            ["Contrato até", i.vencimento ? new Date(i.vencimento + "T00:00:00").toLocaleDateString("pt-BR") : "—"]]
            .map(function (l) { return "<dt>" + esc(l[0]) + "</dt><dd>" + esc(l[1]) + "</dd>"; }).join("");
        });
    }

    document.querySelectorAll(".tabela tbody").forEach(function (tbody) {
      tbody.addEventListener("click", function (evento) {
        if (evento.target.closest(".acoes-celula")) return; // botões têm seu próprio link
        var linha = evento.target.closest("tr[data-codigo]");
        if (!linha) return;
        abrir(linha.dataset.codigo);
      });
    });

    overlay.addEventListener("click", function (evento) {
      if (evento.target === overlay || evento.target.closest("[data-popup-fechar]")) fechar();
    });
    document.addEventListener("keydown", function (evento) {
      if (evento.key === "Escape" && !overlay.hidden) fechar();
    });
  })();

  /* ---- Abas da Auditoria ---- */
  document.querySelectorAll(".abas").forEach(function (grupo) {
    grupo.addEventListener("click", function (evento) {
      var aba = evento.target.closest(".abas__item");
      if (!aba) return;
      grupo.querySelectorAll(".abas__item").forEach(function (i) {
        i.setAttribute("aria-selected", i === aba ? "true" : "false");
      });
    });
  });

  /* ---- Abas funcionais (Locação: Locatários / Locadores / Contratos) ----
     Diferente de .abas (cosmética, usada na Auditoria): aqui cada aba tem
     data-painel-abre apontando pro id do painel que deve ficar visível. */
  document.querySelectorAll("[data-abas-funcionais]").forEach(function (grupo) {
    grupo.addEventListener("click", function (evento) {
      var aba = evento.target.closest("[data-painel-abre]");
      if (!aba) return;
      grupo.querySelectorAll("[data-painel-abre]").forEach(function (i) {
        i.setAttribute("aria-selected", i === aba ? "true" : "false");
      });
      var alvoId = aba.dataset.painelAbre;
      document.querySelectorAll("[data-painel]").forEach(function (painel) {
        painel.hidden = painel.dataset.painel !== alvoId;
      });
    });
  });

  /* A sanfona de "Próximos passos" agora é dinâmica (CRUD via banco) --
     o próprio assets/js/proximos-passos.js cuida de abrir/fechar. */

  /* ---- Funil: seleção visual ---- */
  document.querySelectorAll(".funil").forEach(function (grupo) {
    grupo.addEventListener("click", function (evento) {
      var item = evento.target.closest(".funil__item");
      if (!item) return;
      grupo.querySelectorAll(".funil__item").forEach(function (i) { i.removeAttribute("aria-current"); });
      item.setAttribute("aria-current", "true");
    });
  });
})();
