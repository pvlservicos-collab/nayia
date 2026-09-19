/* ==========================================================================
   Imob Easy — Nay de Captação: "Revisar no WhatsApp" (admin)

   Pedido do Tel (15/09/2026): "estou com problemas para encontrar essas
   mensagens, cria pra mim lá na aba de captação um mockup como se fosse de
   whatsapp com cada conversa dessa aí e a mensagem que chegou minha e da
   pessoa para eu dar uma olhada e decidir".

   A aba "Conversas" que já existia mostra só a ÚLTIMA fala de cada lado, e é
   por isso que ele não achava nada. Aqui vem o thread inteiro, balão a balão,
   de /api/nai/captacao/conversas.

   ESTA TELA NÃO ENVIA NADA. O rascunho da mensagem fica num campo com botão de
   copiar; quem manda é ele, no WhatsApp. Foi o que ele pediu -- "ainda não
   dispara" -- e é também o que evita uma tela de painel virar disparador.
   ========================================================================== */
(function () {
  "use strict";

  var API = window.API_BASE || "";
  var conversas = [];
  var escolhida = null;

  function esc(t) {
    return String(t == null ? "" : t)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }

  function elemento(id) { return document.getElementById(id); }

  /* O grupo da triagem vira a cor da etiqueta. O número na frente do nome do
     grupo ("1 - Imóvel na mão") é quem manda -- assim um grupo novo no banco
     não exige mexer aqui. */
  function classeDoGrupo(prioridade) {
    var n = String(prioridade || "").trim().charAt(0);
    return "zap-g" + (n >= "1" && n <= "5" ? n : "3");
  }

  /* A hora é sempre a de MANAUS, não a do computador de quem abre a tela. A
     conversa aconteceu lá, e a API entrega em GMT -- sem fixar o fuso, quem
     abrisse de outro estado veria horário que nunca existiu na conversa. */
  var FUSO = "America/Manaus";

  function soData(iso) {
    var d = new Date(iso);
    return isNaN(d) ? "" : d.toLocaleDateString("pt-BR",
      { day: "2-digit", month: "long", year: "numeric", timeZone: FUSO });
  }

  function soHora(iso) {
    var d = new Date(iso);
    return isNaN(d) ? "" : d.toLocaleTimeString("pt-BR",
      { hour: "2-digit", minute: "2-digit", timeZone: FUSO });
  }

  function quandoCurto(iso) {
    var d = new Date(iso);
    if (isNaN(d)) return "";
    var mesmoDia = soData(iso) === soData(new Date().toISOString());
    return mesmoDia ? soHora(iso)
                    : d.toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit", timeZone: FUSO });
  }

  function iniciais(nome) {
    var p = String(nome || "?").trim().split(/\s+/);
    return ((p[0] || "?").charAt(0) + (p.length > 1 ? p[p.length - 1].charAt(0) : "")).toUpperCase();
  }

  /* Mensagem sem texto existe de verdade na base: áudio, figurinha e foto
     chegam assim. Mostrar o balão vazio esconderia que algo foi dito. */
  function textoDoBalao(m) {
    var t = String(m.texto == null ? "" : m.texto).trim();
    if (t) return { texto: t, vazia: false };
    var nomes = { audio: "áudio", imagem: "imagem", video: "vídeo",
                  documento: "arquivo", figurinha: "figurinha", reacao: "reação" };
    var o = nomes[m.origem] || "mensagem sem texto";
    return { texto: "(" + o + " — o sistema não lê o conteúdo)", vazia: true };
  }

  function listaFiltrada() {
    var busca = (elemento("zap-busca").value || "").trim().toLowerCase();
    var soTriagem = elemento("zap-so-triagem").checked;
    return conversas.filter(function (c) {
      if (soTriagem && !c.prioridade) return false;
      if (!busca) return true;
      return [c.nome, c.imovel, c.telefone, c.prioridade]
        .join(" ").toLowerCase().indexOf(busca) >= 0;
    });
  }

  function desenharLista() {
    var alvo = elemento("zap-itens");
    var lista = listaFiltrada();
    if (!lista.length) {
      alvo.innerHTML = '<p class="zap__vazio">Nenhuma conversa com esse filtro.</p>';
      return;
    }
    alvo.innerHTML = lista.map(function (c) {
      var ultima = c.mensagens.length ? c.mensagens[c.mensagens.length - 1] : null;
      var previa = ultima ? (ultima.direcao === "enviada" ? "Você: " : "") + textoDoBalao(ultima).texto : "";
      return '<button class="zap__item" type="button" role="tab" data-lead="' + c.id + '"' +
             ' aria-selected="' + (escolhida === c.id ? "true" : "false") + '">' +
             '<span class="zap__ini">' + esc(iniciais(c.nome)) + "</span>" +
             "<span>" +
               '<span class="zap__quando">' + esc(quandoCurto(c.ultima_em)) + "</span>" +
               '<span class="zap__nome">' + esc(c.nome || "(sem nome)") + "</span>" +
               '<span class="zap__previa">' + esc(previa) + "</span>" +
               (c.prioridade
                 ? '<span class="zap__tag ' + classeDoGrupo(c.prioridade) + '">' + esc(c.prioridade) + "</span>"
                 : "") +
             "</span></button>";
    }).join("");
  }

  function desenharConversa() {
    var alvo = elemento("zap-conversa");
    var c = conversas.filter(function (x) { return x.id === escolhida; })[0];
    if (!c) {
      alvo.innerHTML = '<p class="zap__vazio">Escolha uma conversa na lista ao lado.</p>';
      return;
    }

    var diaAnterior = "";
    var baloes = c.mensagens.map(function (m) {
      var pedaco = "";
      var dia = soData(m.criada_em);
      if (dia && dia !== diaAnterior) {
        diaAnterior = dia;
        pedaco += '<div class="zap__dia">' + esc(dia) + "</div>";
      }
      var b = textoDoBalao(m);
      pedaco += '<div class="zap__b zap__b--' + (m.direcao === "enviada" ? "nossa" : "dele") +
                (b.vazia ? " zap__b--vazia" : "") + '">' +
                esc(b.texto) +
                "<time>" + esc(soHora(m.criada_em)) + "</time></div>";
      return pedaco;
    }).join("");

    var rodape = "";
    if (c.mensagem) {
      rodape =
        '<div class="zap__rodape">' +
          '<p class="zap__rot">Rascunho — não foi enviado</p>' +
          (c.motivo ? '<p class="zap__porque">' + esc(c.motivo) + "</p>" : "") +
          '<div class="zap__rascunho">' +
            '<textarea id="zap-rascunho" spellcheck="false">' + esc(c.mensagem) + "</textarea>" +
            '<button class="zap__copiar" type="button" id="zap-copiar">Copiar</button>' +
          "</div>" +
        "</div>";
    } else {
      rodape = '<div class="zap__rodape"><p class="zap__porque">' +
               "Esta conversa não entrou na lista de contato manual — não tem rascunho." +
               "</p></div>";
    }

    var fone = String(c.telefone || "").replace(/\D/g, "");
    alvo.innerHTML =
      '<div class="zap__topo">' +
        '<span class="zap__ini">' + esc(iniciais(c.nome)) + "</span>" +
        "<span><h4>" + esc(c.nome || "(sem nome)") + "</h4>" +
        "<small>" + esc(c.imovel || "sem imóvel no cadastro") +
        (c.situacao ? " · " + esc(c.situacao) : "") + "</small></span>" +
        (fone ? '<a class="zap__abrir" href="https://wa.me/' + esc(fone) +
                '" target="_blank" rel="noopener">Abrir no WhatsApp</a>' : "") +
      "</div>" +
      '<div class="zap__baloes" id="zap-baloes">' + baloes + "</div>" +
      rodape;

    // A conversa abre no fim, como no aplicativo: o que interessa é a última
    // fala, não a primeira.
    var caixa = elemento("zap-baloes");
    if (caixa) caixa.scrollTop = caixa.scrollHeight;

    var botao = elemento("zap-copiar");
    if (botao) botao.addEventListener("click", copiarRascunho);
  }

  function copiarRascunho() {
    var campo = elemento("zap-rascunho");
    var botao = elemento("zap-copiar");
    if (!campo) return;
    campo.select();
    // `execCommand` continua aqui de propósito: o painel é servido por
    // localhost/túnel e a área de transferência nova exige contexto seguro.
    var deu = false;
    try { deu = document.execCommand("copy"); } catch (e) { deu = false; }
    if (!deu && navigator.clipboard) {
      navigator.clipboard.writeText(campo.value).then(function () {
        botao.textContent = "Copiado!";
      });
      return;
    }
    botao.textContent = deu ? "Copiado!" : "Copie com Ctrl+C";
    setTimeout(function () { botao.textContent = "Copiar"; }, 2000);
  }

  function escolher(id) {
    escolhida = id;
    desenharLista();
    desenharConversa();
  }

  function carregar() {
    fetch(API + "/api/nai/captacao/conversas")
      .then(function (r) { return r.json(); })
      .then(function (j) {
        conversas = (j && j.conversas) || [];
        var primeira = listaFiltrada()[0];
        escolhida = primeira ? primeira.id : null;
        desenharLista();
        desenharConversa();
      })
      .catch(function () {
        elemento("zap-itens").innerHTML = '<p class="zap__vazio">Não consegui carregar.</p>';
        elemento("zap-conversa").innerHTML = '<p class="zap__vazio">Sem conexão com a API.</p>';
      });
  }

  function refiltrar() {
    var lista = listaFiltrada();
    var continua = lista.some(function (c) { return c.id === escolhida; });
    if (!continua) escolhida = lista.length ? lista[0].id : null;
    desenharLista();
    desenharConversa();
  }

  document.addEventListener("DOMContentLoaded", function () {
    if (!elemento("zap-itens")) return;
    elemento("zap-itens").addEventListener("click", function (e) {
      var item = e.target.closest("[data-lead]");
      if (item) escolher(Number(item.getAttribute("data-lead")));
    });
    elemento("zap-busca").addEventListener("input", refiltrar);
    elemento("zap-so-triagem").addEventListener("change", refiltrar);
    carregar();
  });
})();
