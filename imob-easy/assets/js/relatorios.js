/* Relatórios das DUAS Nays (12/09/2026, pedido do Tel).
   São dois números e dois assuntos: a Nay Locação atende corretor, a Nay
   Captação fala com proprietário. Os números não se misturam nesta tela.
   Fonte: /api/painel/atendimento (views vw_painel_*). Só leitura. */
(function () {
  "use strict";
  var DIAS_PT = ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"];

  function esc(t) {
    return String(t == null ? "" : t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }
  function dataPt(iso) {
    var p = String(iso).split("-");
    var d = new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]));
    return DIAS_PT[d.getDay()] + " " + p[2] + "/" + p[1];
  }
  function cartao(n, rotulo) {
    return '<div class="painel-cartao"><div class="painel-cartao__n">' + esc(n) +
           '</div><div class="painel-cartao__r">' + esc(rotulo) + "</div></div>";
  }
  function barra(valor, maximo, cor) {
    var pct = maximo > 0 ? Math.round((valor / maximo) * 100) : 0;
    return '<div class="painel-barra"><span class="num" style="min-width:2.2em">' + valor + "</span>" +
           '<span class="painel-barra__t"><span class="painel-barra__p" style="width:' + pct +
           "%;background:" + cor + '"></span></span></div>';
  }
  function selo(id, texto, tipo) {
    var el = document.getElementById(id);
    el.textContent = texto;
    el.className = "selo selo--" + tipo;
  }

  function pintar(d) {
    var r = d.resumo || {}, serie = d.dias || [];
    var hoje = r.hoje || {}, sete = r["7d"] || {};
    var loc = d.locacao || {}, cap = d.captacao || {};

    /* ---------------- Nay Locação ---------------- */
    if (loc.whatsapp_pausado) {
      selo("selo-locacao", "WhatsApp pausado", "off");
      document.getElementById("nota-locacao").textContent =
        "O WhatsApp de atendimento está pausado: a mensagem do corretor continua sendo gravada e aparece aqui, " +
        "mas ninguém recebe resposta automática. A IA de locação está em modo " + (loc.ia_modo || "?") +
        (loc.ia_modo === "teste" ? ", só com " + loc.numeros_teste + " número de teste." : ".");
    } else {
      selo("selo-locacao", "atendendo", "on");
      document.getElementById("nota-locacao").textContent =
        "IA de locação em modo " + (loc.ia_modo || "?") +
        (loc.ia_pausada ? " (envio pausado: ela grava, mas não manda nada)." : ".");
    }

    document.getElementById("cartoes-loc-hoje").innerHTML =
      cartao(hoje.corretores, "corretores falaram com a Nay") +
      cartao(hoje.mensagens_recebidas, "mensagens recebidas") +
      cartao(hoje.corretores_falaram_de_visita, "citaram visita") +
      cartao(hoje.visitas_pedidas, "visitas agendadas");
    document.getElementById("cartoes-loc-sete").innerHTML =
      cartao(sete.corretores, "corretores diferentes") +
      cartao(sete.mensagens_recebidas, "mensagens recebidas") +
      cartao(sete.corretores_falaram_de_visita, "citaram visita") +
      cartao(sete.visitas_pedidas, "visitas agendadas") +
      cartao(sete.visitas_confirmadas, "visitas confirmadas");

    var maiorLoc = serie.reduce(function (m, x) { return Math.max(m, x.corretores); }, 0);
    document.getElementById("corpo-locacao").innerHTML = serie.map(function (x) {
      return "<tr><td>" + esc(dataPt(x.dia)) + "</td>" +
        "<td>" + barra(x.corretores, maiorLoc, "#2563eb") + "</td>" +
        '<td class="num">' + x.corretores_novos + "</td>" +
        '<td class="num">' + x.mensagens_recebidas + "</td>" +
        '<td class="num">' + x.corretores_falaram_de_visita + "</td>" +
        '<td class="num">' + x.visitas_pedidas + "</td>" +
        '<td class="num">' + x.visitas_confirmadas + "</td>" +
        '<td class="num">' + x.visitas_urgentes + "</td></tr>";
    }).join("") || '<tr><td colspan="8">Sem dados.</td></tr>';

    var aviso = document.getElementById("aviso-visitas");
    if (d.visitas_modo && d.visitas_modo !== "todos") {
      aviso.innerHTML = "<strong>Visitas agendadas ainda não têm número real.</strong> Quem agenda visita é a IA de " +
        "locação, e ela está em <strong>modo " + esc(d.visitas_modo) + "</strong>" +
        (d.visitas_numeros ? " (só " + esc(d.visitas_numeros) + ")" : "") +
        ". Enquanto isso, use a coluna “falaram de visita”, que conta os corretores que pediram visita na conversa.";
      aviso.hidden = false;
    }

    /* ---------------- Nay Captação ---------------- */
    if (cap.pausada) selo("selo-captacao", "pausada", "off");
    else if (cap.modo_teste) selo("selo-captacao", "modo teste", "teste");
    else selo("selo-captacao", "rodando", "on");
    document.getElementById("nota-captacao").textContent = cap.modo_teste
      ? "Em modo teste: todo disparo vai para o número de teste, não para os proprietários."
      : "Campanha rodando, com disparo e lembrete dentro do horário combinado.";

    document.getElementById("cartoes-cap-hoje").innerHTML =
      cartao(hoje.captacao_disparos, "disparos enviados") +
      cartao(hoje.captacao_responderam, "proprietários responderam") +
      cartao(hoje.captacao_com_o_tel, "conversas foram para o Tel");
    document.getElementById("cartoes-cap-sete").innerHTML =
      cartao(sete.captacao_disparos, "disparos enviados") +
      cartao(sete.captacao_responderam, "proprietários responderam") +
      cartao(sete.captacao_com_o_tel, "conversas foram para o Tel");

    var maiorCap = serie.reduce(function (m, x) { return Math.max(m, x.captacao_disparos); }, 0);
    document.getElementById("corpo-captacao").innerHTML = serie.map(function (x) {
      return "<tr><td>" + esc(dataPt(x.dia)) + "</td>" +
        "<td>" + barra(x.captacao_disparos, maiorCap, "#7c3aed") + "</td>" +
        '<td class="num">' + x.captacao_responderam + "</td>" +
        '<td class="num">' + x.captacao_com_o_tel + "</td></tr>";
    }).join("") || '<tr><td colspan="4">Sem dados.</td></tr>';
  }

  if (!window.API_BASE) { return; }
  fetch(window.API_BASE + "/api/painel/atendimento?dias=30")
    .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
    .then(pintar)
    .catch(function () {
      document.getElementById("corpo-locacao").innerHTML = '<tr><td colspan="8">Não foi possível carregar.</td></tr>';
      document.getElementById("corpo-captacao").innerHTML = '<tr><td colspan="4">Não foi possível carregar.</td></tr>';
    });
})();
