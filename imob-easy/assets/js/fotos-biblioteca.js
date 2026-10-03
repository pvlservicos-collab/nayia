/* ==========================================================================
   Imob Easy — a BIBLIOTECA DE FOTOS do cadastro de imóvel

   Pedro, 03/10/2026: "cria no cadastro de imóveis uma biblioteca de subir
   imagens manualmente, abre um popup e eu posso subir do meu computador direto
   em um imóvel que já existe no menu editar, ou lá em criar imóvel tenha esse
   campo que monta a galeria, e eu posso mudar a ordem das fotos" / "excluir
   fotos também".

   DOIS MODOS, a mesma galeria:
   - EDITAR (o imóvel existe): o botão "Gerenciar fotos" abre o popup. Subir,
     reordenar e excluir valem na hora, pela API com a senha do painel
     (admin/api/imoveis/<código>/fotos, nay-site-api/fotos_api.py).
   - CRIAR (ainda não há código): a galeria é um campo da página. As fotos ficam
     no navegador, na ordem escolhida, e sobem logo depois do "Cadastrar"
     (imovel-editar.js chama FotosBiblioteca.enviarPendentes antes de ir ao
     editor).

   A PRIMEIRA FOTO É A CAPA. Arrastar muda a ordem; as setas e a estrela fazem o
   mesmo no celular e no teclado.

   Mexer nas fotos de um imóvel que veio do site antigo marca o imóvel como
   "fotos editadas à mão" (migração 283): dali em diante a conferência diária do
   site antigo não troca mais as fotos dele.
   ========================================================================== */
