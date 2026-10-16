/* ==========================================================================
   Imob Easy — admin › Grupos › CAPTAÇÃO ATIVA

   Pedro, 09/10/2026: "Ler solicitações de corretores nos grupos de WhatsApp
   (imóveis que eles procuram para clientes), comparar com o MEU catálogo e dar
   uma nota de 0 a 100 de semelhança. Lista vertical, uma solicitação embaixo
   da outra, mais recente primeiro. ESQUERDA: texto original do corretor,
   grupo, nome/telefone, data/hora e a ficha extraída. DIREITA: o melhor imóvel
   meu (foto, endereço, preço, quartos), nota % e o detalhamento da nota."

   Quem lê, extrai e pontua é o serviço nay-grupos (Python, na VPS). Esta tela
   só mostra o que ele gravou e guarda o que o Pedro julga: "Leitura correta /
   errada", rejeitar, os testes colados e os apelidos. Tudo por
   /admin/api/grupos/captacao (senha do painel).

   NADA É ENVIADO SOZINHO: o serviço não tem por onde enviar. O envio é MANUAL
   (Pedro, 09/10 à noite: "põe um botão de enviar manualmente; eu já tinha
   deixado a msg padrão"): o botão "Enviar ao corretor" abre a conferência com
   a mensagem padrão dele, e só o clique em "Enviar agora" chama o banco
   (site_captacao_grupos_enviar, 339), que tem as travas e põe a abertura, o
   card e as fotos na caixa de saída da Nay, pelo número da Parceria.
   ========================================================================== */
