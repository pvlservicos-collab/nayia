/* ==========================================================================
   Imob Easy — Aba CADASTRO RÁPIDO de Imóveis (site e CRM)

   Pedro, 09/10/2026: "quero uma tela de cadastro de imóveis, hoje temos várias
   fontes, WhatsApp, OLX, quero todos agrupados em uma página ... ele abre um
   popup e vamos passando imóvel por imóvel e marcando os campos que faltam ...
   aprovado ali já fica disponível para a Nay oferecer, vai ser uma curadoria
   geral de todas as fontes, incluindo os que foram novos cadastros pelos
   proprietários mesmo se faltar algo, foto e tudo mais".
   E depois: "você dividiu em 2, não quero isso, quero um só filtro para depois
   que acabar ter tudo resolvido; quero os campos lá igual na tela de cadastrar
   imóvel; se não tiver foto quero saber; se na verdade esse imóvel é outro quero
   marcar, pesquisar o outro e dizer que é uma atualização dele, aí abre o que
   mudou e eu edito; e um card só da origem: de onde veio, se por WhatsApp de
   qual número e quando".

   UMA FILA SÓ: tudo o que espera gente (nai_cadastro_pendente, 248) -- rascunho
   de qualquer origem, ficha que o dono ditou na conversa, bloqueado, no ar sem
   foto ou faltando o essencial. Quem passa a fila até o fim deixa tudo resolvido.
   (A antiga aba CADASTRO PENDENTE saiu: era a mesma lista em outro lugar.)

   O POPUP é o próprio cadastro do site num iframe da mesma origem:
     · imóvel com código: o editor (imovel-editar.html), com condomínio que
       preenche o endereço, "falta preencher" e fotos;
     · ficha do dono sem imóvel: a tela de cadastrar (imovel-novo.html) já
       preenchida com o que ele contou; ao cadastrar, as fotos dele e o dono
       entram junto (site_juntar_cadastro, 326).
   Em cima: o CARD DA ORIGEM (site_origem_do_cadastro, 326), o aviso de foto,
   Importar tudo, Pular, APROVAR (Disponível: site e Nay, menos parceiro) e
   "É ATUALIZAÇÃO DE OUTRO IMÓVEL?": pesquisa o imóvel, mostra o que mudou
   campo a campo (editável, cada um com a sua marca), aplica no outro pelo PUT
   de sempre, leva as fotos e o dono, e este vira Excluído (nada se apaga).
   ========================================================================== */