(function () {
  "use strict";

  var params = new URLSearchParams(location.search);
  var codigo = params.get("codigo");
  var novo = !codigo && params.get("novo") === "1";
  if (!codigo && !novo) return;

  var TIPOS = ["image/jpeg", "image/png", "image/webp"];
  var MAXIMO = 25 * 1024 * 1024;
  var API = "api/imoveis/";

  function esc(v) {
    return String(v == null ? "" : v).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }
  function mega(b) { return (b / 1048576).toLocaleString("pt-BR", { maximumFractionDigits: 1 }) + " MB"; }

  /* ---- estado ---- */
  var itens = [];          // { id, url, arquivo, enviando, erro }
  var raiz = null;         // onde a galeria está desenhada
  var mudou = false;       // alguma coisa mudou no servidor (o editor recarrega as fotos dele)
  var ocupada = 0;         // envios em andamento
  var arrastando = null;   // índice do item que está sendo arrastado
  var temporizador = null;
  var aviso = "";
  var doSiteAntigo = false, jaManual = false;

  function estado(texto, tipo) {
    aviso = texto || "";
    var e = raiz && raiz.querySelector("[data-fb-estado]");
    if (!e) return;
    e.textContent = aviso;
    e.className = "fb__estado" + (tipo ? " fb__estado--" + tipo : "");
  }

  /* ---- desenho ---- */
  function desenhar() {
    if (!raiz) return;
    var travada = !novo && ocupada > 0;      // no servidor, a ordem só muda com os envios terminados
    raiz.innerHTML =
      '<label class="fb__soltar" data-fb-soltar>' +
        '<input type="file" multiple accept="' + TIPOS.join(",") + '" data-fb-arquivos>' +
        '<span class="fb__soltar-ico" aria-hidden="true">＋</span>' +
        "<span><b>Arraste as fotos para cá</b> ou <u>escolha do computador</u>" +
        "<small>JPG, PNG ou WEBP, até 25 MB cada. Pode escolher várias de uma vez.</small></span>" +
      "</label>" +
      (doSiteAntigo && !jaManual && !novo
        ? '<p class="fb__nota">Este imóvel tem fotos que vieram do site antigo. Depois da primeira mudança aqui, a atualização automática das fotos pelo site antigo deixa de valer para ele: fica o que você montar.</p>'
        : "") +
      '<p class="fb__estado" data-fb-estado aria-live="polite">' + esc(aviso) + "</p>" +
      (itens.length
        ? '<ol class="fb__grade' + (travada ? " fb__grade--travada" : "") + '" data-fb-grade>' + itens.map(function (f, k) {
            var acoes = f.enviando ? '<span class="fb__vel">Enviando…</span>'
              : f.erro ? '<span class="fb__vel fb__vel--erro">' + esc(f.erro) + ' <button type="button" data-fb-excluir="' + k + '">tirar</button></span>'
              : '<span class="fb__acoes">' +
                  '<button type="button" data-fb-mover="' + k + '" data-para="-1" title="Mover para antes" aria-label="Mover a foto ' + (k + 1) + ' para antes"' + (k === 0 || travada ? " disabled" : "") + ">‹</button>" +
                  '<button type="button" data-fb-capa="' + k + '" title="Tornar a capa" aria-label="Tornar a foto ' + (k + 1) + ' a capa"' + (k === 0 || travada ? " disabled" : "") + ">★</button>" +
                  '<button type="button" data-fb-mover="' + k + '" data-para="1" title="Mover para depois" aria-label="Mover a foto ' + (k + 1) + ' para depois"' + (k === itens.length - 1 || travada ? " disabled" : "") + ">›</button>" +
                  '<button type="button" class="fb__excluir" data-fb-excluir="' + k + '" title="Excluir a foto" aria-label="Excluir a foto ' + (k + 1) + '">✕</button>' +
                "</span>";
            return '<li class="fb__item' + (f.enviando ? " fb__item--enviando" : "") + (f.erro ? " fb__item--erro" : "") + '" data-fb-k="' + k + '"' +
                (f.enviando || f.erro || travada ? "" : ' draggable="true"') + ">" +
              '<img src="' + esc(f.url) + '" alt="Foto ' + (k + 1) + '" loading="lazy" draggable="false">' +
              '<span class="fb__n">' + (k + 1) + "</span>" + (k === 0 && !f.erro ? '<span class="fb__capa">Capa</span>' : "") + acoes + "</li>";
          }).join("") + "</ol>"
        : '<p class="fb__vazio">' + (novo ? "Nenhuma foto ainda. As fotos sobem junto com o cadastro." : "Este imóvel ainda não tem foto.") + "</p>") +
      (itens.length > 1 ? '<p class="fb__dica">A primeira é a capa. Arraste para mudar a ordem' + (novo ? "." : ": a ordem é salva sozinha.") + "</p>" : "");
    var conta = document.querySelector("[data-fb-conta]");
    if (conta) conta.textContent = validas().length + (validas().length === 1 ? " foto" : " fotos");
    document.dispatchEvent(new CustomEvent("fotos-biblioteca-mudou", { detail: { total: validas().length } }));
  }
  function validas() { return itens.filter(function (f) { return !f.erro; }); }

  /* ---- a ordem ---- */
  function mover(de, para) {
    if (de === para || de < 0 || para < 0 || de >= itens.length || para >= itens.length) return;
    var f = itens.splice(de, 1)[0];
    itens.splice(para, 0, f);
    desenhar();
    if (!novo) salvarOrdem();
  }
  function salvarOrdem() {
    clearTimeout(temporizador);
    temporizador = setTimeout(function () {
      var ids = itens.filter(function (f) { return f.id; }).map(function (f) { return f.id; });
      if (!ids.length) return;
      estado("Salvando a ordem…");
      fetch(API + encodeURIComponent(codigo) + "/fotos/ordem", {
        method: "PUT", credentials: "same-origin", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ ids: ids })
      }).then(function (r) { return r.json().catch(function () { return {}; }).then(function (d) { return { ok: r.ok && d.ok, d: d, status: r.status }; }); })
        .then(function (res) {
          if (res.ok) { mudou = true; jaManual = true; estado("Ordem salva.", "ok"); return; }
          estado(res.status === 401 ? "A senha do painel não foi aceita: recarregue a página." : (res.d.erro || "Não salvou a ordem."), "erro");
          if (res.status === 409) carregar();      // a tela estava velha: mostra o que há de verdade
        })
        .catch(function () { estado("Sem conexão: a ordem não foi salva.", "erro"); });
    }, 350);
  }

  /* ---- subir ---- */
  function recusa(arquivo) {
    if (TIPOS.indexOf(arquivo.type) < 0 && !/\.(jpe?g|png|webp)$/i.test(arquivo.name)) {
      return /\.(heic|heif)$/i.test(arquivo.name) ? "foto em HEIC (iPhone): salve como JPG" : "não é JPG, PNG nem WEBP";
    }
    if (arquivo.size > MAXIMO) return "grande demais (" + mega(arquivo.size) + "; o limite é 25 MB)";
    return "";
  }
  function receber(lista) {
    var arquivos = Array.prototype.slice.call(lista || []);
    if (!arquivos.length) return;
    var recusados = [];
    var bons = arquivos.filter(function (a) { var m = recusa(a); if (m) recusados.push(a.name + ": " + m); return !m; });
    if (novo) {
      bons.forEach(function (a) { itens.push({ arquivo: a, url: URL.createObjectURL(a) }); });
      estado(recusados.length ? "Ficaram de fora — " + recusados.join("; ") : "", recusados.length ? "erro" : "");
      desenhar();
      return;
    }
    var novos = bons.map(function (a) { var f = { arquivo: a, url: URL.createObjectURL(a), enviando: true }; itens.push(f); return f; });
    ocupada += novos.length;
    desenhar();
    var feitas = 0, falhas = recusados.slice();
    var proxima = function () {
      var f = novos.shift();
      if (!f) {
        estado(falhas.length ? "Não subiram — " + falhas.join("; ") : feitas + (feitas === 1 ? " foto enviada." : " fotos enviadas."), falhas.length ? "erro" : "ok");
        return;
      }
      estado("Enviando " + (feitas + 1) + " de " + (feitas + 1 + novos.length) + "…");
      enviar(codigo, f.arquivo).then(function (r) {
        f.enviando = false; ocupada--;
        if (r.ok) { f.id = r.id; f.url = r.url; f.arquivo = null; feitas++; mudou = true; jaManual = true; }
        else { f.erro = "não subiu: " + (r.erro || "erro"); falhas.push(f.arquivo.name + ": " + (r.erro || "erro")); }
        desenhar();
        proxima();
      });
    };
    proxima();
  }
  function enviar(cod, arquivo) {
    return fetch(API + encodeURIComponent(cod) + "/fotos", {
      method: "POST", credentials: "same-origin",
      headers: { "Content-Type": arquivo.type || "application/octet-stream" }, body: arquivo
    }).then(function (r) {
      return r.json().catch(function () { return {}; }).then(function (d) {
        if (r.status === 401) return { ok: false, erro: "a senha do painel não foi aceita" };
        return r.ok && d.ok ? d : { ok: false, erro: d.erro || ("erro " + r.status) };
      });
    }).catch(function () { return { ok: false, erro: "sem conexão" }; });
  }

  /* ---- excluir ---- */
  function excluir(k) {
    var f = itens[k];
    if (!f) return;
    if (novo || f.erro || !f.id) {
      if (f.arquivo) { try { URL.revokeObjectURL(f.url); } catch (e) { /* já foi */ } }
      itens.splice(k, 1); desenhar(); return;
    }
    if (!window.confirm("Excluir a foto " + (k + 1) + " deste imóvel?\n\nEla some do site, da Nay e do card. Não dá para desfazer.")) return;
    estado("Excluindo…");
    fetch(API + encodeURIComponent(codigo) + "/fotos/" + encodeURIComponent(f.id), { method: "DELETE", credentials: "same-origin" })
      .then(function (r) { return r.json().catch(function () { return {}; }).then(function (d) { return { ok: r.ok && d.ok, d: d, status: r.status }; }); })
      .then(function (res) {
        if (!res.ok && res.status !== 404) {
          estado(res.status === 401 ? "A senha do painel não foi aceita: recarregue a página." : (res.d.erro || "Não excluiu."), "erro");
          return;
        }
        mudou = true; jaManual = true;
        var i = itens.indexOf(f);
        if (i >= 0) itens.splice(i, 1);
        estado("Foto excluída.", "ok");
        desenhar();
      })
      .catch(function () { estado("Sem conexão: a foto não foi excluída.", "erro"); });
  }

  /* ---- carregar do servidor (editar) ---- */
  function carregar() {
    return fetch(API + encodeURIComponent(codigo) + "/fotos", { credentials: "same-origin" })
      .then(function (r) {
        if (r.status === 401) throw new Error("a senha do painel não foi aceita: recarregue a página");
        if (!r.ok) throw new Error("não consegui ler as fotos (erro " + r.status + ")");
        return r.json();
      })
      .then(function (d) {
        itens = (d.fotos || []).map(function (f) { return { id: f.id, url: f.url }; });
        doSiteAntigo = (d.fotos || []).some(function (f) { return f.do_site_antigo; });
        jaManual = !!d.manual;
        desenhar();
      })
      .catch(function (e) { itens = []; desenhar(); estado(e.message, "erro"); });
  }

  /* ---- eventos da galeria (delegados: o desenho troca o miolo a cada mudança) ---- */
  function ligar(el) {
    el.addEventListener("click", function (e) {
      var b = e.target.closest ? e.target.closest("button") : null;
      if (!b || !el.contains(b)) return;
      if (b.hasAttribute("data-fb-mover")) { var k = Number(b.getAttribute("data-fb-mover")); mover(k, k + Number(b.getAttribute("data-para"))); }
      else if (b.hasAttribute("data-fb-capa")) mover(Number(b.getAttribute("data-fb-capa")), 0);
      else if (b.hasAttribute("data-fb-excluir")) excluir(Number(b.getAttribute("data-fb-excluir")));
    });
    el.addEventListener("change", function (e) {
      if (!e.target.matches || !e.target.matches("[data-fb-arquivos]")) return;
      e.stopPropagation();                       // o formulário do cadastro não precisa saber deste campo
      receber(e.target.files);
      e.target.value = "";
    });
    // soltar arquivos do computador
    ["dragenter", "dragover"].forEach(function (tipo) {
      el.addEventListener(tipo, function (e) {
        if (arrastando !== null || !e.dataTransfer || Array.prototype.indexOf.call(e.dataTransfer.types || [], "Files") < 0) return;
        e.preventDefault();
        var s = el.querySelector("[data-fb-soltar]"); if (s) s.classList.add("fb__soltar--sobre");
      });
    });
    ["dragleave", "drop"].forEach(function (tipo) {
      el.addEventListener(tipo, function () { var s = el.querySelector("[data-fb-soltar]"); if (s) s.classList.remove("fb__soltar--sobre"); });
    });
    el.addEventListener("drop", function (e) {
      if (arrastando !== null) return;
      if (e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files.length) { e.preventDefault(); receber(e.dataTransfer.files); }
    });
    // arrastar uma foto para outra posição
    el.addEventListener("dragstart", function (e) {
      var li = e.target.closest ? e.target.closest(".fb__item") : null;
      if (!li || li.getAttribute("draggable") !== "true") return;
      arrastando = Number(li.getAttribute("data-fb-k"));
      li.classList.add("fb__item--arrastando");
      try { e.dataTransfer.effectAllowed = "move"; e.dataTransfer.setData("text/plain", String(arrastando)); } catch (x) { /* navegador antigo */ }
    });
    el.addEventListener("dragover", function (e) {
      if (arrastando === null) return;
      var li = e.target.closest ? e.target.closest(".fb__item") : null;
      if (!li) return;
      e.preventDefault();
      var r = li.getBoundingClientRect();
      var depois = e.clientX > r.left + r.width / 2;
      Array.prototype.forEach.call(el.querySelectorAll(".fb__item--antes, .fb__item--depois"), function (x) { x.classList.remove("fb__item--antes", "fb__item--depois"); });
      li.classList.add(depois ? "fb__item--depois" : "fb__item--antes");
    });
    el.addEventListener("drop", function (e) {
      if (arrastando === null) return;
      var li = e.target.closest ? e.target.closest(".fb__item") : null;
      var de = arrastando; arrastando = null;
      if (!li) { desenhar(); return; }
      e.preventDefault();
      var alvo = Number(li.getAttribute("data-fb-k"));
      var r = li.getBoundingClientRect();
      var para = alvo + (e.clientX > r.left + r.width / 2 ? 1 : 0);
      if (de < para) para--;
      if (para === de) desenhar(); else mover(de, para);
    });
    el.addEventListener("dragend", function () { if (arrastando !== null) { arrastando = null; desenhar(); } });
  }

  /* ---- EDITAR: o popup ---- */
  var dialogo = null;
  function abrir() {
    if (!dialogo) {
      dialogo = document.createElement("dialog");
      dialogo.className = "fb-dialogo";
      dialogo.setAttribute("aria-labelledby", "fb-titulo");
      dialogo.innerHTML =
        '<div class="fb-dialogo__caixa">' +
          '<div class="fb-dialogo__topo"><h2 id="fb-titulo">Fotos do imóvel ' + esc(codigo) + '</h2>' +
            '<button type="button" class="fb-dialogo__x" data-fb-fechar aria-label="Fechar">✕</button></div>' +
          '<div class="fb" data-fb-raiz><p class="fb__vazio">Carregando as fotos…</p></div>' +
          '<div class="fb-dialogo__pe"><span data-fb-conta></span><button type="button" class="btn-azul" data-fb-fechar>Pronto</button></div>' +
        "</div>";
      document.body.appendChild(dialogo);
      raiz = dialogo.querySelector("[data-fb-raiz]");
      ligar(raiz);
      dialogo.addEventListener("click", function (e) {
        if (e.target === dialogo || (e.target.closest && e.target.closest("[data-fb-fechar]"))) dialogo.close();
      });
      dialogo.addEventListener("close", function () {
        if (mudou && window.edFotos && window.edFotos.recarregar) window.edFotos.recarregar();
        mudou = false;
      });
      // soltar um arquivo fora da área não pode fazer o navegador abrir a foto no lugar da página
      dialogo.addEventListener("dragover", function (e) { e.preventDefault(); });
      dialogo.addEventListener("drop", function (e) { e.preventDefault(); });
    }
    aviso = "";
    if (dialogo.showModal) dialogo.showModal(); else dialogo.setAttribute("open", "");
    carregar();
  }
  if (!novo) {
    document.addEventListener("click", function (e) {
      var b = e.target.closest ? e.target.closest("[data-fotos-biblioteca]") : null;
      if (b) { e.preventDefault(); abrir(); }
    });
  }

  /* ---- CRIAR: o campo da página ---- */
  function montarCampo() {
    var antes = document.getElementById("ed-cartoes");
    if (!antes || document.getElementById("fb-campo")) return;
    var s = document.createElement("section");
    s.className = "fb-campo";
    s.id = "fb-campo";
    s.innerHTML = '<div class="fb-campo__topo"><h2>Fotos</h2><span data-fb-conta>0 fotos</span></div><div class="fb" data-fb-raiz></div>';
    antes.parentNode.insertBefore(s, antes);
    raiz = s.querySelector("[data-fb-raiz]");
    ligar(raiz);
    s.addEventListener("dragover", function (e) { e.preventDefault(); });
    s.addEventListener("drop", function (e) { e.preventDefault(); });
    desenhar();
  }
  if (novo) {
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", montarCampo); else montarCampo();
    window.addEventListener("beforeunload", function (e) {
      if (validas().length && !window.FotosBiblioteca.enviando) { e.preventDefault(); e.returnValue = ""; }
    });
  }

  /* ---- o que o editor usa ---- */
  window.FotosBiblioteca = {
    enviando: false,
    pendentes: function () { return novo ? validas().length : 0; },
    /* sobe, NA ORDEM, as fotos montadas no cadastro novo; devolve { enviadas, falhas: [nomes] } */
    enviarPendentes: function (cod, progresso) {
      var fila = validas().slice(), total = fila.length, enviadas = 0, falhas = [];
      window.FotosBiblioteca.enviando = true;
      var proxima = function () {
        var f = fila.shift();
        if (!f) return Promise.resolve({ enviadas: enviadas, falhas: falhas });
        if (progresso) progresso(enviadas + falhas.length + 1, total);
        return enviar(cod, f.arquivo).then(function (r) {
          if (r.ok) enviadas++; else falhas.push(f.arquivo.name + " (" + (r.erro || "erro") + ")");
          return proxima();
        });
      };
      return proxima();
    }
  };
})();
