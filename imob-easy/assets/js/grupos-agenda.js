/* ==========================================================================
   Imob Easy — a AGENDA DOS GRUPOS (admin › Grupos)

   Pedro, 03/10/2026: "uma aba Grupos no site, onde eu vou criar e agendar
   mensagens, e o conteúdo da mensagem vou preencher com os imóveis... no
   formato de uma agenda geral lá em cima, e eu podendo filtrar por grupo;
   quero adicionar, excluir, editar, metrificar a mensagem; as métricas são
   quantas pessoas chegaram nas próximas 6 horas que enviei".

   Cada "mensagem" é uma vaga da GRADE do publicador (tabela vagas): horário,
   repetição (todo dia, dias da semana, um dia só), os imóveis e o destino (um
   apelido de grupo, ou vazio = cada imóvel vai aos grupos que aceitam o tipo
   e o valor dele). Quem manda é o cron disparar_grade.sh, no minuto marcado;
   esta tela só cria, edita, apaga e mede. Tudo por /admin/api/grade (senha do
   painel). Os imóveis do seletor vêm de /api/imoveis-para-enviar: só o que a
   Nay oferece, e nunca de parceiro (parceria não sai nos grupos).
   ========================================================================== */
(function () {
  "use strict";

  var API = window.API_BASE || "https://api.imobeasy.online";
  var FUSO = "America/Manaus";
  var DIAS = ["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"];
  var DIAS_LONGOS = ["domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado"];
  var ORDEM_DIAS = [1, 2, 3, 4, 5, 6, 0];          // a semana começa na segunda
  var ROTULO_DESTINO = { alto_padrao: "Alto Padrão", alto_padrao_easy: "Alto Padrão Easy", comercial: "Comercial", easy: "Easy" };

  var $ = function (id) { return document.getElementById(id); };
  function esc(v) {
    return String(v == null ? "" : v).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }
  function pedir(url, opcoes) {
    return fetch(url, Object.assign({ credentials: "same-origin", headers: { "Content-Type": "application/json" } }, opcoes || {}))
      .then(function (r) {
        return r.json().catch(function () { return {}; }).then(function (d) {
          if (r.status === 401) throw new Error("a senha do painel não foi aceita: recarregue a página e entre de novo");
          if (!r.ok && !("ok" in d)) throw new Error(d.erro || ("HTTP " + r.status));
          return d;
        });
      });
  }
  function reais(n) { return "R$ " + Number(n).toLocaleString("pt-BR", { maximumFractionDigits: 0 }); }
  function curto(n) {
    return n >= 1e6 ? (n / 1e6).toLocaleString("pt-BR", { maximumFractionDigits: 2 }) + " mi"
      : n >= 1e4 ? Math.round(n / 1e3).toLocaleString("pt-BR") + " mil" : (n / 1e3).toLocaleString("pt-BR", { maximumFractionDigits: 1 }) + " mil";
  }
  function foto(url, tam) { return url ? String(url).replace("/huge/", "/" + tam + "/") : ""; }
  /* datas em Manaus, como "AAAA-MM-DD" */
  function diaDe(d) {
    var p = new Intl.DateTimeFormat("en-CA", { timeZone: FUSO, year: "numeric", month: "2-digit", day: "2-digit" }).format(d);
    return p;
  }
  function horaDe(d) { return new Intl.DateTimeFormat("pt-BR", { timeZone: FUSO, hour: "2-digit", minute: "2-digit" }).format(d); }
  function somaDias(iso, n) { var d = new Date(iso + "T12:00:00"); d.setDate(d.getDate() + n); return d.toISOString().slice(0, 10); }
  function segundaDe(iso) { var d = new Date(iso + "T12:00:00"); var dow = d.getDay(); return somaDias(iso, dow === 0 ? -6 : 1 - dow); }
  function rotuloDia(iso) {
    var d = new Date(iso + "T12:00:00");
    return DIAS[d.getDay()] + " " + d.toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit" });
  }

  /* ---- estado ---- */
  var semana = segundaDe(diaDe(new Date()));
  var opcoes = { grupos: [], destinos: [] };
  var dados = null;                // a resposta de /admin/api/grade
  var vagasPorId = {};
  var grupoFiltro = "";
  var imoveisCatalogo = null;      // carregado na primeira vez que a janela de editar abre
  var edicao = null;               // { id, lista, escolhidos: [{codigo,titulo,foto,...}] }

  function nomeDoDestino(v) {
    if (v.categoria) return "Lista de " + v.categoria.replace(/_/g, " ") + " (" + (v.negocio === "venda" ? "venda" : "locação") + ")";
    if (!v.destino) return "Todos os grupos que aceitam o imóvel";
    var d = opcoes.destinos.find(function (x) { return x.apelido === v.destino; });
    return (ROTULO_DESTINO[v.destino] || v.destino.replace(/_/g, " ")) + (d && d.grupos.length === 1 ? "" : d ? " (" + d.grupos.length + " grupos)" : "");
  }
  function descreverRepeticao(v) {
    if (v.recorrencia === "diaria") return "todo dia às " + v.horario;
    if (v.recorrencia === "unica") return "em " + new Date(v.data + "T12:00:00").toLocaleDateString("pt-BR") + " às " + v.horario;
    var dias = (v.dias || []).slice().sort(function (a, b) { return ORDEM_DIAS.indexOf(a) - ORDEM_DIAS.indexOf(b); });
    return dias.map(function (d) { return DIAS_LONGOS[d]; }).join(", ").replace(/, ([^,]*)$/, " e $1") + " às " + v.horario;
  }
  /* HORÁRIO LIVRE: vaga da grade sem imóvel (o publicador guarda de reserva e não posta nada) */
  function livre(v) { return !!v && !v.categoria && !(v.imoveis || []).length; }
  function tituloDaVaga(v) {
    if (v.categoria) return nomeDoDestino(v);
    var ims = v.imoveis || [];
    if (!ims.length) return "Horário livre (sem imóvel)";
    return ims.map(function (i) { return i.codigo + (i.titulo ? " · " + i.titulo : ""); }).join(" + ");
  }

  /* o filtro por grupo: o que JÁ saiu conta pelos grupos que receberam; o que vai sair, pelos previstos */
  function passaNoFiltro(o) {
    if (!grupoFiltro) return true;
    var g = opcoes.grupos.find(function (x) { return x.id === grupoFiltro; });
    if (!g) return true;
    if (o.passou && o.posts) return (o.grupos || []).indexOf(g.nome) >= 0;
    var v = vagasPorId[o.vaga];
    return !!v && (v.previstos || []).indexOf(g.id) >= 0;
  }

  /* ---- carregar ---- */
  function carregar() {
    $("ga-periodo").textContent = rotuloDia(semana) + " a " + rotuloDia(somaDias(semana, 6));
    $("ga-agenda").innerHTML = '<p class="ga-carregando">Carregando a agenda…</p>';
    return pedir("/admin/api/grade?de=" + semana + "&ate=" + somaDias(semana, 6))
      .then(function (d) {
        dados = d; vagasPorId = {};
        (d.vagas || []).forEach(function (v) { vagasPorId[v.id] = v; });
        desenhar();
      })
      .catch(function (e) {
        $("ga-agenda").innerHTML = '<p class="ga-erro">Não consegui carregar a agenda: ' + esc(e.message) + "</p>";
      });
  }

  function metricaCurta(o) {
    if (livre(vagasPorId[o.vaga])) return '<span class="ga-st" title="Sem imóvel: nada sai. Edite para pôr imóveis.">livre</span>';
    if (!o.passou) return '<span class="ga-st ga-st--futuro">agendada</span>';
    if (!o.posts) return '<span class="ga-st ga-st--falhou" title="O publicador não postou (imóvel fora do ar, de parceiro ou abaixo da faixa do grupo). Ele avisa o motivo ao Tel no WhatsApp.">não saiu</span>';
    var ng = (o.grupos || []).length;
    return '<span class="ga-st" title="Saiu em ' + ng + (ng === 1 ? " grupo" : " grupos") + '">' + ng + (ng === 1 ? " grupo" : " grupos") + "</span>" +
      '<span class="ga-met" title="Chegaram nas 6 h seguintes' + (o.janela_completa ? "" : " (a janela ainda está aberta)") + '"><b>' +
        (o.pessoas || 0) + "</b> chegaram" + (o.janela_completa ? "" : "…") + "</span>" +
      '<span class="ga-met ga-met--imovel" title="Citaram o post ou escreveram o código"><b>' + (o.pelo_imovel || 0) + "</b> pelo imóvel</span>";
  }

  function desenhar() {
    var oc = (dados.ocorrencias || []).filter(passaNoFiltro);
    // a agenda: uma coluna por dia
    var porDia = {};
    oc.forEach(function (o) { var d = diaDe(new Date(o.quando)); (porDia[d] = porDia[d] || []).push(o); });
    var hoje = diaDe(new Date());
    $("ga-agenda").innerHTML = '<div class="ga-semana">' + [0, 1, 2, 3, 4, 5, 6].map(function (k) {
      var dia = somaDias(semana, k), lista = porDia[dia] || [];
      return '<div class="ga-dia' + (dia === hoje ? " ga-dia--hoje" : "") + (dia < hoje ? " ga-dia--passado" : "") + '">' +
        '<div class="ga-dia__topo">' + esc(rotuloDia(dia)) + (lista.length ? ' <span class="ga-dia__n">' + lista.length + "</span>" : "") + "</div>" +
        (lista.length ? lista.map(cartao).join("") : '<p class="ga-dia__vazio">nada agendado</p>') + "</div>";
    }).join("") + "</div>";

    // o resumo da semana
    var saiu = oc.filter(function (o) { return o.passou && o.posts; });
    var soma = function (k) { return saiu.reduce(function (s, o) { return s + (o[k] || 0); }, 0); };
    $("ga-resumo").innerHTML =
      '<div class="ga-cartao-num"><b>' + oc.length + "</b><span>envios na semana" + (grupoFiltro ? " (neste grupo)" : "") + "</span></div>" +
      '<div class="ga-cartao-num"><b>' + saiu.length + "</b><span>já saíram</span></div>" +
      '<div class="ga-cartao-num"><b>' + oc.filter(function (o) { return o.passou && !o.posts && !livre(vagasPorId[o.vaga]); }).length + '</b><span>não saíram</span></div>' +
      '<div class="ga-cartao-num ga-cartao-num--destaque"><b>' + soma("pelo_imovel") + "</b><span>chegaram pelo imóvel (6 h)</span></div>" +
      '<div class="ga-cartao-num"><b>' + soma("novos") + "</b><span>pessoas novas (6 h)</span></div>";

    // a tabela: uma linha por mensagem (vaga), com a soma da semana
    var porVaga = {};
    oc.forEach(function (o) { (porVaga[o.vaga] = porVaga[o.vaga] || []).push(o); });
    var vagas = (dados.vagas || []).filter(function (v) { return porVaga[v.id] || !grupoFiltro; });
    $("ga-tabela").innerHTML = vagas.length ? vagas.map(function (v) {
      var os = (porVaga[v.id] || []).filter(function (o) { return o.passou && o.posts; });
      var s = function (k) { return os.reduce(function (t, o) { return t + (o[k] || 0); }, 0); };
      return "<tr>" +
        "<td>" + esc(descreverRepeticao(v)) + "</td>" +
        '<td class="ga-tab-imoveis">' + imoveisMini(v) + "</td>" +
        "<td>" + esc(nomeDoDestino(v)) + "</td>" +
        '<td class="num">' + os.length + "</td>" +
        '<td class="num">' + s("pessoas") + "</td>" +
        '<td class="num">' + s("novos") + "</td>" +
        '<td class="num"><b>' + s("pelo_imovel") + "</b></td>" +
        '<td class="col-acoes"><button type="button" class="btn-mini" data-editar="' + v.id + '">Editar</button> ' +
          '<button type="button" class="btn-mini btn-mini--perigo" data-excluir="' + v.id + '">Excluir</button></td></tr>';
    }).join("") : '<tr><td colspan="8" class="ga-dica">Nenhuma mensagem para esse grupo.</td></tr>';
  }

  function imoveisMini(v) {
    if (v.categoria) return '<span class="ga-dica">' + esc(nomeDoDestino(v)) + "</span>";
    if (livre(v)) return '<span class="ga-dica">Horário livre (sem imóvel)</span>';
    return (v.imoveis || []).map(function (i) {
      var alerta = i.parceiro ? "de parceiro: não sai" : i.no_ar === false ? "fora do ar: não sai" : i.existe === false ? "não existe" : "";
      return '<span class="ga-im' + (alerta ? " ga-im--alerta" : "") + '" title="' + esc(alerta || i.titulo || "") + '">' +
        (i.foto ? '<img src="' + esc(foto(i.foto, "small")) + '" alt="" loading="lazy">' : "") + "<b>" + esc(i.codigo) + "</b>" +
        (i.titulo ? "<small>" + esc(i.titulo) + "</small>" : "") + (alerta ? "<em>" + esc(alerta) + "</em>" : "") + "</span>";
    }).join("");
  }

  function cartao(o) {
    var v = vagasPorId[o.vaga] || {};
    var q = new Date(o.quando);
    return '<button type="button" class="ga-cartao' + (livre(v) ? " ga-cartao--livre" : o.passou ? (o.posts ? " ga-cartao--saiu" : " ga-cartao--falhou") : "") +
        '" data-ocorrencia="' + esc(o.vaga + "|" + o.quando) + '">' +
      '<span class="ga-cartao__hora">' + horaDe(q) + (v.recorrencia === "diaria" ? ' <i title="todo dia">↻</i>' : v.recorrencia === "semanal" ? ' <i title="dias da semana">↻</i>' : "") + "</span>" +
      '<span class="ga-cartao__tit">' + esc(tituloDaVaga(v)) + "</span>" +
      '<span class="ga-cartao__dest">' + esc(nomeDoDestino(v)) + "</span>" +
      '<span class="ga-cartao__met">' + metricaCurta(o) + "</span>" +
    "</button>";
  }

  /* ---- detalhe de um envio ---- */
  function abrirDetalhe(chave) {
    var p = chave.split("|"), o = (dados.ocorrencias || []).find(function (x) { return String(x.vaga) === p[0] && x.quando === p[1]; });
    if (!o) return;
    var v = vagasPorId[o.vaga] || {}, q = new Date(o.quando);
    $("ga-det-tit").textContent = q.toLocaleDateString("pt-BR", { timeZone: FUSO, weekday: "long", day: "2-digit", month: "2-digit" }) + " às " + horaDe(q);
    var grupos = o.passou && o.posts ? (o.grupos || [])
      : (v.previstos || []).map(function (id) { var g = opcoes.grupos.find(function (x) { return x.id === id; }); return g ? g.nome : null; }).filter(Boolean);
    $("ga-det-corpo").innerHTML =
      '<div class="ga-det-imoveis">' + imoveisMini(v) + "</div>" +
      '<p class="ga-dica">' + esc(descreverRepeticao(v)) + " · " + esc(nomeDoDestino(v)) + "</p>" +
      (livre(v)
        ? '<p class="ga-dica">Horário livre da grade: sem imóvel, nada sai. Clique em Editar para pôr imóveis nele.</p>'
        : o.passou
        ? (o.posts
          ? '<div class="ga-det-num"><div><b>' + (o.pessoas || 0) + "</b><span>chegaram em 6 h</span></div>" +
              "<div><b>" + (o.novos || 0) + "</b><span>pessoas novas</span></div>" +
              '<div class="ga-det-num__destaque"><b>' + (o.pelo_imovel || 0) + "</b><span>pelo imóvel</span></div></div>" +
              (o.janela_completa ? "" : '<p class="ga-dica">As 6 h ainda não acabaram: os números vão subir.</p>')
          : '<p class="ga-erro">Não saiu. O publicador recusa imóvel fora do ar, de parceiro ou abaixo da faixa do grupo, e avisa o motivo ao Tel no WhatsApp.</p>')
        : '<p class="ga-dica">Ainda vai sair. As métricas aparecem depois do envio.</p>') +
      "<h3>" + (o.passou && o.posts ? "Saiu em " + grupos.length + " grupos" : "Grupos previstos (" + grupos.length + ")") + "</h3>" +
      '<ul class="ga-det-grupos">' + grupos.map(function (n) { return "<li>" + esc(n) + "</li>"; }).join("") + "</ul>" +
      (o.passou && o.posts ? "" : '<p class="ga-dica">Sem destino, cada imóvel vai só aos grupos que aceitam o tipo e o valor dele: a lista exata sai na hora do envio.</p>') +
      '<div class="ga-dialogo__acoes"><button type="button" class="btn-mini btn-mini--perigo" data-excluir="' + v.id + '">Excluir a mensagem</button>' +
        '<button type="button" class="btn-azul" data-editar="' + v.id + '">Editar</button></div>';
    abrirDialogo($("ga-detalhe"));
  }

  /* ---- criar e editar ---- */
  function abrirEditor(v) {
    edicao = { id: v ? v.id : null, lista: !!(v && v.categoria), escolhidos: v && !v.categoria ? (v.imoveis || []).map(function (i) {
      return { codigo: String(i.codigo), titulo: i.titulo, foto: i.foto, bairro: i.bairro, venda: i.venda, aluguel: i.aluguel };
    }) : [] };
    $("ga-ed-tit").textContent = v ? "Editar mensagem" : "Nova mensagem";
    $("ga-ed-imoveis").hidden = edicao.lista;
    $("ga-ed-destino").hidden = edicao.lista;
    $("ga-ed-lista").hidden = !edicao.lista;
    $("ga-ed-lista").textContent = edicao.lista ? nomeDoDestino(v) + ": a lista é montada pelo publicador na hora; aqui só muda o quando." : "";
    $("ga-hora").value = v ? v.horario : "08:00";
    var rec = v ? v.recorrencia : "diaria";
    document.querySelectorAll('#ga-form input[name="rec"]').forEach(function (r) { r.checked = r.value === rec; });
    $("ga-dias").innerHTML = ORDEM_DIAS.map(function (d) {
      var on = v && (v.dias || []).indexOf(d) >= 0;
      return '<label class="ga-dia-chip"><input type="checkbox" value="' + d + '"' + (on ? " checked" : "") + "><span>" + DIAS[d] + "</span></label>";
    }).join("");
    $("ga-data").value = v && v.data ? v.data : somaDias(diaDe(new Date()), 1);
    $("ga-data").min = diaDe(new Date());
    $("ga-destino").innerHTML = '<option value="">Todos os grupos que aceitam o imóvel</option>' + opcoes.destinos.map(function (d) {
      return '<option value="' + esc(d.apelido) + '">' + esc(ROTULO_DESTINO[d.apelido] || d.apelido) + " — " + esc(d.grupos.join(", ")) + "</option>";
    }).join("");
    $("ga-destino").value = v && v.destino ? v.destino : "";
    $("ga-busca").value = ""; $("ga-achados").innerHTML = ""; $("ga-erro").textContent = "";
    mostrarRepeticao(); desenharEscolhidos(); resumoDoEditor();
    abrirDialogo($("ga-editor"));
    if (!edicao.lista && !imoveisCatalogo) {
      fetch(API + "/api/imoveis-para-enviar").then(function (r) { return r.json(); })
        .then(function (d) { imoveisCatalogo = d.imoveis || []; })
        .catch(function () { imoveisCatalogo = []; $("ga-achados").innerHTML = '<p class="ga-erro">Não consegui carregar os imóveis.</p>'; });
    }
    setTimeout(function () { (edicao.lista ? $("ga-hora") : $("ga-busca")).focus(); }, 50);
  }

  function recAtual() { var r = document.querySelector('#ga-form input[name="rec"]:checked'); return r ? r.value : "diaria"; }
  function mostrarRepeticao() {
    $("ga-dias").hidden = recAtual() !== "semanal";
    $("ga-data-rot").hidden = recAtual() !== "unica";
  }
  function diasMarcados() {
    return Array.prototype.map.call(document.querySelectorAll("#ga-dias input:checked"), function (c) { return Number(c.value); });
  }
  function resumoDoEditor() {
    var v = { horario: $("ga-hora").value || "--:--", recorrencia: recAtual(), dias: diasMarcados(), data: $("ga-data").value,
              destino: $("ga-destino").value, categoria: null };
    var n = edicao.escolhidos.length;
    $("ga-resumo-ed").textContent = (edicao.lista ? "Vai sair " : (n ? n + (n === 1 ? " imóvel" : " imóveis") + ", " : "Escolha os imóveis. ")) +
      (v.recorrencia === "semanal" && !v.dias.length ? "escolha os dias" : v.recorrencia === "unica" && !v.data ? "escolha o dia" : descreverRepeticao(v)) +
      (edicao.lista ? "." : ", para " + nomeDoDestino(v).toLowerCase() + ".");
    var d = opcoes.destinos.find(function (x) { return x.apelido === v.destino; });
    $("ga-destino-dica").textContent = v.destino
      ? "Vai para: " + (d ? d.grupos.join(", ") : v.destino) + ". O Comercial só aceita imóvel comercial e o Alto Padrão tem valor mínimo: o publicador confere na hora."
      : "Cada imóvel vai aos grupos que aceitam o tipo e o valor dele (venda, locação, condomínio, comercial).";
  }

  function desenharEscolhidos() {
    $("ga-escolhidos").innerHTML = edicao.escolhidos.length ? edicao.escolhidos.map(function (i, k) {
      return '<span class="ga-escolhido">' + (i.foto ? '<img src="' + esc(foto(i.foto, "small")) + '" alt="">' : "") +
        "<b>" + esc(i.codigo) + "</b><small>" + esc(i.titulo || "") + "</small>" +
        '<button type="button" data-tirar="' + k + '" aria-label="Tirar o ' + esc(i.codigo) + '">×</button></span>';
    }).join("") : '<p class="ga-dica">Nenhum imóvel ainda.</p>';
  }

  function procurar(q) {
    var alvo = $("ga-achados");
    q = String(q || "").trim().toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
    if (!q) { alvo.innerHTML = ""; return; }
    if (!imoveisCatalogo) { alvo.innerHTML = '<p class="ga-dica">Carregando os imóveis…</p>'; return; }
    var ja = edicao.escolhidos.map(function (i) { return i.codigo; });
    var achados = imoveisCatalogo.filter(function (m) {
      var t = (m.codigo + " " + (m.condominio || "") + " " + (m.bairro || "") + " " + (m.titulo || "")).toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
      return t.indexOf(q) >= 0 && ja.indexOf(String(m.codigo)) < 0;
    }).slice(0, 8);
    alvo.innerHTML = achados.length ? achados.map(function (m) {
      var valor = m.venda ? "venda " + curto(m.venda) : m.aluguel ? "aluguel " + reais(m.aluguel) : "";
      return '<button type="button" class="ga-achado" data-escolher="' + esc(m.codigo) + '">' +
        (m.foto ? '<img src="' + esc(foto(m.foto, "small")) + '" alt="">' : '<span class="ga-sem-foto"></span>') +
        "<span><b>" + esc(m.codigo) + " · " + esc(m.condominio || m.tipo || "") + "</b><small>" + esc([m.bairro, valor].filter(Boolean).join(" · ")) + "</small></span></button>";
    }).join("") : '<p class="ga-dica">Nada encontrado entre os imóveis que a Nay oferece (imóvel de parceiro não sai nos grupos).</p>';
  }

  function salvar(e) {
    e.preventDefault();
    var corpo = { horario: $("ga-hora").value, recorrencia: recAtual(), dias: diasMarcados(), data: $("ga-data").value,
                  destino: $("ga-destino").value, codigos: edicao.escolhidos.map(function (i) { return i.codigo; }) };
    $("ga-erro").textContent = "";
    $("ga-salvar").disabled = true;
    pedir(edicao.id ? "/admin/api/grade/" + edicao.id : "/admin/api/grade", { method: edicao.id ? "PUT" : "POST", body: JSON.stringify(corpo) })
      .then(function (r) {
        if (!r.ok) { $("ga-erro").textContent = r.erro || "Não salvou."; return; }
        fecharDialogo($("ga-editor"));
        return carregar();
      })
      .catch(function (e2) { $("ga-erro").textContent = e2.message; })
      .then(function () { $("ga-salvar").disabled = false; });
  }

  function excluir(id) {
    var v = vagasPorId[id];
    if (!v || !window.confirm("Excluir esta mensagem?\n\n" + tituloDaVaga(v) + "\n" + descreverRepeticao(v) + "\n\nEla para de sair nos grupos. O que já saiu continua medido.")) return;
    pedir("/admin/api/grade/" + id, { method: "DELETE" })
      .then(function (r) {
        if (!r.ok) { window.alert(r.erro || "Não excluiu."); return; }
        fecharDialogo($("ga-detalhe"));
        return carregar();
      })
      .catch(function (e) { window.alert(e.message); });
  }

  /* ---- janelas ---- */
  function abrirDialogo(d) { if (d.showModal) { if (!d.open) d.showModal(); } else d.setAttribute("open", ""); }
  function fecharDialogo(d) { if (d.close) d.close(); else d.removeAttribute("open"); }

  /* ---- eventos ---- */
  document.addEventListener("click", function (e) {
    var t = e.target.closest ? e.target.closest("button, [data-fechar]") : null;
    if (!t) { if (e.target.tagName === "DIALOG") fecharDialogo(e.target); return; }
    if (t.hasAttribute("data-fechar")) { fecharDialogo(t.closest("dialog")); return; }
    if (t.dataset.ocorrencia) { abrirDetalhe(t.dataset.ocorrencia); return; }
    if (t.dataset.editar) { fecharDialogo($("ga-detalhe")); abrirEditor(vagasPorId[t.dataset.editar]); return; }
    if (t.dataset.excluir) { excluir(t.dataset.excluir); return; }
    if (t.dataset.escolher) {
      if (edicao.escolhidos.length >= 10) { $("ga-erro").textContent = "No máximo 10 imóveis por mensagem."; return; }
      var m = (imoveisCatalogo || []).find(function (x) { return String(x.codigo) === t.dataset.escolher; });
      if (m) edicao.escolhidos.push({ codigo: String(m.codigo), titulo: m.condominio || m.tipo, foto: m.foto, bairro: m.bairro, venda: m.venda, aluguel: m.aluguel });
      $("ga-busca").value = ""; $("ga-achados").innerHTML = ""; $("ga-busca").focus();
      desenharEscolhidos(); resumoDoEditor(); return;
    }
    if (t.dataset.tirar != null) { edicao.escolhidos.splice(Number(t.dataset.tirar), 1); desenharEscolhidos(); resumoDoEditor(); return; }
    if (t.id === "ga-nova") abrirEditor(null);
    if (t.id === "ga-ant") { semana = somaDias(semana, -7); carregar(); }
    if (t.id === "ga-prox") { semana = somaDias(semana, 7); carregar(); }
    if (t.id === "ga-hoje") { semana = segundaDe(diaDe(new Date())); carregar(); }
  });
  $("ga-busca").addEventListener("input", function () { procurar(this.value); });
  $("ga-busca").addEventListener("keydown", function (e) {
    if (e.key === "Enter") { e.preventDefault(); var b = $("ga-achados").querySelector("[data-escolher]"); if (b) b.click(); }
  });
  $("ga-form").addEventListener("change", function (e) {
    if (e.target.name === "rec") mostrarRepeticao();
    resumoDoEditor();
  });
  $("ga-hora").addEventListener("input", resumoDoEditor);
  $("ga-form").addEventListener("submit", salvar);
  $("ga-grupo").addEventListener("change", function () { grupoFiltro = this.value; if (dados) desenhar(); });

  /* ---- começar ---- */
  pedir("/admin/api/grade/opcoes")
    .then(function (o) {
      opcoes = { grupos: o.grupos || [], destinos: o.destinos || [] };
      $("ga-grupo").innerHTML = '<option value="">Todos os grupos</option>' + opcoes.grupos.filter(function (g) { return g.ativo; }).map(function (g) {
        return '<option value="' + esc(g.id) + '">' + esc(g.nome) + "</option>";
      }).join("");
    })
    .catch(function () { /* sem as opções, a agenda ainda aparece */ })
    .then(carregar);
})();
