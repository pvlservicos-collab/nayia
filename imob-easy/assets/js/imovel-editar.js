/* ==========================================================================
   Imob Easy — Tela de edição de um imóvel (grava direto no naydb)
   ========================================================================== */
(function () {
  "use strict";

  function esc(txt) {
    return String(txt == null ? "" : txt)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }

  var params = new URLSearchParams(window.location.search);
  var codigo = params.get("codigo");
  // NOVO IMOVEL (revisao 11/09): o botao "Novo Imovel" era href="#" e nao
  // existia criacao nenhuma. Sem ?codigo e com ?novo=1, o form nasce vazio
  // e grava com POST; o codigo sai da faixa 900000+ (nao colide com o site).
  var novo = !codigo && params.get("novo") === "1";
  var form = document.getElementById("form-imovel");
  var carregando = document.getElementById("carregando");
  var tituloCodigo = document.getElementById("titulo-codigo");
  var seletorCondo = null;
  var condoInicial = null;

  if (!codigo && !novo) {
    carregando.textContent = "Nenhum código de imóvel informado na URL (?codigo=...).";
    return;
  }
  if (!window.API_BASE) {
    carregando.textContent = "config.js não define API_BASE.";
    return;
  }

  /* Grupos de campos -- as chaves têm que bater com CAMPOS_EDITAVEIS do
     app.py. Se um campo aparecer aqui mas não estiver liberado no servidor,
     o PUT simplesmente ignora ele (não quebra, só não salva). */
  var GRUPOS = [
    { titulo: "Localização", campos: ["condominio", "bairro", "cidade", "estado", "logradouro", "numero", "complemento", "cep"] },
    { titulo: "Características", campos: ["tipo", "quartos", "suites", "banheiros", "vagas", "vagas_cobertas", "area_util", "area_total", "sol", "andar", "mobilia"] },
    { titulo: "Valores", campos: ["valor_venda", "valor_aluguel", "taxa_condominio", "iptu"] },
    { titulo: "Descrição", campos: ["descricao", "caracteristicas"] },
    { titulo: "Publicação e status interno", campos: ["publicado_no_site", "disponivel", "bloqueado", "motivo_bloqueio"] },
  ];

  var ROTULOS = {
    bairro: "Bairro", cidade: "Cidade", estado: "Estado", logradouro: "Logradouro",
    numero: "Número", complemento: "Complemento", cep: "CEP",
    tipo: "Tipo", quartos: "Quartos", suites: "Suítes", banheiros: "Banheiros",
    vagas: "Vagas", vagas_cobertas: "Vagas cobertas", area_util: "Área útil (m²)",
    area_total: "Área total (m²)", sol: "Sol (face solar)", andar: "Andar",
    mobilia: "Mobília", valor_venda: "Valor de venda (R$)", valor_aluguel: "Valor de aluguel (R$)",
    taxa_condominio: "Taxa de condomínio (R$)", iptu: "IPTU (R$)",
    descricao: "Descrição", caracteristicas: "Características (uma por linha)",
    publicado_no_site: "Publicado no site", disponivel: "Disponível",
    bloqueado: "Bloqueado", motivo_bloqueio: "Motivo do bloqueio",
  };

  function campoHtml(nome, valor, regra) {
    if (nome === "condominio") {
      return (
        '<div class="form-imovel__campo form-imovel__campo--largo">' +
          "<label>Condomínio</label>" +
          '<input class="entrada" type="text" id="campo-condominio" placeholder="Digite o nome do condomínio e escolha na lista">' +
        "</div>"
      );
    }
    if (nome === "tipo") {
      return (
        '<div class="form-imovel__campo">' +
          "<label>" + esc(ROTULOS.tipo) + (novo ? " *" : "") +
          (regra.sincronizado ? ' <span class="marca-sincronizado">● sincronizado</span>' : "") + "</label>" +
          '<input class="entrada" type="text" list="tipos-imovel" data-campo="tipo" value="' + esc(valor || "") + '"' + (novo ? " required" : "") + ">" +
          '<datalist id="tipos-imovel"><option>Apartamento</option><option>Casa</option><option>Casa de condomínio</option>' +
          "<option>Cobertura</option><option>Flat</option><option>Sala/Andar</option><option>Loja/Ponto</option>" +
          "<option>Lote em Condomínio</option><option>Terreno</option><option>Prédio</option><option>Galpão</option></datalist>" +
        "</div>"
      );
    }
    var marca = regra.sincronizado ? '<span class="marca-sincronizado">● sincronizado</span>' : "";
    var largo = (nome === "descricao" || nome === "caracteristicas" || nome === "motivo_bloqueio") ? " form-imovel__campo--largo" : "";

    if (regra.tipo === "booleano") {
      return (
        '<div class="form-imovel__campo' + largo + '">' +
          '<label><input type="checkbox" data-campo="' + nome + '" ' + (valor ? "checked" : "") + "> " +
          esc(ROTULOS[nome] || nome) + "</label>" + marca +
        "</div>"
      );
    }
    if (nome === "descricao" || nome === "motivo_bloqueio") {
      return (
        '<div class="form-imovel__campo' + largo + '">' +
          "<label>" + esc(ROTULOS[nome] || nome) + marca + "</label>" +
          '<textarea class="entrada" data-campo="' + nome + '">' + esc(valor || "") + "</textarea>" +
        "</div>"
      );
    }
    if (nome === "caracteristicas") {
      var texto = Array.isArray(valor) ? valor.join("\n") : "";
      return (
        '<div class="form-imovel__campo' + largo + '">' +
          "<label>" + esc(ROTULOS[nome] || nome) + marca + "</label>" +
          '<textarea class="entrada" data-campo="' + nome + '" data-lista="true">' + esc(texto) + "</textarea>" +
        "</div>"
      );
    }
    var tipoInput = regra.tipo === "numero" ? "number" : regra.tipo === "inteiro" ? "number" : "text";
    var step = regra.tipo === "numero" ? ' step="0.01"' : "";
    return (
      '<div class="form-imovel__campo">' +
        "<label>" + esc(ROTULOS[nome] || nome) + marca + "</label>" +
        '<input class="entrada" type="' + tipoInput + '"' + step + ' data-campo="' + nome + '" value="' + esc(valor == null ? "" : valor) + '">' +
      "</div>"
    );
  }

  fetch(window.API_BASE + (novo ? "/api/imoveis/campos" : "/api/imoveis/" + encodeURIComponent(codigo)))
    .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
    .then(function (item) {
      if (novo) {
        item = { campos_editaveis: item, disponivel: true };
        document.title = "Novo imóvel — Imob Easy";
        var h = document.querySelector(".pagina-titulo");
        if (h) h.firstChild.textContent = "Novo imóvel ";
        tituloCodigo.textContent = "";
      } else {
        tituloCodigo.textContent = "#" + item.codigo + (item.condominio_nome ? " — " + item.condominio_nome : "");
      }
      var regras = item.campos_editaveis;
      condoInicial = item.condo_id ? { id: item.condo_id, nome: item.condominio_nome || ("Condomínio " + item.condo_id) } : null;

      var html = GRUPOS.map(function (grupo) {
        var campos = grupo.campos.filter(function (c) { return regras[c] || c === "condominio"; });
        if (!campos.length) return "";
        return (
          '<section class="form-imovel__grupo"><h2>' + esc(grupo.titulo) + "</h2>" +
            '<div class="form-imovel__grade">' +
              campos.map(function (c) { return campoHtml(c, item[c], regras[c]); }).join("") +
            "</div>" +
          "</section>"
        );
      }).join("");

      html +=
        '<div class="form-imovel__rodape">' +
          '<button class="btn-azul" type="submit">' + (novo ? "Criar imóvel" : "Salvar alterações") + "</button>" +
          (novo ? '<span class="form-imovel__status">Nasce FORA do site (não aparece na vitrine nem é oferecido pela Nay até você marcar "Publicado no site").</span>' : "") +
          '<span class="form-imovel__status" id="status-salvar"></span>' +
        "</div>";

      form.innerHTML = html;
      carregando.hidden = true;
      form.hidden = false;
      var campoCondo = document.getElementById("campo-condominio");
      if (campoCondo && window.criarSeletorCondominio) {
        seletorCondo = window.criarSeletorCondominio(campoCondo, { multiplo: false });
        if (condoInicial) seletorCondo.definir([condoInicial]);
      }
      if (!novo && item.condominio_nome && !item.condo_id && campoCondo) {
        campoCondo.placeholder = "Hoje: \"" + item.condominio_nome + "\" (sem vínculo) — escolha na lista para ligar";
      }
    })
    .catch(function () {
      carregando.textContent = "Não foi possível carregar este imóvel (código inexistente ou API fora do ar).";
    });

  form.addEventListener("submit", function (evento) {
    evento.preventDefault();
    var status = document.getElementById("status-salvar");
    var corpo = {};

    form.querySelectorAll("[data-campo]").forEach(function (campo) {
      var nome = campo.dataset.campo;
      if (campo.type === "checkbox") {
        corpo[nome] = campo.checked;
      } else if (campo.dataset.lista === "true") {
        corpo[nome] = campo.value.split("\n").map(function (l) { return l.trim(); }).filter(Boolean);
      } else if (campo.value === "") {
        corpo[nome] = null;
      } else {
        corpo[nome] = campo.value;
      }
    });

    // Condominio: so manda se mudou (id escolhido na lista; nunca texto livre).
    if (seletorCondo) {
      var escolhido = seletorCondo.valores()[0] || null;
      var antes = condoInicial ? condoInicial.id : null;
      var agora = escolhido ? escolhido.id : null;
      if (novo ? agora : agora !== antes) corpo.condo_id = agora;
    }
    if (novo && !corpo.tipo) {
      status.textContent = "Informe o tipo do imóvel.";
      status.className = "form-imovel__status form-imovel__status--erro";
      return;
    }

    status.textContent = "Salvando...";
    status.className = "form-imovel__status";

    fetch(window.API_BASE + (novo ? "/api/imoveis" : "/api/imoveis/" + encodeURIComponent(codigo)), {
      method: novo ? "POST" : "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(corpo),
    })
      .then(function (r) { return r.json().then(function (dados) { return { ok: r.ok, dados: dados }; }); })
      .then(function (resultado) {
        if (resultado.ok && novo) {
          window.location.href = "imovel-editar.html?codigo=" + encodeURIComponent(resultado.dados.codigo) + "&criado=1";
          return;
        }
        if (resultado.ok) {
          if (seletorCondo) condoInicial = seletorCondo.valores()[0] || null;
          status.textContent = "Salvo.";
          status.className = "form-imovel__status form-imovel__status--ok";
        } else {
          status.textContent = "Erro: " + ([].concat(resultado.dados.detalhes || []).join("; ") || resultado.dados.erro || "não salvou");
          status.className = "form-imovel__status form-imovel__status--erro";
        }
      })
      .catch(function () {
        status.textContent = "Erro de conexão com a API.";
        status.className = "form-imovel__status form-imovel__status--erro";
      });
  });
})();