(function () {
  "use strict";

  var API = window.API_BASE || "https://api.imobeasy.online";
  var FUSO = "America/Manaus";
  var painel = document.querySelector('[data-painel="captacao"]');
  if (!painel) return;

  var $ = function (id) { return document.getElementById(id); };
  var estado = { filtro: "todos", dados: null, pedido: 0, carregou: false, fotos: {}, demandaDias: 30, nota: 0, ordem: "recentes" };
  /* 371: a nota mínima e a ordem ficam lembradas neste navegador */
  try {
    estado.nota = parseInt(localStorage.getItem("gc-nota"), 10) || 0;
    estado.ordem = localStorage.getItem("gc-ordem") === "nota" ? "nota" : "recentes";
  } catch (e) { /* sem armazenamento: fica o padrão */ }

  var ROTULO = { operacao: "Operação", tipo: "Tipo", bairros: "Bairros", condominio: "Condomínio", quartos: "Quartos",
                 preco_max: "Teto", mobiliado: "Mobiliado", andar: "Andar", suite: "Suíte", vagas: "Vagas", pet: "Pet", contato: "Contato" };
  var ORDEM = ["operacao", "tipo", "bairros", "condominio", "quartos", "preco_max", "mobiliado", "andar", "suite", "vagas", "pet", "contato"];
  var CRITERIO = { preco: "Preço", local: "Local", quartos: "Quartos", mobiliado: "Mobília", andar: "Andar", extras: "Extras" };
  var COMO = { apelido: "pelo apelido", exato: "", lugar: "conjunto/região", parecido: "parecido", pedaco: "pedaço do nome" };
  var ETAPA = { operacao: "para a operação", tipo: "do tipo", local: "no local", quartos: "com os quartos", preco: "no preço", financiamento: "que aceitam financiamento", confirmado: "confirmados" };

  function esc(v) {
    return String(v == null ? "" : v).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }
  function pedir(url, opcoes) {
    return fetch(url, Object.assign({ credentials: "same-origin", headers: { "Content-Type": "application/json" } }, opcoes || {}))
      .then(function (r) {
        return r.json().catch(function () { return {}; }).then(function (d) {
          if (r.status === 401) throw new Error("a senha do painel não foi aceita: recarregue a página e entre de novo");
          if (!r.ok) throw new Error(d.erro || ("HTTP " + r.status));
          return d;
        });
      });
  }
  function reais(n) { return n == null ? "" : "R$ " + Number(n).toLocaleString("pt-BR", { maximumFractionDigits: 0 }); }
  function quando(iso) {
    if (!iso) return "";
    var d = new Date(iso);
    return d.toLocaleString("pt-BR", { timeZone: FUSO, day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });
  }
  function fone(t) {
    var d = String(t || "").replace(/\D/g, "").replace(/^55/, "");
    if (d.length < 10) return t || "";
    return "(" + d.slice(0, 2) + ") " + d.slice(2, d.length - 4) + "-" + d.slice(-4);
  }

  function manual() { return !!(estado.dados && estado.dados.config && estado.dados.config.envio_manual === true); }
  /* por que este imóvel não pode ser enviado a este pedido (null = pode) */
  function naoPodeEnviar(p, codigo) {
    if (!manual()) return "O envio manual está desligado na configuração.";
    if (p.fonte === "teste") return "Teste colado na tela: não tem corretor para receber.";
    if (!codigo) return "Sem imóvel compatível para enviar.";
    if (!p.telefone) return "A mensagem veio sem o telefone de quem escreveu: fale com a pessoa pelo grupo.";
    if (p.estado === "rejeitado") return "Solicitação rejeitada: desfaça a rejeição para enviar.";
    if ((p.ofertas || []).some(function (o) { return o.codigo === codigo; })) return "Este imóvel já foi enviado para este pedido.";
    return null;
  }

  /* ── o topo: modo, serviço, de onde vêm as mensagens, taxa de acerto ── */
  function desenharTopo(d) {
    var h = [];
    h.push(manual()
      ? '<span class="gc-selo gc-selo--treino" title="O leitor só lê, extrai, pontua e mostra. Mensagem só sai quando você clica em Enviar ao corretor.">ENVIO SÓ MANUAL · nada sai sozinho</span>'
      : '<span class="gc-selo gc-selo--treino" title="O envio manual está desligado em config.json (envio_manual).">MODO TREINO · nada é enviado</span>');
    h.push(d.servico_vivo
      ? '<span class="gc-selo gc-selo--ok" title="Última passada: ' + esc(quando(d.batimento)) + '">leitor ligado</span>'
      : '<span class="gc-selo gc-selo--ruim">leitor parado' + (d.batimento ? " desde " + esc(quando(d.batimento)) : "") + "</span>");
    var c = d.contagem || {};
    h.push('<span class="gc-selo" title="A mesma mensagem colada em vários grupos (mesmo corretor, mesmo texto) conta uma vez só">' + (c.todos || 0) +
           " solicitações nas últimas " + d.horas + " h" +
           (c.mensagens > c.todos ? " · " + c.mensagens + " mensagens, " + c.juntadas + " repetidas em vários grupos" : "") + "</span>");
    if (c.nota_min) h.push('<span class="gc-selo gc-selo--ok">' + (c.com_a_nota || 0) + " com nota ≥ " + c.nota_min + "</span>");
    var a = d.acerto || {};
    if (a.julgados) {
      h.push('<span class="gc-selo" title="Só o último julgamento de cada solicitação conta">leitura certa em ' + a.corretas + " de " + a.julgados +
             " julgadas (" + Math.round(a.corretas * 100 / a.julgados) + "%)</span>");
    }
    var f = d.fonte || {};
    if (f.na_fila) h.push('<span class="gc-selo gc-selo--lendo">lendo… faltam ' + f.na_fila + (f.na_fila === 1 ? " mensagem" : " mensagens") + "</span>");
    if (f.importadas) {
      h.push('<span class="gc-selo" title="Mensagens de conversa exportada do WhatsApp">' + f.importadas + " mensagens importadas de " + f.grupos_importados +
             (f.grupos_importados === 1 ? " grupo" : " grupos") + " · " + (f.nao_eram_pedido || 0) + " não eram pedido" +
             (f.com_erro ? " · " + f.com_erro + " a IA não leu" : "") + "</span>");
    }
    if ($("gc-imp-horas")) $("gc-imp-horas").textContent = d.horas;
    if (!f.com_texto && !f.importadas) {
      h.push('<div class="gc-aviso"><b>Os grupos não estão entregando o texto das mensagens.</b> Nas últimas ' + d.horas + " h chegaram " +
             (f.mensagens || 0) + " avisos de " + (f.grupos || 0) + " grupos (entrou, saiu, apagou) e nenhuma mensagem com texto: a Z-API da Parceria não está " +
             "repassando o conteúdo dos grupos. Enquanto isso não for ligado, só aparecem aqui a conversa exportada (logo abaixo) e as mensagens coladas em <b>Testar uma mensagem</b>.</div>");
    } else if (f.com_texto) {
      h.push('<span class="gc-selo">' + f.com_texto + " mensagens com texto de " + f.grupos + " grupos · " + (f.lidas || 0) + " lidas</span>");
    }
    if (d.aviso) h.push('<div class="gc-aviso"><b>Configuração:</b> ' + esc(d.aviso) + "</div>");
    $("gc-topo").innerHTML = h.join("");

    var botoes = $("gc-filtros").querySelectorAll("[data-filtro]");
    var conta = { todos: c.todos, verde: c.verde, amarelo: c.amarelo, sem_match: c.sem_match, teste: c.teste };
    var cortes = (d.config && d.config.cortes) || { verde: 90, amarelo: 70 };
    var nome = { todos: "Todas", verde: "Nota ≥ " + cortes.verde, amarelo: cortes.amarelo + " a " + (cortes.verde - 1), sem_match: "Sem match", teste: "Testes" };
    Array.prototype.forEach.call(botoes, function (b) {
      var k = b.getAttribute("data-filtro");
      b.textContent = nome[k] + " (" + (conta[k] || 0) + ")";
      b.setAttribute("aria-pressed", k === estado.filtro ? "true" : "false");
    });
  }

  /* ── o desenho de cada solicitação ──
     Pedro, 09/10/2026 (depois de ver a primeira versão): "você colocou vários números um por cima do outro;
     agrupa em categorias para eu ler de forma melhor, pode ser até com bordas de cores diferentes, e as
     informações principais destacadas".
     Cada lado tem uma MANCHETE (o que ele quer / o imóvel e a nota) e, embaixo, caixas por assunto, cada uma
     com a sua cor: Negócio, Onde, Imóvel, Contato; e do outro lado Imóvel, Por que essa nota, Alternativas. */
  function valorDoCampo(campo, v) {
    if (v == null || (Array.isArray(v) && !v.length)) return null;
    if (campo === "preco_max") return "até " + reais(v);
    if (campo === "operacao") return v === "aluguel" ? "Aluguel" : "Venda";
    if (campo === "tipo") return { apartamento: "Apartamento", casa: "Casa", sala: "Sala / loja", outro: "Outro" }[v] || v;
    if (campo === "bairros") return v.join(" ou ");
    if (campo === "andar") return v.map(function (a) { return { terreo: "térreo", "1_andar": "1º andar", qualquer: "qualquer" }[a] || a; }).join(" ou ");
    if (campo === "mobiliado") return v ? "sim" : "não (sem mobília)";
    if (campo === "suite" || campo === "pet") return v ? "sim" : "não";
    return String(v);
  }
  function linha(rotulo, valor, duvidoso) {
    return '<div class="gc-linha' + (duvidoso ? " gc-linha--duvidoso" : "") + '"><dt>' + esc(rotulo) + "</dt><dd>" + valor +
           (duvidoso ? ' <em class="gc-duvida">duvidoso</em>' : "") + "</dd></div>";
  }
  function caixa(cor, titulo, corpo) {
    return corpo ? '<section class="gc-caixa gc-caixa--' + cor + '"><h3>' + esc(titulo) + "</h3>" + corpo + "</section>" : "";
  }
  function campos(p, lista) {
    var ficha = p.ficha || {}, duvidosos = p.duvidosos || [], h = [];
    lista.forEach(function (campo) {
      var v = valorDoCampo(campo, ficha[campo]);
      if (v != null) h.push(linha(ROTULO[campo], "<b>" + esc(v) + "</b>", duvidosos.indexOf(campo) >= 0));
    });
    return h.length ? '<dl class="gc-dl">' + h.join("") + "</dl>" : "";
  }
  /* o que o serviço entendeu de cada nome de lugar (apelido, conjunto, parecido, não reconheci) */
  function lugares(p) {
    var h = [];
    ((p.local || {}).itens || []).forEach(function (it) {
      var tipo = it.tipo === "condominio" ? "condomínio" : "bairro", oficiais = it.oficiais || [];
      if (!it.como) {
        h.push('<p class="gc-lugar gc-lugar--duvida">Não reconheci o ' + tipo + " <b>" + esc(it.escrito) + "</b>" +
               (it.sugestao ? "; o mais parecido é " + esc(it.sugestao) : "") +
               ' <button type="button" class="btn-mini" data-apelido="' + esc(it.escrito) + '" data-tipo="' + esc(it.tipo) + '" data-oficial="' + esc(it.sugestao || "") + '">criar apelido</button></p>');
      } else if (it.como !== "exato" || oficiais.join("|").toLowerCase() !== String(it.escrito).toLowerCase()) {
        var duvida = it.como === "parecido" || it.como === "pedaco";
        h.push('<p class="gc-lugar' + (duvida ? " gc-lugar--duvida" : "") + '">“' + esc(it.escrito) + "” = <b>" +
               esc(oficiais.slice(0, 3).join(", ")) + (oficiais.length > 3 ? " e mais " + (oficiais.length - 3) : "") + "</b>" +
               (COMO[it.como] ? " <small>(" + COMO[it.como] + ")</small>" : "") +
               (duvida ? ' <button type="button" class="btn-mini" data-apelido="' + esc(it.escrito) + '" data-tipo="' + esc(it.tipo) + '" data-oficial="' + esc(oficiais[0] || "") + '">confirmar como apelido</button>' : "") + "</p>");
      }
    });
    return h.join("");
  }
  /* a manchete do pedido: o que ele quer, numa linha que se lê de longe */
  function manchetePedido(p) {
    var f = p.ficha || {}, local = p.local || {}, partes = [];
    var operacao = f.operacao || local.operacao;
    if (operacao) partes.push('<span class="gc-op gc-op--' + esc(operacao) + '">' + (operacao === "aluguel" ? "ALUGUEL" : "VENDA") + "</span>");
    if (f.tipo) partes.push(esc(valorDoCampo("tipo", f.tipo)));
    if (f.quartos != null) partes.push(f.quartos + (f.quartos === 1 ? " quarto" : " quartos"));
    if (f.preco_max) partes.push("<strong>até " + esc(reais(f.preco_max)) + "</strong>");
    var onde = [].concat(f.bairros || [], f.condominio ? [f.condominio] : []);
    return '<p class="gc-manchete">' + (partes.join(' <i>·</i> ') || "Pedido sem detalhe") + "</p>" +
           (onde.length ? '<p class="gc-onde">em ' + esc(onde.join(" ou ")) + "</p>" : "");
  }
  function desenharFicha(p) {
    var f = p.ficha || {}, local = p.local || {};
    var negocio = campos(p, ["operacao", "tipo", "preco_max"]) +
      (local.operacao && local.operacao_origem === "nome do grupo"
        ? '<p class="gc-lugar">Operação tirada do nome do grupo: a mensagem não disse.</p>' : "");
    var onde = campos(p, ["bairros", "condominio"]) + lugares(p);
    var imovel = campos(p, ["quartos", "suite", "vagas", "andar", "mobiliado", "pet"]);
    var contato = campos(p, ["contato"]) + (f.observacao ? '<p class="gc-lugar">Também pediu: ' + esc(f.observacao) + "</p>" : "");
    var caixas = caixa("roxo", "Negócio", negocio) + caixa("azul", "Onde", onde) + caixa("verde", "Imóvel que ele quer", imovel) +
                 caixa("cinza", "Contato e observação", contato);
    return '<div class="gc-caixas">' + (caixas || '<p class="gc-lugar">A IA não achou nenhum campo nesta mensagem.</p>') + "</div>";
  }

  /* ── o lado do imóvel ── */
  function valorDoImovel(im, operacao) { return operacao === "venda" ? im.valor_venda : im.valor_aluguel; }
  function fichaDoImovel(im) {
    var h = [];
    if (im.quartos != null) h.push(linha("Quartos", "<b>" + im.quartos + "</b>" + (im.suites ? " (" + im.suites + (im.suites === 1 ? " suíte)" : " suítes)") : "")));
    if (im.vagas != null) h.push(linha("Vagas", "<b>" + im.vagas + "</b>"));
    if (im.area) h.push(linha("Área", "<b>" + Math.round(im.area) + " m²</b>"));
    if (im.andar_cadastro) h.push(linha("Andar", "<b>" + esc(im.andar_cadastro) + "</b>"));
    if (im.mobilia_cadastro) h.push(linha("Mobília", "<b>" + esc(im.mobilia_cadastro) + "</b>"));
    if (im.taxa_condominio) h.push(linha("Condomínio", "<b>" + esc(reais(im.taxa_condominio)) + "</b>"));
    return h.length ? '<dl class="gc-dl">' + h.join("") + "</dl>" : "";
  }
  /* por que essa nota: uma linha por critério -- o nome, a barra, "ganhou X de Y" e o motivo */
  function desenharNota(par) {
    var h = ['<ul class="gc-criterios">'];
    (par.detalhe || []).forEach(function (d) {
      var cheio = d.rendimento >= 99.5, zero = d.rendimento <= 0.5;
      h.push('<li class="gc-criterio' + (cheio ? " gc-criterio--cheio" : zero ? " gc-criterio--zero" : " gc-criterio--parte") + '">' +
             '<span class="gc-criterio__nome">' + esc(CRITERIO[d.criterio] || d.criterio) + "</span>" +
             '<span class="gc-barra"><i style="width:' + Math.max(0, Math.min(100, d.rendimento)) + '%"></i></span>' +
             '<span class="gc-criterio__pontos"><b>' + Math.round(d.pontos) + "</b> de " + Math.round(d.peso) + "</span>" +
             '<span class="gc-criterio__texto">' + esc(d.texto) + "</span></li>");
    });
    h.push("</ul>");
    return h.join("");
  }
  function desenharImovel(p) {
    var pares = p.pares || [], operacao = (p.local && p.local.operacao) || (p.ficha && p.ficha.operacao);
    if (!p.pontuado) return '<div class="gc-sem"><strong>Calculando…</strong><p>O leitor ainda não fez a conta desta solicitação.</p></div>';
    if (!pares.length) {
      /* o funil para no primeiro filtro que zerou: o resto seria uma fila de zeros */
      var funil = p.funil || {}, passos = [], acabou = false;
      ["operacao", "tipo", "local", "quartos", "preco", "financiamento", "confirmado"].forEach(function (e) {
        if (acabou || funil[e] == null) return;
        passos.push('<span class="gc-passo' + (funil[e] === 0 ? " gc-passo--zero" : "") + '"><b>' + funil[e] + "</b> " + ETAPA[e] + "</span>");
        if (funil[e] === 0) acabou = true;
      });
      return '<div class="gc-sem"><strong>Sem imóvel compatível</strong><p class="gc-sem__motivo">' + esc(p.sem_match_motivo || "nada passou nos filtros") + "</p>" +
             (passos.length ? '<p class="gc-sem__rotulo">Imóveis nossos que sobraram a cada filtro</p><div class="gc-passos">' + passos.join('<i>→</i>') + "</div>" : "") + "</div>";
    }
    var m = pares[0], im = m.imovel || {}, faixa = p.faixa || "registro";
    operacao = operacaoDaParte(p, m.parte);
    var h = ['<div class="gc-imovel">',
             '<img class="gc-foto" alt="" data-foto="' + esc(im.codigo) + '" loading="lazy">',
             '<div class="gc-imovel__dados">',
             '<p class="gc-imovel__nome"><a href="' + esc(API.replace("api.", "") + "/imovel/" + im.codigo) + '" target="_blank" rel="noopener">' +
               esc(im.condominio || im.tipo_cadastro || "Imóvel") + "</a> <small>cód. " + esc(im.codigo) + "</small></p>",
             '<p class="gc-imovel__linha" data-endereco="' + esc(im.codigo) + '">' + esc([im.logradouro, im.bairro].filter(Boolean).join(" · ")) + "</p>",
             '<p class="gc-imovel__preco">' + esc(reais(valorDoImovel(im, operacao))) + (operacao === "aluguel" ? "<small> /mês</small>" : "") + "</p>",
             (m.acima_do_teto ? '<span class="gc-etiqueta">acima do teto, negociável</span>' : ""),
             "</div>",
             '<div class="gc-nota gc-nota--' + esc(faixa) + '"><b>' + Math.round(m.nota) + "</b><span>de 100</span><em>" +
               ({ verde: "na fila", amarelo: "parecido", registro: "fraco" }[faixa] || "") + "</em></div>",
             "</div>",
             '<div class="gc-caixas">',
             caixa("verde", "O imóvel", fichaDoImovel(im)),
             caixa("roxo", "Por que essa nota", desenharNota(m)),
             "</div>"];
    if (im.confirmado_em) h.push('<p class="gc-confirmado">Disponível, confirmado em ' + esc(quando(im.confirmado_em)) + " (" + esc(im.confirmado_como || "") + ").</p>");
    if (pares.length > 1) {
      h.push('<details class="gc-alternativas"><summary>' + (pares.length - 1) + (pares.length === 2 ? " alternativa" : " alternativas") +
             (p.local && p.local.passaram > pares.length ? " (de " + (p.local.passaram - 1) + " que passaram)" : "") + "</summary><ul>");
      pares.slice(1).forEach(function (a) {
        var ia = a.imovel || {}, outra = parteDe(p, a.parte);
        h.push("<li><span><b>" + esc(ia.condominio || ia.tipo_cadastro || "") + "</b> <small>cód. " + esc(ia.codigo) + "</small>" +
               (outra ? ' <small class="gc-alt-parte">para: ' + esc(resumoDaFicha(outra.ficha)) + "</small>" : "") + "<br>" + esc(ia.bairro || "") +
               (ia.quartos != null ? " · " + ia.quartos + (ia.quartos === 1 ? " quarto" : " quartos") : "") + " · " + esc(reais(valorDoImovel(ia, operacaoDaParte(p, a.parte)))) +
               (a.acima_do_teto ? " (acima do teto)" : "") + "</span>" +
               (naoPodeEnviar(p, ia.codigo) ? "" : '<button type="button" class="btn-mini gc-alt-enviar" data-acao="enviar" data-codigo="' + esc(ia.codigo) + '">enviar esta</button>') +
               '<b class="gc-alt-nota">' + Math.round(a.nota) + "</b></li>");
      });
      h.push("</ul></details>");
    }
    return h.join("");
  }

  /* 371 (Pedro, 15/10: "quando o cara joga em vários grupos ele cria várias, junta todas as duplicatas em uma"):
     as cópias vêm juntadas pelo banco; aqui só a etiqueta, que abre a lista dos grupos.
     380 (Pedro, 16/10: "o mesmo corretor faz o pedido em vários grupos ... devem ser todos juntados em um só card"):
     o texto reescrito e colado de novo também vem junto; a etiqueta conta as versões e mostra as outras */
  function copias(p) {
    var versoes = p.outras_versoes || [];
    if (!(p.vezes > 1) && !versoes.length) return "";
    var grupos = p.grupos || [];
    return '<details class="gc-copias"><summary>postado ' + p.vezes + (p.vezes === 1 ? " vez" : " vezes") +
           (grupos.length > 1 ? " em " + grupos.length + " grupos" : "") +
           (versoes.length ? " · " + (versoes.length + 1) + " versões do texto" : "") + "</summary><ul>" +
           grupos.map(function (g) { return "<li>" + esc(g) + "</li>"; }).join("") + "</ul>" +
           (versoes.length
             ? '<p class="gc-versoes__rotulo">Outras versões do texto (o card mostra a mais recente)</p><ul class="gc-versoes">' +
               versoes.map(function (v) {
                 return "<li><small>" + esc(quando(v.quando)) + (v.grupo ? " · " + esc(v.grupo) : "") + "</small>" + esc(v.texto) + "</li>";
               }).join("") + "</ul>"
             : "") +
           "</details>";
  }
  /* 380: a mesma mensagem com mais de um pedido ("casa ou apartamento", "aluguel ou venda") é um card só: aparece a parte
     de melhor nota, as outras numa linha, e os imóveis delas entram nas alternativas com a etiqueta da parte */
  function resumoDaFicha(f) {
    f = f || {};
    var r = [];
    if (f.operacao) r.push(f.operacao === "aluguel" ? "ALUGUEL" : "VENDA");
    if (f.tipo) r.push(valorDoCampo("tipo", f.tipo));
    if (f.quartos != null) r.push(f.quartos + (f.quartos === 1 ? " quarto" : " quartos"));
    if (f.preco_max) r.push("até " + reais(f.preco_max));
    return r.join(" · ") || "pedido sem detalhe";
  }
  function outrasPartes(p) {
    var o = p.outras_partes || [];
    if (!o.length) return "";
    return '<p class="gc-outras-partes">Na mesma mensagem também pede: ' + o.map(function (x) {
      return "<b>" + esc(resumoDaFicha(x.ficha)) + "</b>" + (x.nota != null ? " (nota " + Math.round(x.nota) + ")" : " (sem imóvel)");
    }).join("; ") + "</p>";
  }
  function parteDe(p, parte) {
    if (parte == null || parte === p.parte) return null;
    return (p.outras_partes || []).filter(function (x) { return x.parte === parte; })[0] || null;
  }
  /* o preço do imóvel depende do negócio da parte que o achou (aluguel ou venda) */
  function operacaoDaParte(p, parte) {
    var o = parteDe(p, parte);
    return (o && o.ficha && o.ficha.operacao) || (p.local && p.local.operacao) || (p.ficha && p.ficha.operacao);
  }

  function desenharItem(p) {
    var faixa = p.pontuado ? (p.faixa || "sem_match") : "registro";
    var j = p.julgamento, rejeitado = p.estado === "rejeitado";
    var quem = [];
    if (p.nome) quem.push("<b>" + esc(p.nome) + "</b>");
    if (p.telefone) quem.push(esc(fone(p.telefone)));
    quem.push(esc(quando(p.enviada_em)));
    if (p.vezes > 1 && p.primeira_em) quem.push("1ª vez " + esc(quando(p.primeira_em)));
    var h = ['<article class="gc-item gc-item--' + esc(faixa) + (rejeitado ? " gc-item--rejeitado" : "") + '" data-id="' + p.id + '">',
             '<div class="gc-lado">',
             /* o grupo de onde veio, com o nome EXATO, num quadrado preto (Pedro, 09/10: "seria bom aparecer lá no card
                um quadrado preto com o nome exato do grupo ao qual a msg veio") */
             '<div class="gc-origem"><span class="gc-grupo"><small>' + (p.fonte === "teste" ? "Origem" : "Grupo") + "</small>" +
               esc(p.grupo || "(grupo sem nome)") + "</span>" + copias(p) + "</div>",
             '<div class="gc-quem"><span>' + quem.join(" · ") + "</span></div>",
             manchetePedido(p),
             '<p class="gc-texto">' + esc(p.texto) + "</p>",
             (p.parte > 1 || (p.ficha && p.ficha.trecho && p.ficha.trecho.length + 12 < String(p.texto).length)
               ? '<p class="gc-parte">Pedido ' + p.parte + " desta mensagem: “" + esc(p.ficha.trecho || "") + "”</p>" : ""),
             outrasPartes(p),
             desenharFicha(p),
             '<div class="gc-acoes">',
             (function () {
               var melhor = (p.pares || [])[0], codigo = melhor && melhor.codigo, motivo = naoPodeEnviar(p, codigo);
               return motivo
                 ? '<button type="button" class="btn-mini" disabled title="' + esc(motivo) + '">Enviar ao corretor</button>'
                 : '<button type="button" class="btn-azul gc-btn-enviar" data-acao="enviar" data-codigo="' + esc(codigo) + '">Enviar ao corretor</button>';
             })(),
             /* 382 (Pedro, 16/10): "nas opções põe uma enviar vários imóveis ... em uma nova opção lá no card" */
             (function () {
               var motivo = !manual() ? "O envio manual está desligado (envio_manual)."
                 : p.fonte === "teste" ? "Teste colado na tela: não tem corretor para receber."
                 : !p.telefone ? "A mensagem veio sem o telefone de quem escreveu."
                 : rejeitado ? "Solicitação rejeitada: desfaça a rejeição para enviar." : "";
               return '<button type="button" class="btn-mini gc-btn-varios" data-acao="varios"' +
                      (motivo ? ' disabled title="' + esc(motivo) + '"' : ' title="Escolha os imóveis (os que casaram ou qualquer outro), a mensagem inicial, card e/ou fotos"') +
                      ">Enviar vários imóveis</button>";
             })(),
             /* 372 (Pedro, 15/10): "mais um campo ali ao lado de enviar imóvel, Mensagem de negociação" */
             (function () {
               var motivo = !manual() ? "O envio manual está desligado (envio_manual)."
                 : p.fonte === "teste" ? "Teste colado na tela: não tem corretor para receber."
                 : !p.telefone ? "A mensagem veio sem o telefone de quem escreveu." : "";
               return '<button type="button" class="btn-mini gc-btn-negocia" data-acao="negociar"' +
                      (motivo ? ' disabled title="' + esc(motivo) + '"' : ' title="Escreva uma mensagem: ela vai para o PV dele pelo número da Parceria"') +
                      ">Mensagem de negociação</button>";
             })(),
             (p.ofertas || []).map(function (o) {
               return '<span class="gc-enviado" title="' + esc(o.resumo || "") + '">✓ enviado o ' + esc(o.codigo) + " · " + esc(quando(o.quando)) + "</span>";
             }).join(""),
             (p.negociacao || []).length
               ? '<div class="gc-negociacao">' + p.negociacao.map(function (m) {
                   return '<p title="' + esc(m.resumo || "") + '"><small>✉ no PV · ' + esc(quando(m.quando)) + "</small>" + esc(m.texto) + "</p>";
                 }).join("") + "</div>"
               : "",
             (p.estado === "enviado" ? "" :
               '<button type="button" class="btn-mini" data-acao="' + (rejeitado ? "voltar" : "rejeitar") + '">' + (rejeitado ? "Desfazer rejeição" : "Rejeitar") + "</button>"),
             '<button type="button" class="btn-mini gc-btn-ok" data-acao="correta">Leitura correta</button>',
             '<button type="button" class="btn-mini gc-btn-erro" data-acao="errada">Leitura errada</button>',
             (j ? '<span class="gc-julgado gc-julgado--' + esc(j.leitura) + '" title="' + esc(quando(j.quando)) + '">' +
                  (j.leitura === "correta" ? "✓ leitura correta" : "✗ leitura errada" + (j.o_que_errou ? ": " + esc(j.o_que_errou) : "")) + "</span>" : ""),
             "</div>",
             "</div>",
             '<div class="gc-lado gc-lado--imovel">' + desenharImovel(p) + "</div>",
             "</article>"];
    return h.join("");
  }

  /* a foto e o endereço vêm do card do imóvel (a mesma rota do resto do admin), uma vez por código */
  function buscarFotos() {
    Array.prototype.forEach.call(painel.querySelectorAll("img[data-foto]"), function (img) {
      var c = img.getAttribute("data-foto");
      if (!estado.fotos[c]) {
        estado.fotos[c] = fetch(API + "/api/imovel-card/" + encodeURIComponent(c)).then(function (r) { return r.json(); })
          .then(function (d) { return d.imovel || {}; }).catch(function () { return {}; });
      }
      estado.fotos[c].then(function (im) {
        if (im.capa) img.src = im.capa;
        var linha = painel.querySelector('[data-endereco="' + c + '"]');
        if (linha && im.endereco) linha.textContent = [im.endereco, im.bairro].filter(Boolean).join(" · ");
      });
    });
  }

  function desenhar() {
    var d = estado.dados;
    if (!d) return;
    desenharTopo(d);
    var lista = $("gc-lista"), pedidos = d.pedidos || [];
    if (!pedidos.length) {
      lista.innerHTML = '<p class="gc-vazio">' + (estado.filtro === "todos"
        ? "Nenhuma solicitação nas últimas " + d.horas + " h. Cole uma mensagem em “Testar uma mensagem” para ver a leitura."
        : "Nenhuma solicitação neste filtro" + (estado.nota ? " com nota " + estado.nota + " ou mais" : "") + ".") + "</p>";
      return;
    }
    lista.innerHTML = pedidos.map(desenharItem).join("");
    buscarFotos();
  }

  function carregar() {
    var n = ++estado.pedido;
    if (!estado.dados) $("gc-lista").innerHTML = '<p class="ga-carregando">Carregando as solicitações…</p>';
    return pedir("/admin/api/grupos/captacao?filtro=" + encodeURIComponent(estado.filtro) +
                 "&nota=" + encodeURIComponent(estado.nota || 0) + "&ordem=" + encodeURIComponent(estado.ordem))
      .then(function (d) {
        if (n !== estado.pedido) return;
        estado.dados = d; estado.carregou = true; desenhar();
        clearTimeout(estado.espera);
        if ((d.fonte || {}).na_fila && !painel.hidden && !painel.querySelector(".gc-errou, .gc-negocia")) estado.espera = setTimeout(carregar, 7000);
      })
      .catch(function (e) { if (n === estado.pedido) $("gc-lista").innerHTML = '<p class="gc-vazio">Não consegui carregar: ' + esc(e.message) + "</p>"; });
  }

  /* ── enviar ao corretor: a conferência (a mensagem padrão dele, para quem vai, o que vai) ── */
  var envio = null;
  function abrirEnvio(id, codigo) {
    var p = ((estado.dados || {}).pedidos || []).filter(function (x) { return String(x.id) === String(id); })[0];
    if (!p) return;
    var par = (p.pares || []).filter(function (x) { return String(x.codigo) === String(codigo); })[0];
    if (!par || naoPodeEnviar(p, par.codigo)) return;
    var cfg = estado.dados.config || {}, im = par.imovel || {}, operacao = (p.local && p.local.operacao) || (p.ficha && p.ficha.operacao);
    envio = { id: p.id, codigo: par.codigo };
    $("gc-env-resumo").innerHTML =
      "<div><span>Para</span><b>" + esc(p.nome || "(sem nome)") + " · " + esc(fone(p.telefone)) + "</b></div>" +
      "<div><span>Do grupo</span><b>" + esc(p.grupo || "") + "</b></div>" +
      "<div><span>Imóvel</span><b>" + esc(im.condominio || im.tipo_cadastro || "Imóvel") + " · cód. " + esc(im.codigo) + " · " + esc(reais(valorDoImovel(im, operacao))) +
        " · nota " + Math.round(par.nota) + "</b></div>" +
      "<div><span>Sai por</span><b>número da Parceria (o que está nos grupos)</b></div>";
    $("gc-env-texto").value = cfg.mensagem_de_abertura || "";
    $("gc-env-depois").innerHTML = (cfg.enviar_dados_e_fotos === false
      ? "<b>Só esta mensagem sai.</b> O card e as fotos você manda na mão (enviar_dados_e_fotos está desligado)."
      : "Logo depois dela vão <b>o card e as fotos</b> do imóvel, como na aba Enviar imóvel.") +
      (cfg.intervalo_min_entre_envios > 0 ? " O mesmo corretor só recebe outra mensagem daqui depois de " + cfg.intervalo_min_entre_envios + " min." : "");
    $("gc-env-erro").textContent = "";
    $("gc-env-ok").disabled = false;
    if (!$("gc-enviar").open) $("gc-enviar").showModal();
  }
  function enviar(ev) {
    ev.preventDefault();
    if (!envio) return;
    var texto = $("gc-env-texto").value.trim();
    if (!texto) { $("gc-env-erro").textContent = "Escreva a mensagem que abre a conversa."; return; }
    $("gc-env-ok").disabled = true;
    $("gc-env-erro").textContent = "";
    pedir("/admin/api/grupos/captacao/" + envio.id + "/enviar", { method: "POST", body: JSON.stringify({ codigo: envio.codigo, abertura: texto }) })
      .then(function (r) {
        $("gc-enviar").close();
        var aviso = $("gc-envio-feito");
        aviso.textContent = "Enviado o " + envio.codigo + ". " + (r.resumo || "");
        aviso.hidden = false;
        envio = null;
        return carregar();
      })
      .catch(function (e) { $("gc-env-ok").disabled = false; $("gc-env-erro").textContent = e.message; });
  }

  /* ── 382: ENVIAR VÁRIOS IMÓVEIS (Pedro, 16/10: "nas opções põe uma enviar vários imóveis, aí aparece um popup, eu
     seleciono os imóveis, adiciono, excluo, adiciono uma mensagem inicial, posso marcar enviar card ou marcar enviar foto
     também, uma seleção em lista editável e posso adicionar mais imóveis, pesquiso por código ou nome") ──
     A lista começa com o melhor que casou e ainda não foi; os outros que casaram ficam em Sugestões, a um clique; a busca
     acha qualquer imóvel que a Nay oferece (/api/imoveis-para-enviar, o catálogo do seletor da agenda). As travas (24 h
     por número, parceiro, indisponível, já enviado a este pedido) são do banco (site_captacao_grupos_enviar_varios): o
     que não puder ir volta dito no aviso, e o resto vai. */
  var MAX_VARIOS = 10;
  var varios = null;            // { p, operacao, lista: [imóvel], achados: [imóvel] }
  var catalogoVarios = null;    // Promise do catálogo
  var esperaBusca = null;
  function catalogoDosImoveis() {
    if (!catalogoVarios) {
      catalogoVarios = fetch(API + "/api/imoveis-para-enviar").then(function (r) { return r.json(); })
        .then(function (d) { return d.imoveis || []; })
        .catch(function () { catalogoVarios = null; return []; });
    }
    return catalogoVarios;
  }
  function semAcento(s) { return String(s == null ? "" : s).normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase(); }
  /* o imóvel que casou (par) e o do catálogo no mesmo formato */
  function doPar(par) {
    var im = par.imovel || {};
    return { codigo: Number(par.codigo), nome: im.condominio || im.tipo_cadastro || "Imóvel", bairro: im.bairro || "", quartos: im.quartos,
             venda: im.valor_venda, aluguel: im.valor_aluguel, nota: par.nota, foto: null };
  }
  function doCatalogo(m) {
    return { codigo: Number(m.codigo), nome: m.condominio || m.titulo || m.tipo || "Imóvel", bairro: m.bairro || "", quartos: m.quartos,
             venda: m.venda, aluguel: m.aluguel, nota: null, foto: m.foto || null };
  }
  function precoDe(im, operacao) {
    if (operacao === "venda" && im.venda) return reais(im.venda);
    if (operacao === "aluguel" && im.aluguel) return reais(im.aluguel) + "/mês";
    return [im.venda ? reais(im.venda) : "", im.aluguel ? reais(im.aluguel) + "/mês" : ""].filter(Boolean).join(" · ");
  }
  function jaEnviado(p, codigo) { return (p.ofertas || []).some(function (o) { return Number(o.codigo) === Number(codigo); }); }
  function linhaDoImovel(im, operacao) {
    return "<b>" + esc(im.nome) + "</b> <small>cód. " + esc(im.codigo) + "</small><br><span>" +
           esc([im.bairro, im.quartos != null ? im.quartos + (im.quartos === 1 ? " quarto" : " quartos") : "", precoDe(im, operacao)].filter(Boolean).join(" · ")) +
           "</span>";
  }
  function desenharVarios() {
    var v = varios, l = v.lista;
    $("gc-var-lista").innerHTML = l.length
      ? l.map(function (im, n) {
          return '<li class="gc-var-item"><span class="gc-var-num">' + (n + 1) + "</span>" +
                 '<img class="gc-var-foto" alt="" data-var-foto="' + esc(im.codigo) + '"' + (im.foto ? ' src="' + esc(im.foto) + '"' : "") + ">" +
                 '<span class="gc-var-dados">' + linhaDoImovel(im, v.operacao) +
                   (im.nota != null ? ' <i class="gc-var-nota">casou · nota ' + Math.round(im.nota) + "</i>" : "") + "</span>" +
                 '<span class="gc-var-botoes">' +
                   '<button type="button" class="btn-mini" data-var="subir" data-n="' + n + '"' + (n === 0 ? " disabled" : "") + ' aria-label="Subir" title="Subir">↑</button>' +
                   '<button type="button" class="btn-mini" data-var="descer" data-n="' + n + '"' + (n === l.length - 1 ? " disabled" : "") + ' aria-label="Descer" title="Descer">↓</button>' +
                   '<button type="button" class="btn-mini gc-var-tirar" data-var="tirar" data-n="' + n + '" aria-label="Tirar da lista" title="Tirar da lista">✕</button>' +
                 "</span></li>";
        }).join("")
      : '<li class="gc-var-vazia">Nenhum imóvel na lista. Escolha nas sugestões ou pesquise abaixo.</li>';
    $("gc-var-conta").textContent = l.length ? "(" + l.length + " de no máximo " + MAX_VARIOS + ", vão nesta ordem)" : "";
    var naLista = {};
    l.forEach(function (im) { naLista[im.codigo] = true; });
    var sug = (v.p.pares || []).filter(function (par) { return !naLista[Number(par.codigo)]; });
    $("gc-var-sugestoes").innerHTML = sug.length
      ? sug.map(function (par) {
          var im = doPar(par), ja = jaEnviado(v.p, im.codigo);
          return '<button type="button" class="gc-var-sug" data-var="sugerido" data-codigo="' + esc(im.codigo) + '"' +
                 (ja ? ' disabled title="Já foi enviado para este pedido"' : "") + ">+ " + esc(im.nome) +
                 " <small>cód. " + esc(im.codigo) + " · nota " + Math.round(par.nota) + (ja ? " · já enviado" : "") + "</small></button>";
        }).join("")
      : '<span class="gc-env-nota">Nenhuma outra: pesquise abaixo.</span>';
    $("gc-var-ok").textContent = l.length ? "Enviar " + l.length + (l.length === 1 ? " imóvel" : " imóveis") : "Enviar";
    /* os que casaram não trazem foto: vem do catálogo */
    catalogoDosImoveis().then(function (cat) {
      var porCodigo = {};
      cat.forEach(function (m) { porCodigo[Number(m.codigo)] = m; });
      Array.prototype.forEach.call($("gc-var-lista").querySelectorAll("img[data-var-foto]:not([src])"), function (img) {
        var m = porCodigo[Number(img.getAttribute("data-var-foto"))];
        if (m && m.foto) img.src = m.foto;
      });
    });
  }
  function adicionar(im) {
    var v = varios;
    if (!v) return;
    $("gc-var-erro").textContent = "";
    if (v.lista.some(function (x) { return x.codigo === im.codigo; })) { $("gc-var-erro").textContent = "O " + im.codigo + " já está na lista."; return; }
    if (jaEnviado(v.p, im.codigo)) { $("gc-var-erro").textContent = "O " + im.codigo + " já foi enviado para este pedido."; return; }
    if (v.lista.length >= MAX_VARIOS) { $("gc-var-erro").textContent = "No máximo " + MAX_VARIOS + " imóveis por envio."; return; }
    v.lista.push(im);
    desenharVarios();
  }
  function buscarNoCatalogo() {
    var q = $("gc-var-busca").value.trim(), caixa = $("gc-var-achados");
    if (!q || !varios) { caixa.hidden = true; caixa.innerHTML = ""; return; }
    catalogoDosImoveis().then(function (cat) {
      if (!varios || $("gc-var-busca").value.trim() !== q) return;      // já digitou outra coisa
      var digitos = /^\d+$/.test(q), palavras = semAcento(q).split(/\s+/);
      var achados = cat.filter(function (m) {
        if (digitos) return String(m.codigo).indexOf(q) === 0;
        var onde = semAcento([m.titulo, m.condominio, m.bairro, m.tipo, m.codigo].join(" "));
        return palavras.every(function (pal) { return onde.indexOf(pal) >= 0; });
      }).slice(0, 8).map(doCatalogo);
      varios.achados = achados;
      caixa.innerHTML = achados.length
        ? achados.map(function (im, n) {
            var ja = jaEnviado(varios.p, im.codigo), na = varios.lista.some(function (x) { return x.codigo === im.codigo; });
            return '<li><button type="button" data-var="achado" data-n="' + n + '"' + (ja || na ? " disabled" : "") + ">" +
                   (im.foto ? '<img alt="" src="' + esc(im.foto) + '" loading="lazy">' : "<i></i>") +
                   "<span>" + linhaDoImovel(im, varios.operacao) + (ja ? " <em>já enviado</em>" : na ? " <em>na lista</em>" : "") + "</span></button></li>";
          }).join("")
        : '<li class="gc-var-nada">Nenhum imóvel com "' + esc(q) + '". Aqui só aparece o que a Nay oferece: no mercado e nunca de parceiro.</li>';
      caixa.hidden = false;
    });
  }
  function abrirVarios(id) {
    var p = ((estado.dados || {}).pedidos || []).filter(function (x) { return String(x.id) === String(id); })[0];
    if (!p) return;
    var cfg = estado.dados.config || {};
    var primeiro = (p.pares || []).filter(function (par) { return !jaEnviado(p, par.codigo); })[0];
    varios = { p: p, operacao: (p.local && p.local.operacao) || (p.ficha && p.ficha.operacao), lista: primeiro ? [doPar(primeiro)] : [], achados: [] };
    $("gc-var-resumo").innerHTML =
      "<div><span>Para</span><b>" + esc(p.nome || "(sem nome)") + " · " + esc(fone(p.telefone)) + "</b></div>" +
      "<div><span>Do grupo</span><b>" + esc(p.grupo || "") + "</b></div>" +
      "<div><span>Sai por</span><b>número da Parceria, no privado dele</b></div>";
    $("gc-var-texto").value = cfg.mensagem_de_abertura || "";
    $("gc-var-card").checked = true;
    $("gc-var-fotos").checked = false;
    $("gc-var-busca").value = "";
    $("gc-var-achados").hidden = true;
    $("gc-var-erro").textContent = "";
    $("gc-var-ok").disabled = false;
    desenharVarios();
    if (!$("gc-varios").open) $("gc-varios").showModal();
  }
  function enviarVarios(ev) {
    ev.preventDefault();
    var v = varios;
    if (!v) return;
    var card = $("gc-var-card").checked, fotos = $("gc-var-fotos").checked;
    if (!v.lista.length) { $("gc-var-erro").textContent = "Coloque pelo menos um imóvel na lista."; return; }
    if (!card && !fotos) { $("gc-var-erro").textContent = "Marque o card, as fotos ou os dois."; return; }
    $("gc-var-ok").disabled = true;
    $("gc-var-erro").textContent = "";
    pedir("/admin/api/grupos/captacao/" + v.p.id + "/enviar-varios", { method: "POST", body: JSON.stringify({
      codigos: v.lista.map(function (im) { return im.codigo; }), abertura: $("gc-var-texto").value.trim(), card: card, fotos: fotos }) })
      .then(function (r) {
        $("gc-varios").close();
        var aviso = $("gc-envio-feito");
        aviso.textContent = r.resumo || "Enviado.";
        aviso.hidden = false;
        varios = null;
        return carregar();
      })
      .catch(function (e) { $("gc-var-ok").disabled = false; $("gc-var-erro").textContent = e.message; });
  }
  /* a lista editável: subir, descer, tirar; e o que entra pelas sugestões e pela busca */
  function mexerNaLista(ev) {
    var b = ev.target.closest ? ev.target.closest("[data-var]") : null;
    if (!b || !varios || b.disabled) return;
    var o = b.getAttribute("data-var"), n = parseInt(b.getAttribute("data-n"), 10), l = varios.lista;
    if (o === "sugerido") {
      var par = (varios.p.pares || []).filter(function (x) { return String(x.codigo) === b.getAttribute("data-codigo"); })[0];
      if (par) adicionar(doPar(par));
      return;
    }
    if (o === "achado") {
      if (varios.achados[n]) adicionar(varios.achados[n]);
      $("gc-var-busca").value = "";
      $("gc-var-achados").hidden = true;
      $("gc-var-busca").focus();
      return;
    }
    if (o === "tirar") l.splice(n, 1);
    else if (o === "subir" && n > 0) l.splice(n - 1, 0, l.splice(n, 1)[0]);
    else if (o === "descer" && n < l.length - 1) l.splice(n + 1, 0, l.splice(n, 1)[0]);
    else return;
    $("gc-var-erro").textContent = "";
    desenharVarios();
  }

  /* ── ações de cada solicitação ── */
  function agir(item, acao, botao) {
    var id = item.getAttribute("data-id");
    if (acao === "enviar") { abrirEnvio(id, botao.getAttribute("data-codigo")); return; }
    if (acao === "varios") { abrirVarios(id); return; }
    if (acao === "negociar") {
      var aberta = item.querySelector(".gc-negocia");
      if (aberta) { aberta.remove(); return; }
      var form = document.createElement("form");
      form.className = "gc-negocia";
      form.innerHTML = '<textarea class="entrada" rows="3" maxlength="1500" placeholder="Escreva a mensagem para ele. Vai do jeito que estiver aqui, no PV dele, pelo número da Parceria." aria-label="Mensagem de negociação"></textarea>' +
                       '<div class="gc-negocia__botoes"><button class="btn-azul" type="submit">Enviar no PV</button>' +
                       '<button class="btn-mini" type="button" data-negocia-fechar>Cancelar</button><span class="ga-erro" role="alert"></span></div>';
      item.querySelector(".gc-acoes").appendChild(form);
      form.querySelector("textarea").focus();
      form.querySelector("[data-negocia-fechar]").addEventListener("click", function () { form.remove(); });
      form.addEventListener("submit", function (ev) {
        ev.preventDefault();
        var texto = form.querySelector("textarea").value.trim(), erro = form.querySelector(".ga-erro"), ok = form.querySelector("[type=submit]");
        if (!texto) { form.querySelector("textarea").focus(); return; }
        ok.disabled = true; erro.textContent = "";
        pedir("/admin/api/grupos/captacao/" + id + "/mensagem", { method: "POST", body: JSON.stringify({ texto: texto }) })
          .then(function (r) {
            var aviso = $("gc-envio-feito");
            aviso.textContent = "Mensagem enviada no PV. " + (r.resumo || "");
            aviso.hidden = false;
            form.remove();
            return carregar();
          })
          .catch(function (e) { ok.disabled = false; erro.textContent = e.message; });
      });
      return;
    }
    if (acao === "errada") {
      if (item.querySelector(".gc-errou")) return;
      var caixa = document.createElement("form");
      caixa.className = "gc-errou";
      caixa.innerHTML = '<input class="entrada" maxlength="1000" placeholder="O que a leitura errou? (ex.: eram 2 quartos; o bairro é Aleixo)" aria-label="O que errou">' +
                        '<button class="btn-azul" type="submit">Salvar</button>';
      item.querySelector(".gc-acoes").appendChild(caixa);
      caixa.querySelector("input").focus();
      caixa.addEventListener("submit", function (ev) {
        ev.preventDefault();
        var texto = caixa.querySelector("input").value.trim();
        if (!texto) { caixa.querySelector("input").focus(); return; }
        pedir("/admin/api/grupos/captacao/" + id + "/julgar", { method: "POST", body: JSON.stringify({ leitura: "errada", erro: texto }) })
          .then(carregar).catch(function (e) { alert(e.message); });
      });
      return;
    }
    botao.disabled = true;
    var chamada = acao === "correta"
      ? pedir("/admin/api/grupos/captacao/" + id + "/julgar", { method: "POST", body: JSON.stringify({ leitura: "correta" }) })
      : pedir("/admin/api/grupos/captacao/" + id + "/estado", { method: "POST", body: JSON.stringify({ estado: acao === "rejeitar" ? "rejeitado" : "novo" }) });
    chamada.then(carregar).catch(function (e) { botao.disabled = false; alert(e.message); });
  }

  /* ── testar uma mensagem ── */
  function testar(ev) {
    ev.preventDefault();
    var campo = $("gc-teste-texto"), aviso = $("gc-teste-estado"), botao = $("gc-teste-ler"), texto = campo.value.trim();
    function dizer(t, erro) { aviso.textContent = t; if (erro) aviso.setAttribute("data-erro", "1"); else aviso.removeAttribute("data-erro"); }
    if (texto.length < 8) { dizer("Cole a mensagem do corretor.", true); campo.focus(); return; }
    botao.disabled = true;
    dizer("Enviando para a IA ler…");
    pedir("/admin/api/grupos/captacao/testar", { method: "POST", body: JSON.stringify({ texto: texto }) })
      .then(function (r) {
        var tentativas = 0;
        (function esperar() {
          tentativas += 1;
          pedir("/admin/api/grupos/captacao/testar/" + r.id).then(function (s) {
            if (s.lido && (s.pontuado || !s.pedidos)) {
              botao.disabled = false;
              if (s.erro) return dizer("A IA não respondeu agora (" + s.erro.slice(0, 80) + "). O leitor tenta de novo em 10 minutos.", true);
              if (!s.pedidos) return dizer("A IA leu e entendeu que isto NÃO é um pedido de imóvel" + (s.motivo ? " (" + s.motivo + ")" : "") + ".", true);
              dizer(s.pedidos === 1 ? "Lida: 1 pedido. Está no topo da lista." : "Lida: " + s.pedidos + " pedidos. Estão no topo da lista.");
              campo.value = "";
              estado.filtro = "todos";
              return carregar();
            }
            if (tentativas > 45) { botao.disabled = false; return dizer("O leitor está demorando. Se o selo lá em cima diz \"leitor parado\", é isso: a mensagem fica na fila.", true); }
            dizer(s.lido ? "Lida. Fazendo a conta com o catálogo…" : "A IA está lendo…");
            setTimeout(esperar, 2000);
          }).catch(function (e) { botao.disabled = false; dizer(e.message, true); });
        })();
      })
      .catch(function (e) { botao.disabled = false; dizer(e.message, true); });
  }

  /* ── importar a conversa exportada do WhatsApp (337) ──
     Pedro, 09/10/2026: "quero que teste com os últimos 2 dias de solicitações que tiveram em todos os grupos do
     número de parceria". Esses 2 dias não estão em sistema nenhum (a Z-API só entrega avisos de grupo e não
     devolve histórico); estão no celular, e o WhatsApp exporta a conversa em texto. O navegador lê o arquivo
     (whatsapp-exportado.js), fica só com as mensagens da janela e manda em lotes; o leitor faz o resto. */
  function importar(arquivos) {
    var W = window.WhatsAppExportado, lista = $("gc-importados");
    var horas = (estado.dados && estado.dados.horas) || 48, desde = Date.now() - horas * 3600 * 1000;
    function msgs(n) { return n + (n === 1 ? " mensagem" : " mensagens"); }
    function linhaDe(nome) {
      var li = document.createElement("li");
      li.setAttribute("data-lendo", "1");
      li.textContent = nome + ": lendo o arquivo…";
      lista.insertBefore(li, lista.firstChild);
      return li;
    }
    function umArquivo(arq) {
      var li = linhaDe(arq.name);
      function falhou(e) { li.removeAttribute("data-lendo"); li.setAttribute("data-erro", "1"); li.textContent = arq.name + ": " + (e.message || e); }
      var texto = /\.zip$/i.test(arq.name) ? arq.arrayBuffer().then(W.textoDoZip) : arq.text();
      return texto.then(function (t) {
        var grupo = W.grupoDoArquivo(arq.name) || (window.prompt("De qual grupo é o arquivo " + arq.name + "?") || "").trim();
        if (!grupo) throw new Error("sem o nome do grupo, não importei");
        var lido = W.lerConversaExportada(t, desde), todas = W.lerConversaExportada(t).mensagens.length, lotes = [], i;
        if (!todas) throw new Error("não achei mensagens: este arquivo é uma conversa exportada do WhatsApp?");
        if (!lido.mensagens.length) throw new Error(msgs(todas) + " no arquivo, nenhuma das últimas " + horas + " h");
        for (i = 0; i < lido.mensagens.length; i += 400) lotes.push(lido.mensagens.slice(i, i + 400));
        var soma = { novas: 0, repetidas: 0 };
        li.textContent = grupo + ": enviando " + msgs(lido.mensagens.length) + "…";
        return lotes.reduce(function (antes, lote) {
          return antes.then(function () {
            return pedir("/admin/api/grupos/captacao/importar", { method: "POST", body: JSON.stringify({ grupo: grupo, mensagens: lote }) })
              .then(function (r) { soma.novas += r.novas || 0; soma.repetidas += r.repetidas || 0; });
          });
        }, Promise.resolve()).then(function () {
          li.removeAttribute("data-lendo");
          li.textContent = grupo + ": " + msgs(todas) + " no arquivo, " + lido.mensagens.length + " das últimas " + horas + " h; " +
                           soma.novas + (soma.novas === 1 ? " nova" : " novas") + " na fila do leitor" +
                           (soma.repetidas ? " (" + soma.repetidas + " já tinham entrado)" : "") + ".";
        });
      }).catch(falhou);
    }
    return Array.prototype.reduce.call(arquivos, function (antes, arq) { return antes.then(function () { return umArquivo(arq); }); }, Promise.resolve())
      .then(function () { estado.filtro = "todos"; return carregar(); });
  }

  /* ── demanda do mercado ── */
  function abrirDemanda() {
    var dlg = $("gc-demanda");
    if (!dlg.open) dlg.showModal();
    $("gc-dem-corpo").innerHTML = '<p class="ga-carregando">Somando os pedidos…</p>';
    pedir("/admin/api/grupos/captacao/demanda?dias=" + estado.demandaDias).then(function (d) {
      var h = ['<p class="ga-dica">Nos últimos ' + d.dias + " dias os grupos pediram <b>" + d.pedidos + "</b> imóveis e para <b>" + d.sem_imovel +
               "</b> não tínhamos nada compatível. Abaixo, o que mais pedem (bairro ou condomínio, quartos e faixa de valor); em vermelho, quantos ficaram sem imóvel nosso. " +
               "Testes colados na tela não entram.</p>"];
      if (!(d.linhas || []).length) {
        h.push('<p class="gc-vazio">Ainda não há pedidos de grupo guardados.</p>');
      } else {
        h.push('<div class="tabela-rolagem"><table class="gc-tabela"><thead><tr><th>Operação</th><th>Onde</th><th class="num">Quartos</th><th>Faixa de valor</th><th class="num">Pedidos</th><th class="num">Sem imóvel nosso</th></tr></thead><tbody>');
        d.linhas.forEach(function (l) {
          h.push("<tr" + (l.sem_imovel ? ' data-falta="1"' : "") + "><td>" + esc(l.operacao) + "</td><td>" + esc(l.lugar) + '</td><td class="num">' + esc(l.quartos == null ? "–" : l.quartos) +
                 "</td><td>" + esc(l.preco) + '</td><td class="num">' + l.pedidos + '</td><td class="num">' + l.sem_imovel + "</td></tr>");
        });
        h.push("</tbody></table></div>");
      }
      $("gc-dem-corpo").innerHTML = h.join("");
    }).catch(function (e) { $("gc-dem-corpo").innerHTML = '<p class="gc-vazio">Não consegui somar: ' + esc(e.message) + "</p>"; });
  }

  /* ── apelidos ── */
  var nomesDoCadastro = { bairro: [], condominio: [] };
  function encherNomes() {
    var tipo = $("gc-ap-tipo").value;
    $("gc-ap-nomes").innerHTML = (nomesDoCadastro[tipo] || []).map(function (n) { return '<option value="' + esc(n) + '">'; }).join("");
  }
  function carregarApelidos() {
    $("gc-ap-corpo").innerHTML = '<p class="ga-carregando">Carregando…</p>';
    return pedir("/admin/api/grupos/captacao/apelidos").then(function (d) {
      nomesDoCadastro = { bairro: d.bairros || [], condominio: d.condominios || [] };
      encherNomes();
      var h = ['<table class="gc-tabela"><thead><tr><th>Como escrevem</th><th>Tipo</th><th>Nome no cadastro</th><th></th></tr></thead><tbody>'];
      (d.apelidos || []).forEach(function (a) {
        h.push("<tr><td><b>" + esc(a.apelido) + "</b></td><td>" + (a.tipo === "bairro" ? "bairro" : "condomínio") + "</td><td>" + esc(a.oficial) +
               (a.obs ? ' <small style="color:var(--texto-fraco)">(' + esc(a.obs) + ")</small>" : "") +
               '</td><td><button type="button" class="btn-mini" data-gc-excluir="' + esc(a.apelido) + '">excluir</button></td></tr>');
      });
      if (!(d.apelidos || []).length) h.push('<tr><td colspan="4">Nenhum apelido ainda.</td></tr>');
      h.push("</tbody></table>");
      $("gc-ap-corpo").innerHTML = h.join("");
    }).catch(function (e) { $("gc-ap-corpo").innerHTML = '<p class="gc-vazio">Não consegui carregar: ' + esc(e.message) + "</p>"; });
  }
  function abrirApelidos(apelido, tipo, oficial) {
    var dlg = $("gc-apelidos");
    $("gc-ap-erro").textContent = "";
    $("gc-ap-apelido").value = apelido || "";
    if (tipo) $("gc-ap-tipo").value = tipo;
    $("gc-ap-oficial").value = oficial || "";
    if (!dlg.open) dlg.showModal();
    carregarApelidos().then(function () { (apelido ? $("gc-ap-oficial") : $("gc-ap-apelido")).focus(); });
  }
  function salvarApelido(ev) {
    ev.preventDefault();
    $("gc-ap-erro").textContent = "";
    pedir("/admin/api/grupos/captacao/apelidos", { method: "POST", body: JSON.stringify({
      apelido: $("gc-ap-apelido").value, tipo: $("gc-ap-tipo").value, oficial: $("gc-ap-oficial").value }) })
      .then(function () {
        $("gc-ap-apelido").value = ""; $("gc-ap-oficial").value = "";
        carregarApelidos();
        setTimeout(carregar, 12000);           // o leitor refaz a conta na passada seguinte
      })
      .catch(function (e) { $("gc-ap-erro").textContent = e.message; });
  }

  /* ── ligações ── */
  document.addEventListener("click", function (ev) {
    var alvo = ev.target.closest ? ev.target : null;
    if (!alvo) return;
    /* "+ Nova mensagem" é da agenda: nesta aba não há o que criar */
    var aba = alvo.closest("[data-painel-abre]");
    if (aba && $("ga-nova")) $("ga-nova").style.display = aba.getAttribute("data-painel-abre") === "captacao" ? "none" : "";
    if (alvo.closest('[data-painel-abre="captacao"]')) {
      if (!estado.carregou) carregar();
      try { history.replaceState(null, "", "#captacao"); } catch (_) { /* sem histórico */ }
      return;
    }
    var fechar = alvo.closest("#gc-demanda [data-fechar], #gc-apelidos [data-fechar], #gc-enviar [data-fechar], #gc-varios [data-fechar]");
    if (fechar) { var dlg = fechar.closest("dialog"); if (dlg.open) dlg.close(); return; }
    /* nomes próprios (data-gc-...): o ouvinte geral do grupos-agenda.js pega todo botão com data-dias (período das
       métricas) e data-excluir (apaga mensagem agendada) */
    var dias = alvo.closest("#gc-dem-dias [data-gc-dias]");
    if (dias) {
      estado.demandaDias = parseInt(dias.getAttribute("data-gc-dias"), 10) || 30;
      Array.prototype.forEach.call($("gc-dem-dias").querySelectorAll("[data-gc-dias]"), function (b) { b.setAttribute("aria-pressed", b === dias ? "true" : "false"); });
      abrirDemanda();
      return;
    }
    var excluir = alvo.closest("[data-gc-excluir]");
    if (excluir) {
      pedir("/admin/api/grupos/captacao/apelidos", { method: "DELETE", body: JSON.stringify({ apelido: excluir.getAttribute("data-gc-excluir") }) })
        .then(function () { carregarApelidos(); setTimeout(carregar, 12000); })
        .catch(function (e) { $("gc-ap-erro").textContent = e.message; });
      return;
    }
    if (!painel.contains(alvo)) return;
    var filtro = alvo.closest("[data-filtro]");
    if (filtro) { estado.filtro = filtro.getAttribute("data-filtro"); carregar(); return; }
    if (alvo.closest("#gc-atualizar")) { carregar(); return; }
    if (alvo.closest("#gc-ver-demanda")) { abrirDemanda(); return; }
    if (alvo.closest("#gc-ver-apelidos")) { abrirApelidos(); return; }
    var apelido = alvo.closest("[data-apelido]");
    if (apelido) { abrirApelidos(apelido.getAttribute("data-apelido"), apelido.getAttribute("data-tipo"), apelido.getAttribute("data-oficial")); return; }
    var acao = alvo.closest("[data-acao]");
    if (acao) agir(acao.closest(".gc-item"), acao.getAttribute("data-acao"), acao);
  });
  $("gc-teste").addEventListener("submit", testar);
  if ($("gc-nota")) {
    $("gc-nota").value = String(estado.nota);
    $("gc-ordem").value = estado.ordem;
    $("gc-nota").addEventListener("change", function () {
      estado.nota = parseInt(this.value, 10) || 0;
      try { localStorage.setItem("gc-nota", String(estado.nota)); } catch (e) { /* ok */ }
      carregar();
    });
    $("gc-ordem").addEventListener("change", function () {
      estado.ordem = this.value === "nota" ? "nota" : "recentes";
      try { localStorage.setItem("gc-ordem", estado.ordem); } catch (e) { /* ok */ }
      carregar();
    });
  }
  $("gc-env-form").addEventListener("submit", enviar);
  /* 382: o popup de vários imóveis */
  $("gc-var-form").addEventListener("submit", enviarVarios);
  $("gc-varios").addEventListener("click", mexerNaLista);
  $("gc-var-busca").addEventListener("input", function () { clearTimeout(esperaBusca); esperaBusca = setTimeout(buscarNoCatalogo, 150); });
  $("gc-var-busca").addEventListener("keydown", function (ev) {
    if (ev.key !== "Enter") return;
    ev.preventDefault();                       // Enter na busca adiciona o primeiro achado; não envia o formulário
    var b = $("gc-var-achados").querySelector('button[data-var="achado"]:not([disabled])');
    if (b) b.click();
  });
  $("gc-arquivos").addEventListener("change", function () {
    if (this.files && this.files.length) importar(this.files);
    this.value = "";                           // escolher o mesmo arquivo de novo volta a disparar
  });
  $("gc-ap-form").addEventListener("submit", salvarApelido);
  $("gc-ap-tipo").addEventListener("change", encherNomes);

  /* a aba pode ser aberta direto pelo endereço: grupos.html#captacao */
  if (location.hash === "#captacao") {
    var aba = document.querySelector('[data-painel-abre="captacao"]');
    if (aba) aba.click();
  }
  /* com a aba aberta, a lista se renova sozinha (o leitor passa a cada 10 s) */
  setInterval(function () {
    if (!painel.hidden && estado.carregou && document.visibilityState === "visible" && !painel.querySelector(".gc-errou, .gc-negocia") &&
        !$("gc-demanda").open && !$("gc-apelidos").open && !$("gc-enviar").open && !$("gc-varios").open) carregar();
  }, 45000);
})();