(function () {
  "use strict";

  var aba = document.querySelector('[data-painel-abre="rapido"]');
  var painel = document.querySelector('[data-painel="rapido"]');
  if (!aba || !painel) return;

  function $(id) { return document.getElementById(id); }
  function esc(t) {
    return String(t == null ? "" : t).replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }
  function semAcento(t) { return String(t || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase(); }
  function cor(p) { return p >= 90 ? "#3f9c6d" : p >= 50 ? "#c4762f" : "#b42323"; }
  function quando(iso) {
    if (!iso) return "";
    var d = new Date(iso);
    if (isNaN(d)) return String(iso);
    return d.toLocaleString("pt-BR", { timeZone: "America/Manaus", day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" });
  }
  function fone(t) {
    var d = String(t || "").replace(/\D/g, "").replace(/^55(?=\d{10,11}$)/, "");
    if (d.length === 11) return "(" + d.slice(0, 2) + ") " + d.slice(2, 7) + "-" + d.slice(7);
    if (d.length === 10) return "(" + d.slice(0, 2) + ") " + d.slice(2, 6) + "-" + d.slice(6);
    return t || "";
  }
  var API = window.API_BASE || "";

  /* ---- de onde veio ---------------------------------------------------------- */
  var FONTES = [
    { k: "", rotulo: "Todas" }, { k: "olx", rotulo: "OLX" }, { k: "conversa", rotulo: "Conversa do dono" },
    { k: "crm", rotulo: "Captação (CRM)" }, { k: "secretaria", rotulo: "Secretária" }, { k: "site", rotulo: "Site" },
    { k: "antigo", rotulo: "Site antigo" }, { k: "outros", rotulo: "Outras" }
  ];
  function fonteDe(it) {
    if (it.fonte === "ficha") return "conversa";
    var o = String(it.origem || "").toLowerCase();
    if (o === "olx") return "olx";
    if (o === "captacao") return "conversa";
    if (o === "crm") return "crm";
    if (o === "secretaria") return "secretaria";
    if (o === "site") return "site";
    if (o.indexOf("planilha") === 0 || o.indexOf("site_antigo") >= 0) return "antigo";
    return "outros";
  }
  function rotuloDaFonte(k) { var f = FONTES.filter(function (x) { return x.k === k; })[0]; return f ? f.rotulo : k; }
  function foraDoAr(it) {
    return it.fonte === "ficha" || it.status === "Rascunho" || it.motivos.some(function (m) { return /bloqueado|Rascunho/.test(m); });
  }
  function semFoto(it) {
    return it.fonte === "ficha" ? false : Number(it.fotos || 0) === 0;
  }

  /* ---- O QUE A IA SUPÕE QUE É (332; Pedro, 09/10: "prejulgue em categorias ... com cores ... em ordem") --------
     O palpite vem pronto do servidor (nay-captacao/captacao/palpite.py, de 5 em 5 minutos). A ordem daqui é a da
     fila: o que mais vale abrir primeiro. */
  var CATS = [
    { k: "novo", rotulo: "Imóvel novo para anunciar", cor: "#16a34a" },
    { k: "atualizacao", rotulo: "Atualização de imóvel que já temos", cor: "#2563eb" },
    { k: "completar", rotulo: "Cadastro para completar", cor: "#7c3aed" },
    { k: "indisponivel", rotulo: "Alugado ou indisponível agora", cor: "#d97706" },
    { k: "repetido", rotulo: "Repetido de outro da fila", cor: "#6b7280" },
    { k: "nao_e", rotulo: "Não é para cadastrar", cor: "#dc2626" },
    { k: "", rotulo: "Ainda sem palpite", cor: "#9ca3af" }
  ];
  function catDe(it) {
    var k = (it.palpite && it.palpite.categoria) || "";
    return CATS.some(function (c) { return c.k === k; }) ? k : "";
  }
  function dadosDaCat(k) { return CATS.filter(function (c) { return c.k === k; })[0] || CATS[CATS.length - 1]; }
  function ordemDaCat(it) { var k = catDe(it); for (var i = 0; i < CATS.length; i++) if (CATS[i].k === k) return i; return CATS.length; }
  function seloDaCat(it) {
    var c = dadosDaCat(catDe(it));
    return '<span class="cr-cat" style="background:' + c.cor + '">' + esc(c.rotulo) + "</span>";
  }

  /* ---- o estilo (variáveis do site: segue o tema dentro do CRM) -------------- */
  var css = document.createElement("style");
  css.textContent =
    ".cr-topo{display:flex;flex-wrap:wrap;gap:10px;align-items:center;margin:0 0 12px}" +
    ".cr-chips{display:flex;flex-wrap:wrap;gap:6px}" +
    ".cr-chip{height:32px;padding:0 12px;border-radius:999px;border:1px solid var(--borda-forte,#cfcfca);background:var(--superficie,#fff);color:var(--texto,#16161a);font:inherit;font-size:13px;cursor:pointer}" +
    ".cr-chip b{margin-left:4px}" +
    ".cr-chip[aria-pressed=true]{background:var(--roxo,#6d28d9);border-color:var(--roxo,#6d28d9);color:#fff}" +
    ".cr-comecar{height:40px;padding:0 18px;border:0;border-radius:999px;background:#16a34a;color:#fff;font:inherit;font-weight:700;cursor:pointer}" +
    ".cr-comecar[disabled]{opacity:.5;cursor:default}" +
    ".cr-olx{margin:0 0 14px;padding:12px 14px;border:1px dashed var(--borda-forte,#cfcfca);border-radius:12px;background:var(--superficie,#fff)}" +
    ".cr-olx form{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin-top:8px}" +
    ".cr-olx input{flex:1 1 320px;height:36px;padding:0 10px;border:1px solid var(--borda-forte,#cfcfca);border-radius:8px;font:inherit;background:var(--superficie,#fff);color:var(--texto,#16161a)}" +
    ".cr-olx .cr-fav{display:inline-flex;align-items:center;height:32px;padding:0 12px;border-radius:999px;background:#6e0ad6;color:#fff;font-weight:700;font-size:13px;text-decoration:none;cursor:grab}" +
    ".cr-nota{font-size:12.5px;color:var(--texto-fraco,#6f6f74);line-height:1.4}" +
    ".cr-lista td{vertical-align:top}" +
    ".cr-barrinha{display:inline-block;width:70px;height:6px;border-radius:4px;background:var(--borda,#e2e2de);overflow:hidden;vertical-align:middle;margin-right:6px}" +
    ".cr-barrinha>i{display:block;height:100%;border-radius:4px}" +
    ".cr-semfoto{display:inline-block;padding:1px 8px;border-radius:999px;font-size:11px;font-weight:700;background:#fde8e8;color:#b42323;white-space:nowrap}" +
    ".cr-comfoto{display:inline-block;padding:1px 8px;border-radius:999px;font-size:11px;font-weight:700;background:#e8f7f0;color:#2f7d58;white-space:nowrap}" +
    /* o popup */
    ".cr-veu{position:fixed;inset:0;z-index:2000;background:rgba(0,0,0,.55);display:flex;align-items:stretch;justify-content:center;padding:14px}" +
    /* 09/10: o display:flex de cima vencia o [hidden]: o ✕ esvaziava o popup e ele ficava na frente, sem fechar */
    ".cr-veu[hidden],.cr-veu [hidden]{display:none!important}" +
    /* o que a IA supõe que é: o selo colorido, os chips da lista e a lista suspensa entre as setas */
    ".cr-cat{display:inline-block;padding:2px 9px;border-radius:999px;font-size:11.5px;font-weight:700;color:#fff;white-space:nowrap}" +
    ".cr-cats{display:flex;flex-wrap:wrap;gap:6px;align-items:center;margin:0 0 12px}" +
    ".cr-cats .cr-chip i{display:inline-block;width:9px;height:9px;border-radius:50%;margin-right:6px}" +
    ".cr-nav select{height:34px;max-width:300px;padding:0 10px;border-radius:999px;border:1px solid #374151;border-left:7px solid #9ca3af;background:#1f2937;color:#f9fafb;font:inherit;font-size:13px;font-weight:600;cursor:pointer}" +
    /* a conversa: o desenho do chat do CRM (papel, balões, hora), só leitura */
    ".cr-conv-veu{position:fixed;inset:0;z-index:2100;background:rgba(0,0,0,.55);display:flex;align-items:center;justify-content:center;padding:14px}" +
    ".cr-conv-veu[hidden],.cr-conv-veu [hidden]{display:none!important}" +
    ".cr-conv{--cv-papel:#efeae2;--cv-in:#fff;--cv-out:#d9fdd3;--cv-tinta:#111b21;--cv-fraco:#667781;--cv-painel:#f0f2f5;--cv-linha:#e9edef;" +
      "width:min(580px,100%);height:min(88vh,920px);display:flex;flex-direction:column;border-radius:14px;overflow:hidden;background:var(--cv-papel);color:var(--cv-tinta);box-shadow:0 20px 60px rgba(0,0,0,.45);font-size:14.2px}" +
    ".crm-escuro .cr-conv{--cv-papel:#161717;--cv-in:#242626;--cv-out:#144d37;--cv-tinta:#fafafa;--cv-fraco:#a5a5a5;--cv-painel:#1d1f1f;--cv-linha:rgba(255,255,255,.09)}" +
    ".cr-conv-topo{display:flex;gap:10px;align-items:center;padding:10px 14px;background:var(--cv-painel);border-bottom:1px solid var(--cv-linha)}" +
    ".cr-conv-foto{width:40px;height:40px;border-radius:50%;background:#dfe5e7;color:#54656f;display:flex;align-items:center;justify-content:center;font-weight:700;flex:0 0 auto}" +
    ".cr-conv-quem{flex:1;min-width:0}" +
    ".cr-conv-quem b{display:block;font-size:15.5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}" +
    ".cr-conv-quem span{display:block;font-size:12.5px;color:var(--cv-fraco);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}" +
    ".cr-conv-x{width:34px;height:34px;border:0;border-radius:50%;background:transparent;color:var(--cv-fraco);font-size:18px;cursor:pointer}" +
    ".cr-conv-abas{display:flex;flex-wrap:wrap;gap:6px;padding:6px 14px;background:var(--cv-painel);border-bottom:1px solid var(--cv-linha)}" +
    ".cr-conv-abas button{height:28px;padding:0 12px;border-radius:999px;border:1px solid var(--cv-linha);background:transparent;color:var(--cv-fraco);font:inherit;font-size:12.5px;cursor:pointer}" +
    ".cr-conv-abas button[aria-pressed=true]{background:#1daa61;border-color:#1daa61;color:#fff;font-weight:700}" +
    ".cr-conv-corpo{flex:1;min-height:0;overflow-y:auto;padding:12px 5%;display:flex;flex-direction:column}" +
    ".cr-dia{align-self:center;margin:8px 0;padding:4px 10px;border-radius:8px;background:var(--cv-in);color:var(--cv-fraco);font-size:12px;box-shadow:0 1px .5px rgba(11,20,26,.13)}" +
    ".cr-msg{display:flex;margin-top:2px}" +
    ".cr-msg--out{justify-content:flex-end}" +
    ".cr-msg--novo{margin-top:9px}" +
    ".cr-balao{position:relative;max-width:78%;padding:6px 9px 7px;border-radius:8px;background:var(--cv-in);box-shadow:0 1px .5px rgba(11,20,26,.13);white-space:pre-wrap;overflow-wrap:anywhere;line-height:1.36}" +
    ".cr-msg--out .cr-balao{background:var(--cv-out)}" +
    ".cr-msg--novo .cr-balao::before{content:\"\";position:absolute;top:0;width:8px;height:13px;background:var(--cv-in)}" +
    ".cr-msg--novo.cr-msg--in .cr-balao{border-top-left-radius:0}" +
    ".cr-msg--novo.cr-msg--in .cr-balao::before{left:-8px;clip-path:polygon(0 0,100% 0,100% 100%)}" +
    ".cr-msg--novo.cr-msg--out .cr-balao{border-top-right-radius:0}" +
    ".cr-msg--novo.cr-msg--out .cr-balao::before{right:-8px;background:var(--cv-out);clip-path:polygon(0 0,100% 0,0 100%)}" +
    ".cr-autor{display:block;font-size:12px;font-weight:700;margin-bottom:2px;color:#7c3aed}" +
    ".cr-autor--gente{color:#0b6bcb}" +
    ".cr-autor--num{color:var(--cv-fraco)}" +
    ".crm-escuro .cr-autor{color:#c4b5fd}" +
    ".crm-escuro .cr-autor--gente{color:#7cc4ff}" +
    ".cr-hora{float:right;margin:7px 0 -3px 10px;font-size:11px;color:var(--cv-fraco)}" +
    ".cr-balao img,.cr-balao video{display:block;max-width:260px;max-height:300px;width:auto;height:auto;border-radius:6px;margin-bottom:4px;background:rgba(0,0,0,.06)}" +
    ".cr-balao audio{display:block;width:250px;max-width:100%;margin-bottom:4px}" +
    ".cr-transc{font-size:13px;font-style:italic;color:var(--cv-fraco)}" +
    ".cr-citado{padding:4px 8px;margin-bottom:4px;border-left:4px solid #1daa61;border-radius:6px;background:rgba(0,0,0,.06);font-size:12.5px;color:var(--cv-fraco)}" +
    ".cr-doc{display:inline-block;padding:6px 10px;margin-bottom:4px;border-radius:6px;background:rgba(0,0,0,.06);color:inherit;font-weight:600;text-decoration:none}" +
    ".cr-falhou{font-size:11.5px;font-weight:700;color:#dc2626}" +
    ".cr-conv-pe{padding:7px 14px;background:var(--cv-painel);border-top:1px solid var(--cv-linha);font-size:12px;color:var(--cv-fraco)}" +
    ".cr-conv-aviso{align-self:center;margin:20px 0;padding:8px 12px;border-radius:8px;background:var(--cv-in);color:var(--cv-fraco);font-size:13px;text-align:center}" +
    ".cr-caixa{flex:1;max-width:1500px;display:flex;flex-direction:column;border-radius:14px;overflow:hidden;background:var(--fundo,#f4f4f2);box-shadow:0 20px 60px rgba(0,0,0,.4)}" +
    ".cr-faixa{display:flex;flex-wrap:wrap;gap:8px 14px;align-items:center;padding:8px 14px;background:#111827;color:#f9fafb}" +
    ".cr-titulo{font-weight:700;font-size:14px;letter-spacing:.02em;color:#e5e7eb;margin-right:auto}" +
    ".cr-nav{display:flex;gap:6px;align-items:center;font-weight:700;white-space:nowrap;color:#f9fafb}" +
    ".cr-nav button,.cr-acao{height:34px;padding:0 12px;border-radius:999px;border:1px solid var(--borda-forte,#cfcfca);background:var(--superficie,#fff);color:var(--texto,#16161a);font:inherit;font-size:13px;cursor:pointer}" +
    ".cr-faixa .cr-nav button,.cr-faixa .cr-acao{background:#1f2937;border-color:#374151;color:#f9fafb}" +
    ".cr-faixa .cr-fechar{color:#f9fafb}" +
    ".cr-nav button[disabled],.cr-acao[disabled]{opacity:.45;cursor:default}" +
    ".cr-quem{flex:1 1 320px;min-width:0}" +
    ".cr-quem b{font-size:15px}" +
    ".cr-quem .cr-sub{display:block;font-size:12.5px;color:var(--texto-fraco,#6f6f74);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}" +
    ".cr-fonte{display:inline-block;margin-right:6px;padding:1px 8px;border-radius:999px;font-size:11px;font-weight:700;letter-spacing:.04em;text-transform:uppercase;background:var(--roxo-suave,#f3edff);color:var(--roxo,#6d28d9)}" +
    ".cr-falta{font-size:12.5px;color:#b45309}" +
    ".cr-acoes{display:flex;gap:6px;flex-wrap:wrap;align-items:center}" +
    ".cr-aprovar{height:36px;padding:0 16px;border:0;border-radius:999px;background:#16a34a;color:#fff;font:inherit;font-weight:700;cursor:pointer}" +
    ".cr-aprovar[disabled]{opacity:.5;cursor:default}" +
    ".cr-fechar{width:36px;height:36px;border-radius:999px;border:0;background:transparent;color:var(--texto,#16161a);font-size:20px;cursor:pointer}" +
    ".cr-recado{width:100%;font-size:12.5px;color:#d1d5db}" +
    ".cr-recado:empty{display:none}" +
    ".cr-recado--ok{color:#86efac}.cr-recado--erro{color:#fca5a5}" +
    /* o card da origem */
    ".cr-origem{width:100%;display:flex;flex-wrap:wrap;gap:4px 14px;align-items:baseline;padding:8px 12px;border-radius:10px;border:1px solid var(--borda,#e2e2de);border-left:4px solid #2563eb;background:var(--superficie-2,#f7f7f5);font-size:13px}" +
    ".cr-origem b{font-size:11px;letter-spacing:.06em;text-transform:uppercase;color:#2563eb}" +
    ".cr-origem span{white-space:nowrap}" +
    ".cr-origem a{color:#2563eb;font-weight:600}" +
    ".cr-corpo{flex:1;min-height:0;position:relative;background:var(--fundo,#f4f4f2)}" +
    ".cr-corpo iframe{position:absolute;inset:0;width:100%;height:100%;border:0;background:transparent}" +
    /* é atualização de outro imóvel */
    ".cr-atu{position:absolute;inset:0;z-index:2;overflow:auto;padding:18px;background:var(--fundo,#f4f4f2)}" +
    ".cr-atu-caixa{max-width:1000px;margin:0 auto;padding:18px 20px;border-radius:14px;background:var(--superficie,#fff);border:1px solid var(--borda,#e2e2de)}" +
    ".cr-atu h3{margin:0 0 6px}" +
    ".cr-atu input[type=search],.cr-atu .cr-valor{width:100%;height:34px;padding:0 10px;border:1px solid var(--borda-forte,#cfcfca);border-radius:8px;font:inherit;background:var(--superficie,#fff);color:var(--texto,#16161a)}" +
    ".cr-atu textarea.cr-valor{height:80px;padding:6px 10px}" +
    ".cr-achados{list-style:none;margin:10px 0 0;padding:0;display:grid;gap:6px}" +
    ".cr-achados li{display:flex;gap:10px;align-items:center;padding:8px;border:1px solid var(--borda,#e2e2de);border-radius:10px}" +
    ".cr-achados img{width:56px;height:42px;object-fit:cover;border-radius:6px;background:var(--borda,#e2e2de)}" +
    ".cr-achados .cr-txt{flex:1;min-width:0;font-size:13px}" +
    ".cr-diff{width:100%;border-collapse:collapse;margin:12px 0;font-size:13px}" +
    ".cr-diff th,.cr-diff td{padding:6px 8px;border-bottom:1px solid var(--borda,#e2e2de);text-align:left;vertical-align:middle}" +
    ".cr-diff td.cr-hoje{color:var(--texto-fraco,#6f6f74);max-width:240px;overflow:hidden;text-overflow:ellipsis}" +
    ".cr-diff tr.cr-igual td{opacity:.55}";
  document.head.appendChild(css);

  /* ---- a aba: uma fila só ------------------------------------------------------ */
  painel.innerHTML =
    '<div class="cr-olx">' +
      "<b>Trazer da OLX</b> " +
      '<span class="cr-nota">Arraste o botão roxo para a barra de favoritos uma vez. Na página do anúncio da OLX, clique nele: ' +
      "o anúncio, as fotos e os dados entram aqui como pré-cadastro e o cadastro rápido abre nele.</span>" +
      '<form id="cr-olx-form">' +
        '<a class="cr-fav" id="cr-fav" href="#" title="Arraste para a barra de favoritos">Enviar para Imob Easy</a>' +
        '<input id="cr-olx-link" type="url" placeholder="ou cole aqui o link do anúncio da OLX e abra" aria-label="Link do anúncio da OLX">' +
        '<button class="cr-acao" type="submit">Abrir o anúncio</button>' +
      "</form>" +
      '<div class="cr-nota" id="cr-olx-recado" role="status"></div>' +
    "</div>" +
    '<div class="cr-topo">' +
      '<div class="cr-chips" id="cr-chips"></div>' +
      '<label class="cr-nota">Ordem <select id="cr-ordem" class="cr-chip" style="padding:0 8px">' +
        '<option value="antigos">Mais antigos primeiro</option><option value="novos">Mais novos primeiro</option>' +
      "</select></label>" +
      '<button class="cr-comecar" type="button" id="cr-comecar" disabled>Começar a curadoria</button>' +
      '<span class="cr-nota">Tudo o que espera alguém, numa fila só: passou até o fim, está tudo resolvido.</span>' +
    "</div>" +
    '<div class="cr-cats" id="cr-cats" aria-label="O que a IA supõe que é"></div>' +
    '<div class="tabela-envolucro"><div class="tabela-rolagem"><table class="tabela cr-lista">' +
      '<thead><tr><th scope="col">Imóvel</th><th scope="col">O que a IA supõe que é</th><th scope="col">De onde veio</th><th scope="col">Fotos</th><th scope="col">Cadastro</th><th scope="col">Por que está aqui</th><th scope="col"></th></tr></thead>' +
      '<tbody id="cr-corpo"><tr><td colspan="7">Carregando…</td></tr></tbody>' +
    "</table></div></div>";

  var itens = null;
  var fonte = "";
  var cat = null;      // a categoria escolhida na lista (null = todas)

  /* a ordem (Pedro, 09/10: "posso filtrar do mais antigo para o mais novo"): pela data em que chegou --
     a ficha pela última vez que o dono falou dela, o imóvel pelo cadastro */
  function dataDe(it) { var t = Date.parse(it.quando || ""); return isNaN(t) ? 0 : t; }
  function visiveis() {
    if (!itens) return [];
    var novos = ($("cr-ordem") || {}).value === "novos";
    // em ordem por categoria (o que a IA supõe que é); dentro dela, pela data
    return itens.filter(function (it) { return (!fonte || fonteDe(it) === fonte) && (cat === null || catDe(it) === cat); })
      .sort(function (a, b) {
        return (ordemDaCat(a) - ordemDaCat(b)) || (novos ? dataDe(b) - dataDe(a) : dataDe(a) - dataDe(b));
      });
  }

  function seloDeFoto(it) {
    if (it.fonte === "ficha") return '<span class="sub">as que ele mandou</span>';
    return semFoto(it) ? '<span class="cr-semfoto">SEM FOTO</span>'
      : '<span class="cr-comfoto">' + it.fotos + " foto" + (Number(it.fotos) === 1 ? "" : "s") + "</span>";
  }

  function pintar() {
    var base = itens || [];
    $("cr-chips").innerHTML = FONTES.map(function (f) {
      var n = base.filter(function (it) { return !f.k || fonteDe(it) === f.k; }).length;
      if (f.k && !n) return "";
      return '<button class="cr-chip" type="button" data-fonte="' + f.k + '" aria-pressed="' + (fonte === f.k) + '">' +
        esc(f.rotulo) + "<b>" + n + "</b></button>";
    }).join("");
    var daFonte = base.filter(function (it) { return !fonte || fonteDe(it) === fonte; });
    $("cr-cats").innerHTML = '<span class="cr-nota">O que a IA supõe que é:</span>' +
      '<button class="cr-chip" type="button" data-cat="*" aria-pressed="' + (cat === null) + '">Todas<b>' + daFonte.length + "</b></button>" +
      CATS.map(function (c) {
        var n = daFonte.filter(function (it) { return catDe(it) === c.k; }).length;
        if (!n) return "";
        return '<button class="cr-chip" type="button" data-cat="' + c.k + '" aria-pressed="' + (cat === c.k) + '">' +
          '<i style="background:' + c.cor + '"></i>' + esc(c.rotulo) + "<b>" + n + "</b></button>";
      }).join("");
    var lista = visiveis();
    $("cr-comecar").disabled = !lista.length;
    $("cr-comecar").textContent = lista.length ? "Começar a curadoria (" + lista.length + ")" : "Nada esperando: tudo resolvido";
    $("cr-corpo").innerHTML = lista.length ? lista.slice(0, 300).map(function (it, i) {
      var pct = it.pct == null ? null : Number(it.pct);
      return "<tr><td><b>" + esc(it.titulo) + "</b><br><span class=\"sub\">" +
          (it.codigo ? "#" + it.codigo + " · " : "sem cadastro · ") + esc([it.tipo, it.bairro, it.status].filter(Boolean).join(" · ")) +
          (it.dono ? " · dono: " + esc(it.dono) : "") + "</span></td>" +
        "<td>" + seloDaCat(it) + (it.palpite && it.palpite.porque ? '<div class="sub">' + esc(it.palpite.porque) + "</div>" : "") + "</td>" +
        '<td><span class="cr-fonte">' + esc(rotuloDaFonte(fonteDe(it))) + "</span>" +
          (it.quando ? '<div class="sub">' + esc(quando(it.quando)) + "</div>" : "") + "</td>" +
        "<td>" + seloDeFoto(it) + "</td>" +
        "<td>" + (pct == null ? '<span class="sub">—</span>' :
          '<span class="cr-barrinha"><i style="width:' + pct + "%;background:" + cor(pct) + '"></i></span><b style="color:' + cor(pct) + '">' + pct + "%</b>") +
          (it.falta && it.falta.length ? '<div class="sub">falta ' + esc(it.falta.slice(0, 3).join(", ")) + (it.falta.length > 3 ? " +" + (it.falta.length - 3) : "") + "</div>" : "") + "</td>" +
        '<td class="sub">' + esc(it.motivos.join(" · ")) + "</td>" +
        '<td><button class="cr-acao" type="button" data-abrir="' + i + '">Abrir</button></td></tr>';
    }).join("") : '<tr><td colspan="7">Nada esperando aqui — o cadastro está em dia.</td></tr>';
  }

  function carregar(depois) {
    return fetch("/admin/api/imoveis/cadastro-pendente", { credentials: "same-origin" })
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (d) { itens = d.itens || []; pintar(); if (depois) depois(); })
      .catch(function () {
        $("cr-corpo").innerHTML = '<tr><td colspan="7">Não foi possível carregar a fila (a senha do /admin é necessária).</td></tr>';
      });
  }

  aba.addEventListener("click", function () { if (!itens) carregar(); });
  $("cr-ordem").addEventListener("change", pintar);
  $("cr-chips").addEventListener("click", function (e) {
    var b = e.target.closest("[data-fonte]");
    if (b) { fonte = b.getAttribute("data-fonte"); pintar(); }
  });
  $("cr-cats").addEventListener("click", function (e) {
    var b = e.target.closest("[data-cat]");
    if (b) { var v = b.getAttribute("data-cat"); cat = v === "*" ? null : v; pintar(); }
  });
  $("cr-comecar").addEventListener("click", function () { abrir(visiveis(), 0); });
  $("cr-corpo").addEventListener("click", function (e) {
    var b = e.target.closest("[data-abrir]");
    if (b) abrir(visiveis(), Number(b.getAttribute("data-abrir")));
  });

  /* ---- o popup -------------------------------------------------------------- */
  var fila = [], pos = 0, veu = null, ocupado = false;
  var filaToda = [], catDoPopup = "*";    // a fila inteira e a categoria escolhida entre as setas ("*" = todas)
  var feitos = {};

  function chave(it) { return it.codigo ? "i" + it.codigo : "f" + it.fichaId; }

  function abrir(lista, inicio) {
    fila = lista.slice();
    if (!fila.length) return;
    filaToda = fila; catDoPopup = "*";
    pos = Math.max(0, Math.min(inicio || 0, fila.length - 1));
    if (!veu) {
      veu = document.createElement("div");
      veu.className = "cr-veu";
      veu.setAttribute("role", "dialog");
      veu.setAttribute("aria-label", "Cadastro rápido");
      veu.innerHTML =
        '<div class="cr-caixa">' +
          '<div class="cr-faixa">' +
            '<div class="cr-nav"><button type="button" data-ir="-1" aria-label="Anterior">◀</button>' +
              '<select id="cr-cat" aria-label="O que a IA supõe que é" title="O que a IA supõe que é: escolha a categoria para passar só por ela"></select>' +
              '<span id="cr-pos"></span><button type="button" data-ir="1" aria-label="Próximo">▶</button></div>' +
            '<span class="cr-titulo">Cadastro rápido</span>' +
            '<div class="cr-acoes">' +
              '<button class="cr-acao" type="button" id="cr-conversa" hidden>Ver conversa</button>' +
              '<button class="cr-acao" type="button" id="cr-condo">+ Condomínio</button>' +
              '<button class="cr-acao" type="button" id="cr-outro">É atualização de outro imóvel?</button>' +
              '<button class="cr-acao" type="button" id="cr-importar">Importar tudo</button>' +
              '<button class="cr-acao" type="button" id="cr-pular">Pular</button>' +
              '<button class="cr-aprovar" type="button" id="cr-aprovar">Aprovar: fica disponível para a Nay</button>' +
              '<button class="cr-fechar" type="button" id="cr-fechar" aria-label="Fechar">✕</button>' +
            "</div>" +
            '<div class="cr-recado" id="cr-recado" role="status"></div>' +
          "</div>" +
          '<div class="cr-corpo" id="cr-corpo-popup"></div>' +
        "</div>";
      document.body.appendChild(veu);
      veu.addEventListener("click", function (e) {
        var ir = e.target.closest("[data-ir]");
        if (ir) return mover(Number(ir.getAttribute("data-ir")));
        var id = e.target.id;
        if (id === "cr-pular") return mover(1);
        if (id === "cr-fechar") return fechar();
        if (id === "cr-aprovar") return aprovar();
        if (id === "cr-importar") return importar();
        if (id === "cr-outro") return abrirAtualizacao();
        if (id === "cr-condo") return abrirCondominio();
        if (id === "cr-conversa") return abrirConversa(fila[pos]);
        if (id === "cr-atu-voltar") return fecharAtualizacao();
        if (id === "cr-atu-aplicar") return aplicarAtualizacao();
        var esc_ = e.target.closest("[data-alvo]");
        if (esc_) return compararCom(Number(esc_.getAttribute("data-alvo")));
      });
      veu.addEventListener("input", function (e) {
        if (e.target.id === "cr-atu-busca") buscarAlvo(e.target.value);
      });
      veu.addEventListener("change", function (e) { if (e.target.id === "cr-cat") escolherCat(e.target.value); });
      document.addEventListener("keydown", function (e) {
        if (e.key !== "Escape" || !veu || veu.hidden) return;
        if (conv && !conv.hidden) { fecharConversa(); return; }     // o Esc fecha primeiro a conversa
        fechar();
      });
    }
    veu.hidden = false;
    document.body.style.overflow = "hidden";
    mostrar();
  }

  /* a categoria escolhida entre as setas: as setas passam só por ela (Pedro, 09/10) */
  function escolherCat(v) {
    var s = $("cr-cat");
    if (ocupado) { s.value = catDoPopup; return; }
    var atual = fila[pos];
    catDoPopup = v;
    fila = v === "*" ? filaToda : filaToda.filter(function (it) { return catDe(it) === (v === "-" ? "" : v); });
    if (!fila.length) { fila = filaToda; catDoPopup = "*"; }
    var i = fila.indexOf(atual);
    if (i >= 0) { pos = i; pintarFaixa(); atualizarCard(); return; }   // o mesmo imóvel continua aberto
    pos = 0;
    mostrar();
  }
  function pintarCats() {
    var s = $("cr-cat");
    if (!s) return;
    s.innerHTML = '<option value="*">Todas as categorias (' + filaToda.length + ")</option>" +
      CATS.map(function (c) {
        var n = filaToda.filter(function (it) { return catDe(it) === c.k; }).length;
        return n ? '<option value="' + (c.k || "-") + '">' + esc(c.rotulo) + " (" + n + ")</option>" : "";
      }).join("");
    s.value = catDoPopup;
    // a cor é a do imóvel aberto: dá para ver a categoria mesmo passando por "Todas"
    s.style.borderLeftColor = dadosDaCat(catDe(fila[pos])).cor;
  }

  function fechar() {
    if (!veu) return;
    fecharConversa();
    devolverCondominio();
    ocupado = false;          // o ✕ sempre solta o popup, mesmo com um salvamento no meio
    veu.hidden = true;
    document.body.style.overflow = "";
    $("cr-corpo-popup").innerHTML = "";
    carregar();
  }

  function mover(passo) {
    if (ocupado) return;
    var p = pos + passo;
    if (p < 0) return;
    if (p >= fila.length) { recado("Fim da fila. " + Object.keys(feitos).length + " resolvido(s) nesta rodada.", "ok"); return; }
    pos = p;
    mostrar();
  }

  function recado(texto, tipo) {
    var r = $("cr-recado");
    r.className = "cr-recado" + (tipo ? " cr-recado--" + tipo : "");
    r.textContent = texto || "";
  }

  function pintarFaixa() {
    var it = fila[pos];
    $("cr-pos").textContent = (pos + 1) + " de " + fila.length;
    pintarCats();
    pintarBotaoDaConversa();
    veu.querySelector('[data-ir="-1"]').disabled = pos === 0;
    veu.querySelector('[data-ir="1"]').disabled = pos >= fila.length - 1;
    $("cr-importar").hidden = !it.codigo;
    var feito = !!feitos[chave(it)];
    var a = $("cr-aprovar");
    a.disabled = feito;
    a.textContent = feito ? "Resolvido ✓"
      : !it.codigo ? "Cadastrar e aprovar"
      : it.status === "Disponível" ? "Salvar e próximo" : "Aprovar: fica disponível para a Nay";
  }

  function mostrar() {
    var it = fila[pos];
    recado("");
    pintarFaixa();
    pintarOrigem(it);
    if (!it.codigo && it.fichaId && it._prep === undefined) prepararFicha(it);
    // o que já sabemos e ainda não entrou (a ficha do dono num imóvel que existe, foto em link de fora): entra sozinho
    if (it.codigo && !it._importou && it.motivos.some(function (m) { return /ditou dados|link de fora/.test(m); })) {
      it._importou = true;
      setTimeout(importar, 50);
    }
    var corpo = $("cr-corpo-popup");
    var src = it.codigo ? "imovel-editar.html?codigo=" + encodeURIComponent(it.codigo) + "&rapido=1" : "imovel-novo.html?novo=1&rapido=1";
    corpo.innerHTML = '<iframe title="Cadastro do imóvel" src="' + src + '"></iframe>';
    var f = corpo.querySelector("iframe");
    f.addEventListener("load", function () { aoCarregarOEditor(f, it); });
  }

  /* ---- O CARD do cadastro: origem, motivo, fotos, falta e situação, num lugar só ----
     Fica DENTRO da página do imóvel, antes do cabeçalho dele (Pedro, 09/10: "põe tudo em um card antes das
     informações do imóvel, senão confunde com os menus de cima"). */
  function pintarOrigem(it) {
    if (it._origem !== undefined) { atualizarCard(); return; }
    it._origem = null;
    var q = it.codigo ? "codigo=" + encodeURIComponent(it.codigo) : "ficha=" + encodeURIComponent(it.fichaId);
    fetch("/admin/api/imoveis/origem?" + q, { credentials: "same-origin" })
      .then(function (r) { return r.ok ? r.json() : {}; })
      .then(function (o) { it._origem = o || {}; if (fila[pos] === it) { atualizarCard(); pintarBotaoDaConversa(); } })
      .catch(function () { it._origem = { erro: true }; if (fila[pos] === it) atualizarCard(); });
  }

  function prepararFicha(it) {
    it._prep = null;
    fetch("/admin/api/imoveis/da-ficha/" + encodeURIComponent(it.fichaId), { credentials: "same-origin" })
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (p) {
        it._prep = p || {};
        if (fila[pos] !== it) return;
        atualizarCard();
        var d = docDoEditor();
        if (d && d.getElementById("ed-form")) preencherComAFicha(d, it);
      })
      .catch(function () { it._prep = {}; });
  }

  var CSS_DO_CARD =
    "#cr-card{max-width:1180px;margin:16px auto 0;padding:14px 18px;border-radius:14px;background:var(--superficie,#fff);" +
      "border:1px solid var(--borda,#e2e2de);border-left:5px solid #2563eb;box-shadow:var(--sombra-1,none);font-size:13.5px;color:var(--texto,#16161a)}" +
    "#cr-card h2{margin:0 0 10px;font-size:15px;display:flex;flex-wrap:wrap;gap:8px;align-items:center}" +
    "#cr-card h2 small{font-size:12px;font-weight:600;color:var(--texto-fraco,#6f6f74)}" +
    "#cr-card dl{display:grid;grid-template-columns:150px 1fr;gap:7px 14px;margin:0}" +
    "#cr-card dt{font-size:11px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;color:var(--texto-fraco,#6f6f74);padding-top:2px}" +
    "#cr-card dd{margin:0;line-height:1.45}" +
    "#cr-card a{color:#2563eb;font-weight:600}" +
    "#cr-card .crc-fonte{display:inline-block;padding:1px 8px;border-radius:999px;font-size:11px;font-weight:700;letter-spacing:.04em;text-transform:uppercase;background:#dbeafe;color:#1d4ed8}" +
    "#cr-card .crc-sem{display:inline-block;padding:1px 8px;border-radius:999px;font-size:11.5px;font-weight:700;background:#fde8e8;color:#b42323}" +
    "#cr-card .crc-com{display:inline-block;padding:1px 8px;border-radius:999px;font-size:11.5px;font-weight:700;background:#e8f7f0;color:#2f7d58}" +
    "#cr-card .crc-falta{color:#b45309}" +
    "#cr-card .crc-fotos{display:grid;grid-template-columns:repeat(auto-fill,minmax(92px,1fr));gap:6px;margin-top:6px}" +
    "#cr-card .crc-fotos a{display:block;aspect-ratio:4/3;border-radius:8px;overflow:hidden;background:var(--borda,#e2e2de)}" +
    "#cr-card .crc-fotos img{width:100%;height:100%;object-fit:cover;display:block}" +
    "#cr-card .crc-ok{color:#15803d;font-weight:700}#cr-card .crc-aviso{color:#b45309;font-weight:700}" +
    "#cr-card .crc-cat{display:inline-block;padding:2px 10px;border-radius:999px;font-size:12px;font-weight:700;color:#fff;margin-right:6px}" +
    "#cr-card .crc-botao{height:28px;padding:0 12px;margin-left:6px;border-radius:999px;border:1px solid #1daa61;background:#1daa61;color:#fff;font:inherit;font-size:12.5px;font-weight:700;cursor:pointer}" +
    "@media (max-width:700px){#cr-card dl{grid-template-columns:1fr}}";

  function cardHtml(it) {
    var o = it._origem;
    var origem;
    if (o === null || o === undefined) origem = "buscando…";
    else if (o.erro) origem = "não consegui ler a origem";
    else {
      origem = [
        "<strong>" + esc(o.rotulo || rotuloDaFonte(fonteDe(it))) + "</strong>",
        o.linha && esc(o.linha),
        (o.nome || o.telefone) && esc([o.nome, fone(o.telefone)].filter(Boolean).join(" · ")),
        o.quando && "em " + esc(quando(o.quando)),
        o.link && '<a href="' + esc(o.link) + '" target="_blank" rel="noopener">ver o anúncio' + (o.titulo ? ": " + esc(String(o.titulo).slice(0, 70)) : "") + "</a>",
        o.detalhe && esc(o.detalhe)
      ].filter(Boolean).join(" · ");
    }
    var prep = it._prep;
    var fotosDele = prep && prep.fotos ? prep.fotos : [];
    var fotos = it.fonte === "ficha"
      ? (fotosDele.length
          ? '<span class="crc-com">' + fotosDele.length + " foto" + (fotosDele.length === 1 ? "" : "s") + "</span> que o dono mandou — entram no cadastro sozinhas" +
            '<div class="crc-fotos">' + fotosDele.map(function (u) {
              return '<a href="' + esc(u) + '" target="_blank" rel="noopener"><img src="' + esc(u) + '" alt="" loading="lazy"></a>';
            }).join("") + "</div>"
          : (prep === null || prep === undefined ? "buscando…" : '<span class="crc-sem">SEM FOTO</span> o dono não mandou foto'))
      : (semFoto(it) ? '<span class="crc-sem">SEM FOTO</span> este imóvel não tem nenhuma foto'
                     : '<span class="crc-com">' + it.fotos + " foto" + (Number(it.fotos) === 1 ? "" : "s") + "</span>");
    var pct = it.pct == null ? null : Number(it.pct);
    var situacao = [it.status || (it.codigo ? "" : "ainda sem cadastro"), it.dono && "dono: " + it.dono,
                    pct != null && '<b style="color:' + cor(pct) + '">' + pct + "% preenchido</b>"].filter(Boolean);
    return "<h2>Sobre este cadastro " + '<span class="crc-fonte">' + esc(rotuloDaFonte(fonteDe(it))) + "</span>" +
        "<small>" + (pos + 1) + " de " + fila.length + " na fila</small></h2>" +
      "<dl>" +
        "<dt>O que a IA supõe que é</dt><dd>" +
          '<span class="crc-cat" style="background:' + dadosDaCat(catDe(it)).cor + '">' + esc(dadosDaCat(catDe(it)).rotulo) + "</span>" +
          (it.palpite ? esc(it.palpite.porque || "") : "a análise roda de 5 em 5 minutos; este ainda não passou por ela") + "</dd>" +
        "<dt>De onde veio</dt><dd>" + origem +
          (temConversa(it) ? '<button class="crc-botao" type="button" data-cr-conversa="1">Ver conversa</button>' : "") + "</dd>" +
        "<dt>Por que está aqui</dt><dd>" + esc(it.motivos.join(" · ") || "—") + "</dd>" +
        (prep && prep.campos && prep.campos.condominio && !prep.condominio
          ? '<dt>Condomínio</dt><dd><span class="crc-aviso">“' + esc(prep.campos.condominio) + "” não bate com nenhum condomínio cadastrado.</span> " +
            "Se for um nome parecido, procure no campo Condomínio do imóvel; se não existe, use <b>+ Condomínio</b> na faixa de cima " +
            "(abre com o nome e o bairro, e entra escolhido no imóvel).</dd>"
          : "") +
        (prep && (prep.campos || prep.observacao) ? "<dt>Análise da IA</dt><dd>" +
          (prep.pronto === false ? '<span class="crc-aviso">Não parece pronto para anunciar.</span> ' : prep.pronto ? '<span class="crc-ok">Pronto para anunciar.</span> ' : "") +
          esc(prep.observacao || "") +
          (prep.duplicado_de ? " · parece o mesmo imóvel de outra ficha deste dono (ficha " + esc(prep.duplicado_de) + "): veja com “É atualização de outro imóvel?”" : "") +
          (prep.campos ? '<div class="cr-nota">Os campos abaixo já vêm preenchidos com o que ele contou. Confira e aprove.</div>' : "") +
          "</dd>" : "") +
        "<dt>Fotos</dt><dd>" + fotos + "</dd>" +
        (it.falta && it.falta.length ? '<dt>Falta preencher</dt><dd class="crc-falta">' + esc(it.falta.join(", ")) + "</dd>" : "") +
        "<dt>Situação</dt><dd>" + (situacao.length ? situacao.map(function (x) { return x.charAt(0) === "<" ? x : esc(x); }).join(" · ") : "—") + "</dd>" +
      "</dl>";
  }

  function atualizarCard() {
    var d = docDoEditor();
    var c = d && d.getElementById("cr-card");
    if (c) c.innerHTML = cardHtml(fila[pos]);
  }

  function injetarCard(d, it) {
    if (!d.getElementById("cr-card-css")) {
      var s = d.createElement("style");
      s.id = "cr-card-css";
      s.textContent = CSS_DO_CARD;
      d.head.appendChild(s);
    }
    var c = d.getElementById("cr-card");
    if (!c) {
      c = d.createElement("section");
      c.id = "cr-card";
      c.setAttribute("aria-label", "Sobre este cadastro");
      var topo = d.querySelector(".nv__topo") || d.querySelector("main") || d.body.firstChild;
      topo.parentNode.insertBefore(c, topo);
    }
    c.innerHTML = cardHtml(it);
    c.style.borderLeftColor = dadosDaCat(catDe(it)).cor;
    // o card mora dentro da página do imóvel (iframe): o clique sobe para cá
    c.onclick = function (e) { if (e.target.closest("[data-cr-conversa]")) abrirConversa(fila[pos]); };
  }

  /* ---- VER CONVERSA (Pedro, 09/10: "esses imóveis que vêm de conversa eu quero ver a conversa, pega o mockup de
     conversa lá do CRM, em um popup") -------------------------------------------------------------------------
     A conversa vem do CRM pela API do site (/admin/api/imoveis/conversa): as linhas em que a pessoa falou (oficial,
     captação), o que a Nay e a equipe escreveram, fotos e áudios. Só leitura: para responder é no CRM. */
  var conv = null;
  function temConversa(it) {
    if (!it) return false;
    if (it.fonte === "ficha") return true;
    return !!(it._origem && it._origem.telefone);
  }
  function pintarBotaoDaConversa() {
    var b = $("cr-conversa");
    if (b) b.hidden = !temConversa(fila[pos]);
  }
  function fecharConversa() {
    if (!conv || conv.hidden) return;
    conv.hidden = true;
    conv.querySelector(".cr-conv-corpo").innerHTML = "";      // para o áudio que estiver tocando
  }
  function horaDe(iso) {
    var d = new Date(iso);
    return isNaN(d) ? "" : d.toLocaleTimeString("pt-BR", { timeZone: "America/Manaus", hour: "2-digit", minute: "2-digit" });
  }
  function diaDe(iso) {
    var d = new Date(iso);
    return isNaN(d) ? "" : d.toLocaleDateString("pt-BR", { timeZone: "America/Manaus", weekday: "short", day: "2-digit", month: "2-digit", year: "numeric" });
  }
  function midiaHtml(m) {
    var x = m.midia;
    if (!x || !x.url) return "";
    var u = esc(x.url);
    if (x.tipo === "image") {
      // a miniatura do armazém do CRM (?w=) -- a foto cheia abre no clique
      var mini = /\/api\/midia\//.test(x.url) ? u + (x.url.indexOf("?") >= 0 ? "&amp;" : "?") + "w=480" : u;
      return '<a href="' + u + '" target="_blank" rel="noopener"><img src="' + mini + '" alt="foto" loading="lazy"></a>';
    }
    if (x.tipo === "audio") return '<audio controls preload="none" src="' + u + '"></audio>';
    if (x.tipo === "video") return '<video controls preload="metadata" src="' + u + '"></video>';
    return '<a class="cr-doc" href="' + u + '" target="_blank" rel="noopener">📄 ' + esc(x.nome || "documento") + "</a>";
  }
  function pintarConversa(i) {
    var d = conv._dados || {};
    var lista = d.conversas || [];
    var c = lista[i];
    var nome = d.nome || (c && c.nome) || "Contato";
    conv.querySelector(".cr-conv-foto").textContent = String(nome).trim().charAt(0).toUpperCase() || "?";
    conv.querySelector(".cr-conv-quem b").textContent = nome;
    conv.querySelector(".cr-conv-quem span").textContent = [fone(d.telefone || (c && c.telefone)), c && c.rotulo].filter(Boolean).join(" · ");
    var abas = conv.querySelector(".cr-conv-abas");
    abas.hidden = lista.length < 2;
    abas.innerHTML = lista.map(function (x, n) {
      return '<button type="button" data-conv-aba="' + n + '" aria-pressed="' + (n === i) + '">' + esc(x.rotulo || x.linha) + " (" + x.mensagens.length + ")</button>";
    }).join("");
    var corpo = conv.querySelector(".cr-conv-corpo");
    if (!c || !c.mensagens.length) {
      corpo.innerHTML = '<div class="cr-conv-aviso">' + esc(d.aviso || "Não achei mensagens desta pessoa.") + "</div>";
      conv.querySelector(".cr-conv-pe").textContent = "";
      return;
    }
    var dia = "", antes = null;
    corpo.innerHTML = (d.aviso ? '<div class="cr-conv-aviso">' + esc(d.aviso) + "</div>" : "") + c.mensagens.map(function (m) {
      var h = "";
      var hoje = diaDe(m.quando);
      if (hoje !== dia) { dia = hoje; antes = null; h += '<div class="cr-dia">' + esc(hoje) + "</div>"; }
      var lado = m.saida ? "out" : "in";
      var quem = m.saida ? m.autor : "";
      var novo = antes !== lado + "|" + quem;        // muda quem fala: o balão ganha o rabinho e o nome
      antes = lado + "|" + quem;
      var texto = m.texto || "";
      if (m.midia && /^\[[^\]]{2,20}\]$/.test(texto.trim())) texto = "";      // "[imagem]": a foto já diz
      h += '<div class="cr-msg cr-msg--' + lado + (novo ? " cr-msg--novo" : "") + '"><div class="cr-balao">' +
        (m.saida && novo ? '<span class="cr-autor' + (m.deGente ? " cr-autor--gente" : /^Nay/.test(quem) ? "" : " cr-autor--num") + '">' + esc(quem) + "</span>" : "") +
        (m.citado ? '<div class="cr-citado">' + esc(m.citado) + "</div>" : "") +
        midiaHtml(m) + esc(texto) +
        (m.transcricao ? '<div class="cr-transc">“' + esc(m.transcricao) + "”</div>" : "") +
        (m.falhou ? ' <span class="cr-falhou">não foi entregue</span>' : "") +
        '<span class="cr-hora">' + esc(horaDe(m.quando)) + "</span></div></div>";
      return h;
    }).join("");
    conv._noFim = true;
    conv.querySelector(".cr-conv-pe").textContent = c.mensagens.length + " mensagens · só leitura (para responder, abra a conversa no CRM)";
    corpo.scrollTop = corpo.scrollHeight;
  }
  function abrirConversa(it) {
    if (!it) return;
    if (!conv) {
      conv = document.createElement("div");
      conv.className = "cr-conv-veu";
      conv.setAttribute("role", "dialog");
      conv.setAttribute("aria-label", "Conversa");
      conv.innerHTML =
        '<div class="cr-conv">' +
          '<div class="cr-conv-topo"><div class="cr-conv-foto"></div><div class="cr-conv-quem"><b></b><span></span></div>' +
            '<button class="cr-conv-x" type="button" data-conv-fechar="1" aria-label="Fechar a conversa">✕</button></div>' +
          '<div class="cr-conv-abas" hidden></div>' +
          '<div class="cr-conv-corpo"></div>' +
          '<div class="cr-conv-pe"></div>' +
        "</div>";
      document.body.appendChild(conv);
      // a foto chega depois do texto e empurra a conversa: enquanto a pessoa não rolou, ela fica na última mensagem
      var rolo = conv.querySelector(".cr-conv-corpo");
      rolo.addEventListener("load", function () { if (conv._noFim) rolo.scrollTop = rolo.scrollHeight; }, true);
      rolo.addEventListener("wheel", function () { conv._noFim = false; }, { passive: true });
      rolo.addEventListener("touchmove", function () { conv._noFim = false; }, { passive: true });
      conv.addEventListener("click", function (e) {
        if (e.target === conv || e.target.closest("[data-conv-fechar]")) return fecharConversa();
        var a = e.target.closest("[data-conv-aba]");
        if (a) pintarConversa(Number(a.getAttribute("data-conv-aba")));
      });
    }
    conv._dados = { nome: it.dono || (it._origem && it._origem.nome), telefone: it._origem && it._origem.telefone, conversas: [] };
    conv.hidden = false;
    pintarConversa(0);
    conv.querySelector(".cr-conv-corpo").innerHTML = '<div class="cr-conv-aviso">Buscando a conversa…</div>';
    var q = it.codigo ? "codigo=" + encodeURIComponent(it.codigo) : "ficha=" + encodeURIComponent(it.fichaId);
    fetch("/admin/api/imoveis/conversa?" + q, { credentials: "same-origin" })
      .then(function (r) { return r.json().then(function (j) { return { ok: r.ok, j: j }; }); })
      .then(function (x) {
        if (!conv || conv.hidden) return;
        if (!x.ok) { conv._dados.aviso = (x.j && (x.j.erro || x.j.error)) || "Não consegui buscar a conversa."; pintarConversa(0); return; }
        conv._dados = x.j || {};
        pintarConversa(0);
      })
      .catch(function () { if (conv && !conv.hidden) { conv._dados.aviso = "Não consegui buscar a conversa."; pintarConversa(0); } });
  }

  /* ---- o editor dentro do popup ---------------------------------------------- */
  function docDoEditor() {
    var f = $("cr-corpo-popup").querySelector("iframe");
    try { return f && f.contentDocument; } catch (e) { return null; }
  }

  function aoCarregarOEditor(f, it) {
    var d;
    try { d = f.contentDocument; } catch (e) { return; }
    if (!d) return;
    if (!d.getElementById("cr-sem-menu")) {
      var s = d.createElement("style");
      s.id = "cr-sem-menu";
      s.textContent = ".barra-topo,.nav-principal,.rodape-sistema,.pular-conteudo,.nv__voltar,[data-layout-topo],[data-layout-rodape]{display:none!important}" +
        "body::before{display:none!important}";
      d.head.appendChild(s);
    }
    injetarCard(d, it);
    var aqui = new URLSearchParams(f.contentWindow.location.search);
    var novoCodigo = aqui.get("codigo");
    // a ficha acabou de virar imóvel: as fotos que ele mandou e o dono vão junto
    if (!it.codigo && novoCodigo && it.fichaId) {
      it.codigo = Number(novoCodigo);
      juntar({ de_ficha: it.fichaId, em: it.codigo, fotos: true }).then(function (r) {
        it.fonte = "imovel"; it.status = "Rascunho"; it.fotos = r.fotos || 0;
        var feitoAqui = "Cadastrado como #" + it.codigo + (r.fotos ? ", com " + r.fotos + " foto(s) que o dono mandou" : "") + (r.dono ? " e o dono ligado" : "");
        if (!it._aprovarAoCriar) {
          pintarFaixa();
          recado(feitoAqui + ". Confira e aprove.", "ok");
          f.contentWindow.location.reload();
          return;
        }
        return put(it.codigo, { status: "Disponível" }).then(function () {
          it.status = "Disponível";
          feitos[chave(it)] = true;
          var texto = feitoAqui + " e aprovado: Disponível, no site e na Nay.";
          if (pos < fila.length - 1) { mover(1); recado(texto + " Próximo:", "ok"); }
          else { pintarFaixa(); f.contentWindow.location.reload(); recado(texto + " Fim da fila.", "ok"); }
        });
      }).catch(function (e) { recado("O imóvel foi cadastrado (#" + it.codigo + "), mas faltou um passo: " + e.message, "erro"); });
      return;
    }
    // a análise da IA ainda vindo: quem preenche é ela, quando chegar (prepararFicha)
    if (!it.codigo && it.fonte === "ficha" && it._prep !== null) preencherComAFicha(d, it);
  }

  /* a ficha da conversa vira os campos da tela de cadastro */
  var NUMEROS = { um: 1, uma: 1, dois: 2, duas: 2, tres: 3, quatro: 4, cinco: 5, seis: 6, sete: 7, oito: 8, nove: 9, dez: 10 };
  function numeroDe(t) {
    var s = semAcento(t);
    var m = s.match(/\d+(?:[.,]\d+)?/);
    if (m) return Number(m[0].replace(",", "."));
    var w = s.split(/[^a-z]+/).filter(function (x) { return NUMEROS[x]; });
    return w.length ? NUMEROS[w[0]] : null;
  }
  function dinheiroDe(t) {
    var s = semAcento(t);
    var m = s.match(/\d[\d.]*(?:,\d+)?/);
    if (!m) return null;
    var n = Number(m[0].replace(/\./g, "").replace(",", "."));
    if (/milh/.test(s)) n *= 1e6; else if (/\bmil\b/.test(s)) n *= 1000;
    return n || null;
  }
  function brl(n) { return n == null ? "" : Math.round(n).toLocaleString("pt-BR"); }
  function camposDaFicha(dados) {
    var d = dados || {};
    var negocio = semAcento(d.negocio);
    var venda = /vend|ambos|os dois/.test(negocio), aluga = !/vend/.test(negocio) || /ambos|os dois/.test(negocio);
    var tipo = String(d.tipo || "").trim();
    return {
      tipo: tipo ? tipo.charAt(0).toUpperCase() + tipo.slice(1) : null,
      bairro: d.bairro || null,
      quartos: numeroDe(d.quartos), suites: numeroDe(d.suites), banheiros: numeroDe(d.banheiros), vagas: numeroDe(d.vagas),
      area_util: numeroDe(d.area),
      valor_venda: venda ? dinheiroDe(d.valor) : null,
      valor_aluguel: aluga ? dinheiroDe(d.valor) : null,
      taxa_condominio: dinheiroDe(d.condominio_valor), iptu: dinheiroDe(d.iptu),
      mobilia: d.mobilia || null,
      descricao: d.detalhes ? "O dono contou na conversa: " + d.detalhes : null,
      _condominio: d.condominio || null
    };
  }
  var DINHEIRO = { valor_venda: 1, valor_aluguel: 1, taxa_condominio: 1, iptu: 1 };
  var DA_IA = ["tipo", "bairro", "logradouro", "numero", "complemento", "andar", "quartos", "suites", "banheiros", "vagas",
               "area_util", "area_total", "valor_aluguel", "valor_venda", "taxa_condominio", "iptu", "mobilia", "descricao"];
  function camposPreparados(it) {
    var c = it._prep && it._prep.campos;
    if (!c) return camposDaFicha(it.dados);
    var v = {};
    DA_IA.forEach(function (k) { v[k] = c[k]; });
    v._condominio = (it._prep.condominio && it._prep.condominio.nome) || c.condominio || null;
    v._caracteristicas = c.caracteristicas || [];
    return v;
  }
  function preencherComAFicha(d, it) {
    if (d._crPreenchido === (it._prep ? "ia" : "simples")) return;
    d._crPreenchido = it._prep ? "ia" : "simples";
    var v = camposPreparados(it);
    var dono = it._prep && it._prep.dono;
    var tentativas = 0;
    (function esperar() {
      if (!d.querySelector('[data-campo="quartos"]')) { if (++tentativas < 40) setTimeout(esperar, 250); return; }
      Object.keys(v).forEach(function (k) {
        if (k.charAt(0) === "_" || v[k] == null || v[k] === "") return;
        var el = d.querySelector('[data-campo="' + k + '"]');
        if (!el || String(el.value || "").trim()) return;      // só campo vazio
        el.value = DINHEIRO[k] ? brl(v[k]) : String(v[k]);
        el.dispatchEvent(new Event("input", { bubbles: true }));
        el.dispatchEvent(new Event("change", { bubbles: true }));
      });
      // o dono da conversa (sem ele a tela pergunta "falta o proprietário" ao cadastrar)
      if (dono) {
        [["o:nome", dono.nome], ["o:telefone", dono.telefone], ["o:tratamento", dono.tratamento]].forEach(function (par) {
          var el = d.querySelector('[data-campo="' + par[0] + '"]');
          if (!el || !par[1] || String(el.value || "").trim()) return;
          el.value = par[1];
          el.dispatchEvent(new Event("input", { bubbles: true }));
          el.dispatchEvent(new Event("change", { bubbles: true }));
        });
      }
      // o que o imóvel tem, como etiquetas
      var mais = d.querySelector('[data-acrescentar-grupo="imovel"]');
      (v._caracteristicas || []).forEach(function (x) {
        if (!mais || !x) return;
        mais.value = x;
        mais.dispatchEvent(new Event("change", { bubbles: true }));
      });
      // o condomínio: digita e escolhe na lista sozinho quando o nome bate
      var c = d.getElementById("ed-condominio");
      if (c && v._condominio && !c.value) escolherCondominioNoEditor(d, v._condominio);
      recado(it._prep && it._prep.campos
        ? "A IA já pôs o que o dono contou nos campos" + (it._prep.fotos && it._prep.fotos.length ? " e as " + it._prep.fotos.length + " fotos entram ao cadastrar" : "") + ". Confira e clique em Cadastrar e aprovar."
        : "Campos preenchidos com o que o dono contou. Confira e clique em Cadastrar e aprovar.", "ok");
    })();
  }

  function json(r) {
    return r.json().catch(function () { return {}; }).then(function (d) {
      if (!r.ok) throw new Error((d.detalhes && [].concat(d.detalhes).join("; ")) || d.detalhe || d.erro || ("HTTP " + r.status));
      return d;
    });
  }
  function juntar(corpo) {
    return fetch("/admin/api/imoveis/juntar", {
      method: "POST", credentials: "same-origin", headers: { "Content-Type": "application/json" }, body: JSON.stringify(corpo)
    }).then(json);
  }
  function put(codigo, corpo) {
    return fetch("/admin/api/imoveis/" + encodeURIComponent(codigo), {
      method: "PUT", credentials: "same-origin", headers: { "Content-Type": "application/json" }, body: JSON.stringify(corpo)
    }).then(json);
  }

  function importar() {
    var it = fila[pos];
    if (ocupado || !it || !it.codigo) return;
    ocupado = true;
    recado("Importando o que já sabemos (só em campo vazio)…");
    fetch("/admin/api/imoveis/" + it.codigo + "/importar", { method: "POST", credentials: "same-origin" })
      .then(json)
      .then(function (d) {
        ocupado = false;
        var partes = [];
        if (d.fotosImportadas) { partes.push(d.fotosImportadas + " foto(s) trazida(s)"); it.fotos = Number(it.fotos || 0) + d.fotosImportadas; }
        if ((d.entraram || []).length) partes.push("entrou: " + d.entraram.join(", "));
        if (d.pct_antes !== d.pct_depois) { partes.push(d.pct_antes + "% → " + d.pct_depois + "%"); it.pct = d.pct_depois; }
        mostrar();
        recado(partes.length ? partes.join(" · ") : "Não havia nada para puxar: o resto é digitar no editor.", "ok");
      })
      .catch(function (e) { ocupado = false; recado("Não importei: " + e.message, "erro"); });
  }

  /* Salva o que estiver digitado no editor (o botão dele) e espera a resposta */
  function salvarOEditor() {
    var d = docDoEditor();
    var botao = d && d.getElementById("ed-salvar");
    if (!botao || botao.disabled) return Promise.resolve(false);
    var status = d.getElementById("ed-status-salvar");
    var antes = status ? status.textContent : "";
    botao.click();
    return new Promise(function (ok, falha) {
      var n = 0;
      var t = setInterval(function () {
        n++;
        var c = status ? status.className : "";
        if (c.indexOf("--ok") >= 0 && status.textContent !== antes) { clearInterval(t); ok(true); }
        else if (c.indexOf("--erro") >= 0) { clearInterval(t); falha(new Error(status.textContent)); }
        else if (n > 80) { clearInterval(t); falha(new Error("o editor não respondeu ao salvar")); }
      }, 250);
    });
  }

  function aprovar() {
    var it = fila[pos];
    if (ocupado || !it) return;
    if (!it.codigo) {      // ficha: cadastra pela tela de cadastro; ao abrir o imóvel novo, junta as fotos e aprova
      var d = docDoEditor();
      var b = d && d.getElementById("ed-salvar");
      if (!b) { recado("A tela de cadastro ainda está carregando.", "erro"); return; }
      it._aprovarAoCriar = true;
      recado("Cadastrando…");
      b.click();
      return;
    }
    ocupado = true;
    $("cr-aprovar").disabled = true;
    recado("Salvando…");
    salvarOEditor()
      .then(function () { return it.status === "Disponível" ? { jaEstava: true } : put(it.codigo, { status: "Disponível" }); })
      .then(function (d) {
        ocupado = false;
        feitos[chave(it)] = true;
        it.status = "Disponível";
        var texto = d && d.jaEstava ? "#" + it.codigo + " salvo." : "#" + it.codigo + " aprovado: Disponível, no site e na Nay" +
          (semFoto(it) ? " (sem foto: a Nay manda só o card)" : "") + ".";
        if (pos < fila.length - 1) { mover(1); recado(texto + " Próximo:", "ok"); }
        else { pintarFaixa(); recado(texto + " Fim da fila.", "ok"); }
      })
      .catch(function (e) {
        ocupado = false;
        $("cr-aprovar").disabled = false;
        recado("Não aprovei: " + e.message, "erro");
      });
  }

  /* ---- + CONDOMÍNIO: o formulário da aba "Adicionar condomínio", emprestado ----------------
     (Pedro, 09/10: "coloca para eu poder cadastrar condomínio por aí também"). O DOM do painel muda de lugar e volta:
     é o mesmo formulário, com a mesma regra (nome sem repetir, endereço fixo). Ao gravar, o condomínio entra
     escolhido no cadastro do imóvel aberto, e o endereço vem dele. */
  var condoEmprestado = null;
  function devolverCondominio() {
    if (!condoEmprestado) return;
    var e = condoEmprestado; condoEmprestado = null;
    e.painel.hidden = e.estavaEscondido;
    if (e.proximo && e.proximo.parentNode === e.pai) e.pai.insertBefore(e.painel, e.proximo); else e.pai.appendChild(e.painel);
  }
  function inicioDoCondominio(it) {
    var c = it._prep && it._prep.campos;
    if (c) {
      return { nome: c.condominio, bairro: c.bairro, logradouro: c.logradouro, numero: c.numero,
               tipo: /casa|lote|sobrado|terreno|ch[aá]cara/i.test(c.tipo || "") ? "casas_lotes" : "apartamentos" };
    }
    return { nome: it.condominio && !/^im[oó]vel novo$/i.test(it.condominio) ? it.condominio : "", bairro: it.bairro };
  }
  function abrirCondominio() {
    var cc = document.querySelector('[data-painel="condominio-novo"]');
    if (!cc || !window.condominioNovoCom) { recado("O cadastro de condomínio não carregou nesta página: recarregue.", "erro"); return; }
    painelAtu("<h3>Cadastrar condomínio</h3>" +
      '<p class="cr-nota">O condomínio é cadastrado uma vez, com o endereço fixo. Ao gravar, ele já entra escolhido no imóvel que está aberto. ' +
      "Se ele já existe, a busca de cima abre o que existe.</p>" +
      '<div id="cr-cc-lugar"></div>' +
      '<p style="margin-top:12px"><button class="cr-acao" type="button" id="cr-atu-voltar">Voltar ao cadastro do imóvel</button></p>');
    window.condominioNovoCom(inicioDoCondominio(fila[pos]));
    condoEmprestado = { painel: cc, pai: cc.parentNode, proximo: cc.nextSibling, estavaEscondido: cc.hidden };
    $("cr-cc-lugar").appendChild(cc);
    cc.hidden = false;
  }
  /* escolhe o condomínio no campo do cadastro aberto, pelo nome (a lista do campo é a do servidor) */
  function escolherCondominioNoEditor(d, nome, depois) {
    var c = d && d.getElementById("ed-condominio");
    if (!c || !nome) return;
    c.value = nome;
    c.dispatchEvent(new Event("input", { bubbles: true }));
    var alvo = semAcento(nome).trim(), n = 0;
    (function escolher() {
      var itens = d.querySelectorAll(".sel-condo__item");
      var certo = Array.prototype.filter.call(itens, function (x) {
        var t = semAcento((x.firstChild && x.firstChild.textContent) || x.textContent).trim();
        return t === alvo || t.indexOf(alvo) === 0;
      })[0];
      if (certo) { certo.dispatchEvent(new MouseEvent("mousedown", { bubbles: true, cancelable: true })); if (depois) depois(true); return; }
      if (++n < 16) setTimeout(escolher, 250); else if (depois) depois(false);
    })();
  }
  window.addEventListener("condominio-salvo", function (e) {
    if (!veu || veu.hidden || !condoEmprestado) return;
    var nome = e.detail && e.detail.nome;
    var f = $("cr-corpo-popup").querySelector("iframe");
    var w = null, d = null;
    try { w = f && f.contentWindow; d = f && f.contentDocument; } catch (x) { w = null; }
    if (w && w.recarregarCondominios) w.recarregarCondominios();
    var it = fila[pos];
    if (it._prep && it._prep.campos && !it._prep.condominio) it._prep.condominio = { id: e.detail.id, nome: nome };
    setTimeout(function () {
      fecharAtualizacao();
      escolherCondominioNoEditor(d, nome, function (ok) {
        recado(ok ? "Condomínio “" + nome + "” " + (e.detail.criado ? "cadastrado" : "salvo") + " e escolhido no imóvel; o endereço vem dele."
                  : "Condomínio “" + nome + "” gravado. Escolha ele no campo Condomínio do imóvel.", "ok");
      });
      atualizarCard();
    }, 600);
  });

  /* ---- É ATUALIZAÇÃO DE OUTRO IMÓVEL ------------------------------------------ */
  var CAMPOS = [
    ["tipo", "Tipo"], ["bairro", "Bairro"], ["logradouro", "Rua / avenida"], ["numero", "Número"], ["complemento", "Complemento"],
    ["quartos", "Quartos", "int"], ["suites", "Suítes", "int"], ["banheiros", "Banheiros", "int"], ["vagas", "Vagas", "int"],
    ["area_util", "Área construída (m²)", "num"], ["area_total", "Área total (m²)", "num"],
    ["valor_aluguel", "Aluguel (R$)", "din"], ["valor_venda", "Venda (R$)", "din"],
    ["taxa_condominio", "Condomínio (R$)", "din"], ["iptu", "IPTU (R$)", "din"],
    ["mobilia", "Mobília"], ["descricao", "Descrição", "longo"]
  ];
  var atu = { origem: null, alvo: null, espera: null };

  function painelAtu(html) {
    devolverCondominio();
    var corpo = $("cr-corpo-popup");
    var p = corpo.querySelector(".cr-atu");
    if (!p) { p = document.createElement("div"); p.className = "cr-atu"; corpo.appendChild(p); }
    p.innerHTML = '<div class="cr-atu-caixa">' + html + "</div>";
    return p;
  }
  function fecharAtualizacao() {
    devolverCondominio();
    var p = $("cr-corpo-popup").querySelector(".cr-atu");
    if (p) p.remove();
  }

  function valoresDesteItem(it) {
    if (!it.codigo) return Promise.resolve(camposDaFicha(it.dados));
    return fetch(API + "/api/imoveis/" + encodeURIComponent(it.codigo)).then(function (r) { return r.ok ? r.json() : {}; })
      .then(function (x) { return x.imovel || x; });
  }

  function abrirAtualizacao() {
    var it = fila[pos];
    atu = { origem: null, alvo: null, espera: null };
    painelAtu(
      "<h3>Na verdade é atualização de outro imóvel?</h3>" +
      '<p class="cr-nota">Pesquise o imóvel que já está cadastrado (código, condomínio, bairro ou rua). Em seguida aparece o que mudou, ' +
      "campo a campo, para você conferir e editar antes de aplicar. Este " + (it.codigo ? "cadastro (#" + it.codigo + ") vira Excluído" : "ficha da conversa fica ligada a ele") +
      ", e as fotos e o dono vão para o imóvel certo.</p>" +
      '<input type="search" id="cr-atu-busca" placeholder="Ex.: 3050, Parque dos Ingleses, Ponta Negra…" autocomplete="off">' +
      '<ul class="cr-achados" id="cr-atu-achados"></ul>' +
      '<p style="margin-top:14px"><button class="cr-acao" type="button" id="cr-atu-voltar">Voltar ao cadastro</button></p>');
    var b = $("cr-atu-busca");
    var sugestao = it.dados && it.dados.condominio || it.condominio || it.titulo;
    if (sugestao && !/^im[oó]vel novo$/i.test(sugestao)) { b.value = sugestao; buscarAlvo(sugestao); }
    b.focus();
  }

  function buscarAlvo(q) {
    clearTimeout(atu.espera);
    var it = fila[pos];
    atu.espera = setTimeout(function () {
      q = String(q || "").trim();
      var ul = $("cr-atu-achados");
      if (!ul) return;
      if (q.length < 2) { ul.innerHTML = ""; return; }
      ul.innerHTML = '<li class="cr-nota">Procurando…</li>';
      fetch(API + "/api/imoveis-lista?per=10&status=" + encodeURIComponent("Disponível,Alugado,Vendido,Rascunho,Em revisão,Indisponível,Arquivado,Removido") +
            "&q=" + encodeURIComponent(q))
        .then(function (r) { return r.ok ? r.json() : { itens: [] }; })
        .then(function (d) {
          var lista = (d.itens || []).filter(function (x) { return String(x.codigo) !== String(it.codigo || ""); });
          ul.innerHTML = lista.length ? lista.map(function (x) {
            return "<li>" + (x.capa ? '<img src="' + esc(x.capa) + '" alt="">' : "<img alt=\"\">") +
              '<div class="cr-txt"><b>#' + esc(x.codigo) + " · " + esc(x.condominio || x.tipo || "") + "</b><br>" +
              '<span class="cr-nota">' + esc([x.status, x.tipo, x.bairro, x.endereco, x.valor, x.fotos + " foto(s)", x.proprietario && "dono: " + x.proprietario]
                .filter(Boolean).join(" · ")) + "</span></div>" +
              '<button class="cr-acao" type="button" data-alvo="' + esc(x.codigo) + '">É este</button></li>';
          }).join("") : '<li class="cr-nota">Nada encontrado com isso.</li>';
        })
        .catch(function () { ul.innerHTML = '<li class="cr-nota">A busca falhou; tente de novo.</li>'; });
    }, 300);
  }

  function texto(v) { return v == null ? "" : String(v); }
  function mostrarValor(v, tipo) {
    if (v == null || v === "") return "—";
    if (tipo === "din") return "R$ " + brl(Number(v));
    return texto(v);
  }
  function iguais(a, b, tipo) {
    if ((a == null || a === "") && (b == null || b === "")) return true;
    if (tipo === "int" || tipo === "num" || tipo === "din") return Number(a) === Number(b);
    return semAcento(texto(a)).trim() === semAcento(texto(b)).trim();
  }

  function compararCom(alvo) {
    var it = fila[pos];
    painelAtu('<p class="cr-nota">Comparando com o #' + alvo + "…</p>");
    Promise.all([valoresDesteItem(it), fetch(API + "/api/imoveis/" + alvo).then(function (r) { return r.ok ? r.json() : {}; })])
      .then(function (r) {
        var deste = r[0] || {}, dele = r[1].imovel || r[1] || {};
        atu.alvo = alvo;
        var linhas = CAMPOS.map(function (c) {
          var k = c[0], tipo = c[2], novo = deste[k], hoje = dele[k];
          if (novo == null || novo === "") return "";
          var igual = iguais(novo, hoje, tipo);
          var valor = tipo === "din" ? brl(Number(novo)) : texto(novo);
          var campo = tipo === "longo"
            ? '<textarea class="cr-valor" data-k="' + k + '" data-t="' + (tipo || "") + '">' + esc(valor) + "</textarea>"
            : '<input class="cr-valor" data-k="' + k + '" data-t="' + (tipo || "") + '" value="' + esc(valor) + '">';
          return '<tr class="' + (igual ? "cr-igual" : "") + '"><td><label><input type="checkbox" data-usar="' + k + '"' + (igual ? "" : " checked") + "> " +
            esc(c[1]) + '</label></td><td class="cr-hoje" title="' + esc(texto(hoje)) + '">' + esc(mostrarValor(hoje, tipo)) + "</td><td>" + campo + "</td></tr>";
        }).join("");
        var fotosDeste = it.codigo ? Number(it.fotos || 0) : null;
        painelAtu(
          "<h3>O que mudou no #" + alvo + "?</h3>" +
          '<p class="cr-nota">Marque o que vale a informação nova (pode editar o valor antes). O que ficar desmarcado continua como está no #' + alvo + ".</p>" +
          '<table class="cr-diff"><thead><tr><th>Campo</th><th>No #' + alvo + " hoje</th><th>O novo</th></tr></thead><tbody>" +
            (linhas || '<tr><td colspan="3" class="cr-nota">Este cadastro não tem campos preenchidos para comparar.</td></tr>') + "</tbody></table>" +
          '<p><label><input type="checkbox" id="cr-atu-fotos" checked> Levar as fotos ' +
            (fotosDeste == null ? "que o dono mandou" : "(" + fotosDeste + ")") + " para o #" + alvo + " (sem repetir as que já estão lá)</label></p>" +
          '<p style="display:flex;gap:8px;flex-wrap:wrap;margin-top:12px">' +
            '<button class="cr-aprovar" type="button" id="cr-atu-aplicar">Aplicar no #' + alvo + "</button>" +
            '<button class="cr-acao" type="button" id="cr-atu-voltar">Cancelar</button></p>');
      })
      .catch(function (e) { painelAtu('<p class="cr-recado--erro">Não consegui comparar: ' + esc(e.message) + "</p>"); });
  }

  function aplicarAtualizacao() {
    var it = fila[pos], alvo = atu.alvo;
    if (ocupado || !alvo) return;
    var p = $("cr-corpo-popup").querySelector(".cr-atu");
    var corpo = {};
    p.querySelectorAll("[data-usar]:checked").forEach(function (cb) {
      var k = cb.getAttribute("data-usar");
      var el = p.querySelector('.cr-valor[data-k="' + k + '"]');
      var t = el.getAttribute("data-t"), v = String(el.value || "").trim();
      if (!v) { corpo[k] = null; return; }
      if (t === "din") corpo[k] = dinheiroDe(v);
      else if (t === "int") corpo[k] = Math.round(numeroDe(v));
      else if (t === "num") corpo[k] = numeroDe(v);
      else corpo[k] = v;
    });
    var fotos = !!(p.querySelector("#cr-atu-fotos") || {}).checked;
    ocupado = true;
    $("cr-atu-aplicar").disabled = true;
    recado("Aplicando no #" + alvo + "…");
    (Object.keys(corpo).length ? put(alvo, corpo) : Promise.resolve())
      .then(function () { return juntar(it.codigo ? { de_codigo: it.codigo, em: alvo, fotos: fotos } : { de_ficha: it.fichaId, em: alvo, fotos: fotos }); })
      .then(function (r) {
        ocupado = false;
        feitos[chave(it)] = true;
        var era = it.codigo ? "#" + it.codigo + " virou Excluído (atualização do #" + alvo + ")" : "a ficha ficou ligada ao #" + alvo;
        fecharAtualizacao();
        it.codigo = alvo; it.status = null; it.fonte = "imovel"; it._origem = undefined; pintarOrigem(it);
        $("cr-corpo-popup").innerHTML = '<iframe title="Cadastro do imóvel" src="imovel-editar.html?codigo=' + alvo + '&rapido=1"></iframe>';
        var f = $("cr-corpo-popup").querySelector("iframe");
        f.addEventListener("load", function () { aoCarregarOEditor(f, it); });
        pintarFaixa();
        recado("Feito: " + Object.keys(corpo).length + " campo(s) no #" + alvo + (r.fotos ? ", " + r.fotos + " foto(s) levada(s)" : "") +
          (r.dono ? ", dono ligado" : "") + "; " + era + ". O #" + alvo + " está aberto abaixo, se quiser editar mais.", "ok");
      })
      .catch(function (e) {
        ocupado = false;
        var b = $("cr-atu-aplicar"); if (b) b.disabled = false;
        recado("Não apliquei: " + e.message, "erro");
      });
  }

  /* ---- a OLX: o favorito traz o anúncio para esta página -------------------- */
  // o mesmo leitor do anúncio da aba Captação OLX (captacao-olx.js), com o destino nesta página
  function botaoDaOlx(destino) {
    try {
      var fontes = [];
      var a1 = document.getElementById("initial-data");
      if (a1) fontes.push(a1.getAttribute("data-json"));
      var a2 = document.getElementById("__NEXT_DATA__");
      if (a2) fontes.push(a2.textContent);
      var achar = function (n, p) {
        if (p > 9 || !n || typeof n !== "object") return null;
        if (Array.isArray(n)) {
          for (var i = 0; i < n.length && i < 20; i++) { var a = achar(n[i], p + 1); if (a) return a; }
          return null;
        }
        if ("subject" in n && ("images" in n || "properties" in n)) return n;
        for (var k in n) { if (n[k] && typeof n[k] === "object") { var b = achar(n[k], p + 1); if (b) return b; } }
        return null;
      };
      var ad = null;
      for (var f = 0; f < fontes.length && !ad; f++) { try { ad = achar(JSON.parse(fontes[f]), 0); } catch (e) { ad = null; } }
      if (!ad) { alert("Não achei o anúncio nesta página. Abra a página do imóvel na OLX e clique de novo."); return; }
      var o = {
        url: location.href.split("#")[0].split("?")[0],
        anuncio: {
          listId: ad.listId, subject: ad.subject, body: ad.body,
          priceValue: ad.priceValue, priceLabel: ad.priceLabel, location: ad.location,
          properties: (ad.properties || []).map(function (p) { return { name: p.name, label: p.label, value: p.value }; }),
          images: (ad.images || []).map(function (i) { return typeof i === "string" ? i : (i.original || i.originalAlternative || i.url); }).filter(Boolean)
        }
      };
      var alvo = destino + "#olx=" + encodeURIComponent(JSON.stringify(o));
      var janela = window.open(alvo, "_blank");
      if (!janela) location.href = alvo;
    } catch (e) {
      alert("Não consegui ler o anúncio: " + e.message);
    }
  }
  var fav = $("cr-fav");
  fav.href = "javascript:" + encodeURIComponent("(" + botaoDaOlx.toString() + ")(" +
    JSON.stringify(location.origin + location.pathname) + ")");
  fav.addEventListener("click", function (e) {
    e.preventDefault();
    $("cr-olx-recado").innerHTML = "Esse botão não funciona aqui: <strong>arraste</strong> ele para a barra de favoritos e use na página do anúncio da OLX.";
  });
  $("cr-olx-form").addEventListener("submit", function (e) {
    e.preventDefault();
    var link = $("cr-olx-link").value.trim();
    if (!/^https?:\/\/([a-z0-9-]+\.)*olx\.com\.br\//i.test(link)) {
      $("cr-olx-recado").textContent = "Esse link não é de um anúncio da OLX.";
      return;
    }
    link = link.replace(/^http:/i, "https:").replace(/^https:\/\/www\.olx\.com\.br\//i, "https://am.olx.com.br/");
    window.open(link, "_blank", "noopener");
    $("cr-olx-recado").innerHTML = "Abri o anúncio numa aba nova. Lá, clique em <strong>Enviar para Imob Easy</strong> na barra de favoritos.";
  });

  function enviarJson(url, metodo, corpo) {
    return fetch(url, { method: metodo, credentials: "same-origin", headers: { "Content-Type": "application/json" },
                        body: JSON.stringify(corpo) }).then(json);
  }

  function importarDaOlx(pacote) {
    aba.click();
    var r = $("cr-olx-recado");
    r.textContent = "Lendo o anúncio da OLX…";
    enviarJson("/admin/api/imoveis/olx/importar", "POST", pacote).then(function (d) {
      var fotos = d.fotos || [];
      var ok = 0, k = 0;
      var cadeia = Promise.resolve();
      fotos.forEach(function (url, i) {
        cadeia = cadeia.then(function () {
          k = i + 1;
          r.textContent = "Pré-cadastro #" + d.codigo + (d.novo ? " criado" : " (já existia)") + ". Baixando foto " + k + " de " + fotos.length + "…";
          return enviarJson("/admin/api/imoveis/olx/" + d.codigo + "/foto", "POST", { url: url, ordem: i + 1 })
            .then(function (x) { if (x.ok) ok++; }).catch(function () {});
        });
      });
      return cadeia.then(function () {
        r.textContent = "Da OLX: pré-cadastro #" + d.codigo + " com " + (ok + (d.fotos_ja || 0)) + " foto(s). Abrindo no cadastro rápido…";
        return carregar(function () {
          var lista = visiveis();
          var i = lista.findIndex(function (x) { return String(x.codigo) === String(d.codigo); });
          if (i < 0) { lista = [{ codigo: d.codigo, titulo: d.titulo || "Anúncio da OLX", origem: "olx", status: "Rascunho",
                                   fonte: "imovel", motivos: ["pré-cadastro (Rascunho)"], falta: [] }].concat(lista); i = 0; }
          abrir(lista, i);
        });
      });
    }).catch(function (e) { r.textContent = "Não importei da OLX: " + e.message; });
  }

  // chegou pelo favorito: #olx=... (a aba abre sozinha)
  var h = location.hash;
  if (h.indexOf("#olx=") === 0) {
    var pacote = null;
    try { pacote = JSON.parse(decodeURIComponent(h.slice(5))); } catch (e) { pacote = null; }
    history.replaceState(null, "", location.pathname + location.search);
    if (pacote) setTimeout(function () { importarDaOlx(pacote); }, 300);
  } else if (h === "#rapido") {
    setTimeout(function () { aba.click(); }, 300);
  }
})();
