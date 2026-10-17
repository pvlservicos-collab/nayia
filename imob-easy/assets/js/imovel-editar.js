/* ==========================================================================
   Imob Easy — Tela de edição (e de cadastro) de um imóvel

   Refeita em 28/09/2026. Pedro: "tá tudo muito confuso em uma galeria branca
   estranha, não quero assim, quero fotos em cima, e os campos embaixo
   organizados por categorias, fáceis de editar... bem organizado e
   visualmente diferente cada conjunto de dados".

   E no mesmo dia, sobre o cadastro: "ponha todos os campos do site antigo mas
   sem ser obrigatório, põe só as informações que tivermos" (o Tel não
   conseguia cadastrar, e não tinha nem onde pôr o número do apartamento).

   - A SITUAÇÃO fica no alto, numa faixa presa ao rolar, junto do "no site" e
     do "chega na Nay". Ela manda no anúncio (regra do Tel de 27/09, aplicada
     no servidor): nosso e Disponível fica no site e na Nay; o resto sai. No
     CADASTRO a faixa só tem o botão: o imóvel nasce como rascunho e a
     situação aparece depois de criar.
   - As FOTOS vêm logo abaixo (elas moram no site antigo; aqui só se vê).
   - Cada conjunto de dados é um cartão com cor e ícone próprios.
   - Os campos vêm de três lugares:
       coluna do imóvel ........ o nome da coluna (regras do servidor)
       "x:" ................... chave do `extras`, com o nome que o site antigo
                                 usa -- é de lá que a Nay lê "incluso no
                                 aluguel" e "aceita financiamento"
       "p:" ................... a parte PRIVADA (unidade, locatário,
                                 observações), que só sai por /admin/api, com
                                 a senha do painel
   - Salvar manda SÓ o que mudou -- o campo mexido fica marcado -- e a tela
     avisa antes de sair com alteração não salva. Nenhum campo é obrigatório.

   Grava pelo próprio domínio (/admin/api, atrás da senha do painel).
   ========================================================================== */
(function () {
  "use strict";

  function esc(txt) {
    return String(txt == null ? "" : txt)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }
  function $(id) { return document.getElementById(id); }
  function slug(nome) { return String(nome).replace(/[^a-z0-9]+/gi, "-"); }

  var params = new URLSearchParams(window.location.search);
  var codigo = params.get("codigo");
  // NOVO IMOVEL: sem ?codigo e com ?novo=1, o formulário nasce vazio e grava com POST.
  var novo = !codigo && params.get("novo") === "1";
  var form = $("ed-form");
  var carregando = $("ed-carregando");

  if (!codigo && !novo) { carregando.textContent = "Nenhum imóvel informado no endereço (?codigo=...)."; return; }
  if (!window.API_BASE) { carregando.textContent = "config.js não define API_BASE."; return; }

  /* ---- a situação ---------------------------------------------------------- */
  var SITUACOES = ["Disponível", "Alugado", "Vendido", "Rascunho", "Em revisão", "Arquivado", "Removido", "Indisponível"];
  var COR_SITUACAO = {
    "Disponível": ["#2f7d58", "#e8f7f0"], "Alugado": ["#6d28d9", "#f1eaff"], "Vendido": ["#5d566a", "#efedf3"],
    "Rascunho": ["#5d566a", "#efedf3"], "Em revisão": ["#a8662f", "#fdf2ea"], "Arquivado": ["#5d566a", "#efedf3"],
    "Removido": ["#b42323", "#fdeef1"], "Indisponível": ["#b42323", "#fdeef1"],
    "Excluído": ["#5d566a", "#efedf3"]
  };
  function corDaSituacao(s) {
    var c = COR_SITUACAO[s] || ["#5d566a", "#efedf3"];
    return "--sc:" + c[0] + ";--sb:" + c[1];
  }

  /* ---- os campos e os conjuntos ----------------------------------------------
     Coluna: as chaves batem com CAMPOS_EDITAVEIS do app.py; o que o servidor
     não libera não aparece. "x:" e "p:" o servidor confere por lista própria. */
  var CAMPOS = {
    // localização
    condominio: { rotulo: "Condomínio", largo: true },
    logradouro: { rotulo: "Rua / avenida", largo: true },
    numero: { rotulo: "Número" },
    complemento: { rotulo: "Complemento", dica: "ponto de referência, conjunto" },
    bairro: { rotulo: "Bairro", lista: true },
    cidade: { rotulo: "Cidade", lista: true },
    estado: { rotulo: "Estado", lista: true },
    cep: { rotulo: "CEP" },
    // O andar voltou à tela em 02/10 (tinha saído no mesmo dia por "andar não precisa"): não é obrigatório nem
    // conta como "falta preencher", mas a Nay responde por ele ("andar baixo ou médio?" no Milano).
    andar: { rotulo: "Andar", lista: true, dica: "com elevador: o andar da unidade (a Nay responde por ele)" },
    // a unidade (privado)
    "p:torre": { rotulo: "Torre" },
    "p:bloco": { rotulo: "Bloco" },
    "p:unidade": { rotulo: "Apartamento" },
    "p:casa": { rotulo: "Número da casa", dica: "de rua ou no condomínio" },
    "p:lote": { rotulo: "Lote" },
    // o proprietário (fonte "o", migração 162): a OLX não traz -- é o último passo da captação
    "o:nome": { rotulo: "Nome" },
    "o:telefone": { rotulo: "Telefone / WhatsApp", dica: "é por ele que a Nay fala com o dono para marcar visita" },
    "o:email": { rotulo: "E-mail" },
    "o:documento": { rotulo: "CPF ou CNPJ" },
    "o:tratamento": { rotulo: "Tratamento", tipo: "escolha", opcoes: ["Sr.", "Sra.", "Dr.", "Dra."] },
    // características
    tipo: { rotulo: "Tipo", lista: true },
    quartos: { rotulo: "Quartos" }, suites: { rotulo: "Suítes" }, banheiros: { rotulo: "Banheiros" },
    "x:salas": { rotulo: "Salas", tipo: "inteiro" },
    vagas: { rotulo: "Vagas" }, vagas_cobertas: { rotulo: "Vagas cobertas" },
    /* UM CAMPO SÓ, E SE CHAMA ÁREA CONSTRUÍDA (Pedro, 03/10/2026): "em casa se coloca na área construída
       a metragem total, mas os imóveis estão sendo colocados na metragem de área útil; só trocar o nome onde
       está por área construída e apagar esse outro que foi criado". O dado continua em `area_util` (é o que a
       Nay e o card leem); o campo `x:area construida` saiu do formulário. */
    /* 11/10 (Pedro): "no apartamento é área útil e não área construída; área construída é coisa de casa; quando for
       casa fica tamanho do terreno e área construída, e área total é coisa de apartamento". O dado continua em
       `area_util`; o RÓTULO muda com o tipo (rotuloDe), e área total só aparece em apartamento/sala. */
    area_util: { rotulo: "Área útil", sufixo: "m²" }, area_total: { rotulo: "Área total", sufixo: "m²" },
    "x:tamanho do terreno": { rotulo: "Terreno", tipo: "m2", sufixo: "m²" },
    "x:frente": { rotulo: "Frente", tipo: "m", sufixo: "m" },
    "x:fundo": { rotulo: "Fundo", tipo: "m", sufixo: "m" },
    "x:pe direito": { rotulo: "Pé-direito", tipo: "m", sufixo: "m" },
    "x:andares": { rotulo: "Andares", tipo: "inteiro", dica: "da casa ou do prédio" },
    "x:elevadores": { rotulo: "Elevadores", tipo: "inteiro" },
    "x:lances de escada": { rotulo: "Lances de escada", tipo: "inteiro", dica: "sem elevador: quantos lances até a unidade" },
    cobertura: { rotulo: "É cobertura", tipo: "booleano", dica: "só apartamento e sala" },
    "x:tipo de cobertura": { rotulo: "Tipo da cobertura", tipo: "escolha", opcoes: ["Linear", "Duplex", "Triplex"] },
    sol: { rotulo: "Face solar", lista: true },
    // os 4 níveis (Pedro, 11/10): "pelado (sem nada), climatizado (só), com modulados e ar (o antigo semimobiliado), mobiliado"
    mobilia: { rotulo: "Mobília", tipo: "escolha", opcoes: ["sem nada", "só climatizado", "com modulados e ar", "mobiliado"] },
    /* 12/10 (Pedro): "a descrição é o texto de anúncio; a observação quem preenche somos nós, e quando preenchermos
       aí sim vai com o card". Nasce vazia: só o que a equipe escrever aqui sai com o card. */
    observacao: { rotulo: "Observação da equipe (sai com o card quando preenchida)", largo: true, longo: true,
      dica: "Só o que a equipe souber e valer a pena o corretor ler: \"falta só TV\", \"vista para o rio\", \"o dono negocia a mobília no aluguel\", \"aceita outro imóvel\". Vazio = o card vai como sempre." },
    // valores e negócio
    valor_aluguel: { rotulo: "Aluguel", prefixo: "R$", tipo: "dinheiro" }, valor_venda: { rotulo: "Venda", prefixo: "R$", tipo: "dinheiro" },
    taxa_condominio: { rotulo: "Condomínio", prefixo: "R$", tipo: "dinheiro" }, iptu: { rotulo: "IPTU", prefixo: "R$", tipo: "dinheiro" },
    "x:aceita financiamento": { rotulo: "Aceita financiamento", tipo: "simnao" },
    "x:permuta": { rotulo: "Permuta", tipo: "texto", lista: true, dica: "o que aceita como parte do pagamento" },
    "x:incluso no aluguel": { rotulo: "Incluso no aluguel", tipo: "marcar", largo: true,
      opcoes: ["Água", "Energia", "Internet", "Taxa de Gás", "Taxa de Condomínio", "IPTU"] },
    "x:garantia de aluguel": { rotulo: "Garantia de aluguel", tipo: "marcar", largo: true,
      opcoes: ["Depósito caução", "Seguro fiança", "Fiador", "Título de capitalização", "Carta fiança"] },
    // descrição
    descricao: { rotulo: "Descrição do anúncio", largo: true, longo: true },
    // o que tem: dois grupos, como a OLX mostra (Pedro, 28/09: "na OLX fica bem
    // divididinho, quero assim"). A coluna guarda todas -- é nela que a Nay
    // procura --; "x:caracteristicas do condominio" diz quais são do condomínio.
    caracteristicas: { rotulo: "Características", tipo: "grupos", largo: true },
    "x:caracteristicas do condominio": { rotulo: "Características do condomínio", tipo: "lista_texto" },
    // captação
    captado_por: { rotulo: "Captado por", lista: true },
    captado_em: { rotulo: "Captado em", tipo: "data_br" },
    "x:indicado por": { rotulo: "Indicado por", tipo: "texto", lista: true },
    "x:inspecionado por": { rotulo: "Inspecionado por", tipo: "texto", lista: true },
    // locação atual (privado)
    "p:locatario_nome": { rotulo: "Locatário" },
    "p:locatario_contato": { rotulo: "Contato do locatário" },
    "p:vencimento": { rotulo: "Vencimento do contrato", tipo: "data" },
    "p:observacao_aluguel": { rotulo: "Observação do aluguel", largo: true },
    // uso interno
    "p:observacoes": { rotulo: "Observações", largo: true, longo: true },
    bloqueado: { rotulo: "Bloqueado para a Nay", dica: "ela não oferece, mesmo disponível e no site" },
    motivo_bloqueio: { rotulo: "Motivo do bloqueio", largo: true, lista: true }
  };
  var GRUPOS = [
    // O ENDEREÇO É DO CONDOMÍNIO (Pedro, 02/10: "não quero ter que digitar a mesma informação 2
    // vezes... as informações do condomínio já são fixas"). Escolheu o condomínio, vem tudo dele;
    // o que for corrigido aqui o servidor guarda NO condomínio (273). "Andar não precisa": saiu.
    { titulo: "Condomínio e endereço", icone: "⌖", cor: "#2f6fb8", fundo: "#eaf2fb",
      nota: "Escolha o condomínio: o endereço e as características dele vêm do cadastro do condomínio (para mudar, Editar condomínio). Aqui fica só o complemento. Sem condomínio (casa de rua), preencha o endereço.",
      campos: ["condominio", "logradouro", "numero", "complemento", "bairro", "cidade", "estado", "cep"] },
    /* 11/10 (Pedro): "o andar sai de condomínio e passa a ficar dentro da unidade no imóvel": apartamento = torre,
       bloco, apartamento e andar (com elevador) ou lances de escada (sem); sala = setor e número da sala; casa = o
       número da casa. O que aparece depende do tipo e do elevador do condomínio (aplicarRegrasDoTipo). */
    { titulo: "Unidade", icone: "⌗", cor: "#4338ca", fundo: "#eef0ff", privado: true,
      nota: "Torre, bloco, número e lote nunca saem para o cliente. O andar e os lances de escada a Nay responde.",
      campos: ["p:torre", "p:bloco", "p:unidade", "p:casa", "p:lote", "andar", "x:lances de escada"] },
    { titulo: "Proprietário", icone: "✆", cor: "#0369a1", fundo: "#e0f2fe", privado: true, id: "ed-cartao-dono",
      nota: "A OLX não traz o dono do imóvel: estes dados são o último passo da captação.",
      campos: ["o:nome", "o:telefone", "o:email", "o:documento", "o:tratamento"] },
    { titulo: "Características", icone: "⌂", cor: "#6d28d9", fundo: "#f1eaff",
      campos: ["tipo", "quartos", "suites", "banheiros", "x:salas", "vagas", "vagas_cobertas", "area_util", "area_total",
        "x:tamanho do terreno", "x:frente", "x:fundo", "x:pe direito", "x:andares",
        "cobertura", "x:tipo de cobertura", "sol", "mobilia", "observacao"] },
    { titulo: "O que tem", icone: "✓", cor: "#0e7490", fundo: "#e6f6fa", largo: true,
      campos: ["caracteristicas"] },
    { titulo: "Valores e negócio", icone: "$", cor: "#c4762f", fundo: "#fdf2ea",
      campos: ["valor_aluguel", "valor_venda", "taxa_condominio", "iptu", "x:aceita financiamento", "x:permuta",
        "x:incluso no aluguel", "x:garantia de aluguel"] },
    { titulo: "Descrição", icone: "✎", cor: "#4b5563", fundo: "#f1f2f4",
      campos: ["descricao"] },
    { titulo: "Captação", icone: "✦", cor: "#0f766e", fundo: "#e6f6f4",
      campos: ["captado_por", "captado_em", "x:indicado por", "x:inspecionado por"] },
    { titulo: "Locação atual", icone: "⚿", cor: "#be185d", fundo: "#fdf0f6", privado: true,
      nota: "Fica fora do site. O vencimento é o mesmo da lista de proprietários por vencimento.",
      campos: ["p:locatario_nome", "p:locatario_contato", "p:vencimento", "p:observacao_aluguel"] },
    { titulo: "Uso interno", icone: "⚑", cor: "#b42323", fundo: "#fdeef1",
      campos: ["p:observacoes", "bloqueado", "motivo_bloqueio"] }
  ];

  var VALORES = {};          // as listas que descem, do próprio catálogo
  var regras = {};           // o que o servidor deixa gravar, e o tipo de cada um
  var item = {};             // o imóvel como veio
  var privado = null;        // a parte privada como veio (null = não abriu)
  var inicial = {};          // o valor de cada campo quando a tela abriu (ou no último salvar)
  var seletorCondo = null, condoInicial = null;
  var noSiteMexido = false;  // ele mexeu no "no site" com a mão?
  var donoNovo = false;      // "é outra pessoa": cadastra outro dono em vez de mudar o de hoje
  var semDonoOk = false;     // ele viu o aviso de "falta o proprietário" e mandou salvar assim mesmo
  var fotos = [], fotoAberta = 0;

  /* ---- de onde vem cada campo --------------------------------------------- */
  function fonte(nome) {
    var p = nome.slice(0, 2);
    return p === "x:" ? "x" : p === "p:" ? "p" : p === "o:" ? "o" : "c";
  }

  function aparece(nome) {
    var f = fonte(nome);
    if (novo && (nome === "bloqueado" || nome === "motivo_bloqueio")) return false; // o cadastro não grava bloqueio
    if (f === "x") return true;                 // o servidor confere pela lista dele
    if (f === "p" || f === "o") return privado !== null;   // sem a senha, a parte privada não abre
    return nome === "condominio" || !!regras[nome];
  }

  function tipoDe(nome) {
    var c = CAMPOS[nome] || {};
    if (c.tipo) return c.tipo;
    if (c.longo) return "longo";
    if (fonte(nome) === "p" || fonte(nome) === "o") return "texto";
    return (regras[nome] || {}).tipo || "texto";
  }

  function valorGuardado(nome) {
    var f = fonte(nome);
    if (f === "x") return (item.extras || {})[nome.slice(2)];
    if (f === "p") return privado ? privado[nome.slice(2)] : null;
    if (f === "o") return privado && privado.proprietario && !donoNovo ? privado.proprietario[nome.slice(2)] : null;
    return item[nome];
  }

  /* O DINHEIRO COM PONTO DE MILHAR (03/10/2026): "eu salvei a casa com valor de 850.000 e quando eu salvo
     todas as informações ela volta para o valor de 750... pode colocar quando a gente preencher aparece o valor
     assim: 750.000; hoje aparece assim: 750000". O campo era type="number": o navegador lê o ponto como vírgula
     decimal, e "750.000" era gravado como 750 (foi assim que o 9013 ficou à venda por R$ 690). Agora é texto com
     máscara: o ponto é SEMPRE milhar, e centavo só existe depois da vírgula. */
  function formatarDinheiro(v) {
    var s = String(v == null ? "" : v).replace(/[^\d,]/g, "");
    var partes = s.split(",");
    var inteiro = partes[0].replace(/^0+(?=\d)/, "").replace(/\B(?=(\d{3})+(?!\d))/g, ".");
    if (partes.length === 1) return inteiro;
    return (inteiro || "0") + "," + partes.slice(1).join("").slice(0, 2);
  }
  // o número guardado (750000 ou 1089.5) do jeito que se escreve: "750.000", "1.089,50"
  function dinheiroDoBanco(v) {
    var n = Number(v);
    if (!isFinite(n)) return "";
    var centavos = Math.round(n * 100);
    var resto = centavos % 100;
    return formatarDinheiro(String((centavos - resto) / 100) + (resto ? "," + (resto < 10 ? "0" : "") + resto : ""));
  }
  // "750.000" -> 750000; "1.089,50" -> 1089.5; vazio -> null
  function numeroDoDinheiro(s) {
    var t = String(s == null ? "" : s).replace(/\./g, "").replace(",", ".").replace(/[^\d.]/g, "");
    return t === "" || t === "." ? null : Number(t);
  }

  // o que está guardado, no formato da entrada ("115.0 m2" -> 115; "27/05/2024" -> 2024-05-27)
  function paraEntrada(tipo, v) {
    if (v == null || v === "") return "";
    if (tipo === "dinheiro") return dinheiroDoBanco(v);
    if (tipo === "m2" || tipo === "m") {
      var n = String(v).match(/\d+(?:[.,]\d+)?/);
      return n ? String(Number(n[0].replace(",", "."))) : "";
    }
    if (tipo === "data_br") {
      var d = String(v).match(/^(\d{2})\/(\d{2})\/(\d{4})/);
      return d ? d[3] + "-" + d[2] + "-" + d[1] : "";
    }
    if (tipo === "data") return String(v).slice(0, 10);
    return String(v);
  }

  /* ---- o que aparece depende do TIPO (Pedro, 11/10/2026) -----------------------
     "As características hoje estão muito misturadas. Elas precisam estar por tipo de imóvel": apartamento tem área
     útil e total, cobertura, torre/bloco/apartamento e andar (ou lances de escada, sem elevador); casa tem área
     construída, tamanho do terreno, pé-direito, andares da casa e o número da casa; sala tem setor e número da sala;
     lote tem terreno. O que não é do tipo fica escondido (continua guardado, não é apagado). */
  var FAMILIA = [["vertical", /apartamento|flat|cobertura|studio|kitnet|loft/i], ["sala", /sala|loja|ponto|conjunto|escrit[oó]rio/i],
                 ["casa", /casa|ch[aá]cara|s[ií]tio|fazenda|sobrado/i], ["terreno", /lote|terreno/i]];
  var POR_TIPO = {
    area_total: ["vertical", "sala", "outro"], cobertura: ["vertical", "sala"], "x:tipo de cobertura": ["vertical", "sala"],
    "x:tamanho do terreno": ["casa", "terreno", "outro"], "x:frente": ["casa", "terreno"], "x:fundo": ["casa", "terreno"],
    "x:pe direito": ["casa", "outro"], "x:andares": ["casa", "outro"],
    andar: ["vertical", "sala", "outro"], "x:lances de escada": ["vertical", "sala", "outro"],
    "p:torre": ["vertical"], "p:bloco": ["vertical", "sala"], "p:unidade": ["vertical", "sala"],
    "p:casa": ["casa"], "p:lote": ["casa", "terreno"],
    quartos: ["vertical", "casa", "outro"], suites: ["vertical", "casa", "outro"], "x:salas": ["sala", "outro"],
    mobilia: ["vertical", "casa", "sala", "outro"]
  };
  var ROTULO_POR_TIPO = {
    area_util: { casa: "Área construída", terreno: "Área construída" },
    "p:bloco": { sala: "Bloco / setor" }, "p:unidade": { sala: "Número da sala" }
  };
  var condoFicha = null;      // a ficha do condomínio escolhido (elevador decide andar x lances)

  function tipoAtual() {
    var el = form ? form.querySelector('[data-campo="tipo"]') : null;
    return el ? String(el.value || "") : String(item.tipo || "");
  }
  function familiaDoTipo(t) {
    for (var k = 0; k < FAMILIA.length; k++) if (FAMILIA[k][1].test(t || "")) return FAMILIA[k][0];
    return "outro";
  }
  function rotuloDe(nome) {
    var f = familiaDoTipo(tipoAtual());
    var por = ROTULO_POR_TIPO[nome];
    return (por && por[f]) || (CAMPOS[nome] || { rotulo: nome }).rotulo;
  }
  function elevadorDoCondominio() {
    var e = condoFicha && condoFicha.elevador ? String(condoFicha.elevador) : "";
    if (/^\s*(sim|possui|tem|\d)/i.test(e)) return true;
    if (/^\s*n[aã]o/i.test(e)) return false;
    return null;
  }
  function aplicarRegrasDoTipo() {
    if (!form) return;
    var f = familiaDoTipo(tipoAtual());
    var elev = elevadorDoCondominio();
    var cob = form.querySelector('[data-campo="cobertura"]');
    Object.keys(POR_TIPO).forEach(function (nome) {
      var bloco = form.querySelector('[data-envolve="' + nome + '"]');
      if (!bloco) return;
      var mostra = POR_TIPO[nome].indexOf(f) >= 0;
      if (nome === "andar" && mostra && elev === false) mostra = false;               // sem elevador: lances
      if (nome === "x:lances de escada" && mostra && elev === true) mostra = false;   // com elevador: andar
      if (nome === "x:tipo de cobertura" && mostra) mostra = !!(cob && cob.checked);
      bloco.hidden = !mostra;
    });
    Object.keys(ROTULO_POR_TIPO).forEach(function (nome) {
      var bloco = form.querySelector('[data-envolve="' + nome + '"]');
      var rot = bloco ? bloco.querySelector("label") : null;
      if (rot) rot.textContent = rotuloDe(nome);
    });
    var dicaAndar = form.querySelector('[data-envolve="andar"] .ed__dica');
    if (dicaAndar) dicaAndar.textContent = elev === true ? "O condomínio tem elevador: o andar da unidade."
      : elev === false ? "O condomínio não tem elevador: use os lances de escada." : "Com elevador: o andar (a Nay responde por ele).";
  }

  /* ---- o condomínio, só para ler (Pedro, 11/10: "quando eu abrir um imóvel ele já vai abrir as informações do
     condomínio, não para editar, só para mostrar; para editar tem um botão Editar Condomínio") ---- */
  var pedidoDaFicha = 0;
  function mostrarFichaDoCondominio() {
    var caixa = $("ed-condo-ficha");
    if (!caixa) return;
    var escolhido = seletorCondo && seletorCondo.valores()[0];
    if (!escolhido || !escolhido.id) { condoFicha = null; caixa.hidden = true; caixa.innerHTML = ""; aplicarRegrasDoTipo(); return; }
    var meu = ++pedidoDaFicha;
    fetch(window.API_BASE + "/api/condominios/" + encodeURIComponent(escolhido.id) + "/ficha")
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (f) {
        if (meu !== pedidoDaFicha) return;
        condoFicha = f || {};
        caixa.hidden = false;
        caixa.innerHTML = fichaHtml(escolhido, f);
        aplicarRegrasDoTipo();
      })
      .catch(function () { if (meu === pedidoDaFicha) { condoFicha = null; aplicarRegrasDoTipo(); } });
  }
  function chips(lista) {
    return (lista || []).length ? '<div class="ed__cf-chips">' + lista.map(function (x) { return '<span class="ed__cf-chip">' + esc(x) + "</span>"; }).join("") + "</div>" : "";
  }
  function fichaHtml(escolhido, f) {
    var editar = '<a class="ed__cf-editar" href="imoveis.html?condominio=' + encodeURIComponent(escolhido.id) + '" target="_blank" rel="noopener">Editar condomínio</a>';
    if (!f || !f.id) {
      return '<div class="ed__cf"><div class="ed__cf-topo"><b>Do condomínio</b>' + editar + "</div>" +
        '<p class="ed__dica">Este condomínio ainda não tem ficha (torres, elevador, lazer…). Cadastre uma vez em Editar condomínio: vale para todos os imóveis dele.</p></div>';
    }
    var estrutura = [f.tipo === "casas_lotes" ? "casas / lotes" : "prédio", f.torres, f.andares, f.aptos_por_andar ? f.aptos_por_andar + " por andar" : "",
      f.elevador, f.unidades].filter(Boolean).join(" · ");
    var quem = [f.construtora ? "construtora " + f.construtora : "", f.ano ? "ano " + f.ano : "", f.revestimento ? "revestimento " + f.revestimento : ""].filter(Boolean).join(" · ");
    var taxas = (f.taxas || []).map(function (t) {
      return (t.quartos ? t.quartos + " quartos" : t.metragem ? t.metragem + " m²" : "—") + ": condomínio R$ " + (t.condominio || "—") + (t.iptu ? " · IPTU R$ " + t.iptu : "");
    }).join("; ");
    return '<div class="ed__cf"><div class="ed__cf-topo"><b>Do condomínio</b><span class="ed__cf-fonte">' + esc(f.nome) + (f.fonte ? " · " + esc(f.fonte) : "") + "</span>" + editar + "</div>" +
      (estrutura ? '<p class="ed__cf-linha">' + esc(estrutura) + "</p>" : "") +
      (quem ? '<p class="ed__cf-linha">' + esc(quem) + "</p>" : "") +
      ((f.lazer || []).length ? '<p class="ed__cf-rot">Lazer</p>' + chips(f.lazer) : "") +
      ((f.seguranca || []).length ? '<p class="ed__cf-rot">Segurança</p>' + chips(f.seguranca) : "") +
      ((f.comodidades || []).length ? '<p class="ed__cf-rot">Comodidades e serviços</p>' + chips(f.comodidades) : "") +
      (taxas ? '<p class="ed__cf-linha"><b>Taxas:</b> ' + esc(taxas) + "</p>" : "") +
      ((f.taxa_inclui || []).length ? '<p class="ed__cf-linha"><b>A taxa inclui:</b> ' + esc(f.taxa_inclui.join(", ")) + "</p>" : "") +   // 367
      (f.observacao ? '<p class="ed__cf-linha"><b>Obs.:</b> ' + esc(f.observacao) + "</p>" : "") +
      (!estrutura && !quem && !(f.lazer || []).length ? '<p class="ed__dica">A ficha deste condomínio está vazia: complete em Editar condomínio.</p>' : "") +
      "</div>";
  }

  /* ---- montar -------------------------------------------------------------- */
  function datalist(nome) {
    var vs = VALORES[nome] || [];
    return vs.length ? '<datalist id="ed-lista-' + slug(nome) + '">' +
      vs.map(function (v) { return "<option>" + esc(v) + "</option>"; }).join("") + "</datalist>" : "";
  }

  /* ---- o que tem: características do imóvel e do condomínio -----------------
     Imóvel sem a divisão guardada (todos os de antes de 28/09) é separado por
     palavra: o que só existe em condomínio vai para lá; piscina, churrasqueira,
     academia, portão eletrônico e gerador só quando o imóvel é de condomínio
     (numa casa de rua são dela). Ele corrige com o ⇄. */
  var SO_DE_CONDOMINIO = /condom[ií]nio fechado|portaria|porteiro|seguran[cç]a 24|guarita|sal[aã]o de (festas|jogos)|playground|brinquedoteca|elevador|quadra|biciclet[aá]rio|coworking|espa[cç]o pet|pet place|cinema|lavanderia coletiva/i;
  var TALVEZ_DE_CONDOMINIO = /piscina|churrasqueira|academia|sauna|espa[cç]o gourmet|[aá]rea de lazer|\bspa\b|port[aã]o eletr[oô]nico|gerador/i;

  function separarLista(txt) {
    var itens = [];
    String(txt || "").split(/[,\n]/).forEach(function (x) { x = x.trim(); if (x && itens.indexOf(x) < 0) itens.push(x); });
    return itens;
  }

  function doCondominio(todos) {
    var guardado = (item.extras || {})["caracteristicas do condominio"];
    if (guardado != null) {
      return separarLista(guardado).filter(function (x) { return todos.indexOf(x) >= 0; });
    }
    var emCondominio = !!(item.condo_id || item.condominio_nome) ||
      /apartamento|flat|cobertura|condom/i.test(item.tipo || "");
    return todos.filter(function (x) {
      return SO_DE_CONDOMINIO.test(x) || (emCondominio && TALVEZ_DE_CONDOMINIO.test(x));
    });
  }

  function chipHtml(x) {
    return '<span class="ed__chip" data-item="' + esc(x) + '"><span>' + esc(x) + "</span>" +
      '<button type="button" class="ed__chip-botao" data-tirar title="Tirar" aria-label="Tirar ' + esc(x) + '">×</button></span>';
  }

  function gruposHtml(v) {
    // 11/10 (Pedro): "as características de condomínio ficam na aba condomínio e não misturadas com a do imóvel".
    // Aqui só as do imóvel; as do condomínio aparecem, só para ler, no bloco "Do condomínio" (mostrarFichaDoCondominio).
    var todos = Array.isArray(v) ? v.slice() : [];
    var imovel = todos;
    function secao(qual, titulo, itens) {
      return '<section class="ed__grupo" data-grupo="' + qual + '">' +
        '<h3 class="ed__grupo-titulo">' + titulo + "</h3>" +
        '<div class="ed__chips">' + itens.map(chipHtml).join("") + "</div>" +
        '<input class="entrada ed__grupo-mais" list="ed-lista-caracteristicas" data-acrescentar-grupo="' + qual + '"' +
          ' placeholder="Acrescentar (Enter)" aria-label="Acrescentar em ' + titulo + '">' +
        "</section>";
    }
    return '<div class="ed__campo ed__campo--largo" data-envolve="caracteristicas">' +
      '<div class="ed__grupos" data-campo="caracteristicas" data-grupos="true">' +
        secao("imovel", "Características do imóvel", imovel) +
      "</div>" +
      datalist("caracteristicas") +
      '<span class="ed__dica">Só o que é do imóvel (varanda, closet, armários, piscina da casa…). Piscina do prédio, portaria, ' +
        'salão de festas e elevador são do condomínio: ficam no cadastro do condomínio e valem para todos os imóveis dele.</span>' +
      "</div>";
  }

  function itensDoGrupo(caixa, qual) {
    return Array.prototype.map.call(caixa.querySelectorAll('[data-grupo="' + qual + '"] .ed__chip'),
      function (c) { return c.getAttribute("data-item"); });
  }

  function sincronizarGrupos(caixa) { /* 11/10: um grupo só; ficou pelo nome, para quem chama */ }

  function acrescentarNoGrupo(entrada) {
    var qual = entrada.getAttribute("data-acrescentar-grupo");
    var caixa = entrada.closest("[data-grupos]");
    var v = String(entrada.value || "").trim();
    entrada.value = "";
    if (!v || !caixa) return;
    var existente = Array.prototype.find.call(caixa.querySelectorAll(".ed__chip"), function (c) {
      return c.getAttribute("data-item").toLowerCase() === v.toLowerCase();
    });
    var destino = caixa.querySelector('[data-grupo="' + qual + '"] .ed__chips');
    if (existente) destino.appendChild(existente);        // já tinha: só muda de grupo
    else destino.insertAdjacentHTML("beforeend", chipHtml(v));
    sincronizarGrupos(caixa);
    atualizarBotao();
  }

  function campoHtml(nome) {
    var c = CAMPOS[nome] || { rotulo: nome };
    var tipo = tipoDe(nome);
    var v = valorGuardado(nome);
    var id = "ed-" + slug(nome);
    var dados = ' data-campo="' + esc(nome) + '"';
    var classes = "ed__campo" + (c.largo ? " ed__campo--largo" : "");
    var dica = c.dica ? '<span class="ed__dica">' + esc(c.dica) + "</span>" : "";
    var envolve = ' data-envolve="' + esc(nome) + '"';
    var rotulo = '<label for="' + id + '">' + esc(rotuloDe(nome)) + "</label>";

    if (tipo === "grupos") return gruposHtml(v);
    if (nome === "condominio") {
      return '<div class="' + classes + '" data-envolve="condominio"><label for="ed-condominio">Condomínio</label>' +
        '<input class="entrada" type="text" id="ed-condominio" placeholder="Digite o nome e escolha na lista">' +
        '<span class="ed__dica" id="ed-condo-dica"></span>' +
        '<div class="ed__dica" id="ed-condo-endereco" style="margin-top:6px;font-size:13px" hidden></div>' +
        '<div class="ed__condo-ficha" id="ed-condo-ficha" hidden></div>' +
        '<div class="ed__no-condo" id="ed-no-condo" hidden></div></div>';
    }
    if (tipo === "booleano") {
      return '<div class="' + classes + ' ed__campo--chave"' + envolve + '>' +
        '<label class="ed__chave"><input type="checkbox"' + dados + (v ? " checked" : "") + '>' +
        '<span class="ed__chave-trilho" aria-hidden="true"></span><span>' + esc(c.rotulo) + "</span></label>" + dica + "</div>";
    }
    if (tipo === "lista") {
      var texto = Array.isArray(v) ? v.join("\n") : "";
      return '<div class="' + classes + '"' + envolve + ">" + rotulo +
        '<textarea class="entrada" id="' + id + '" rows="5"' + dados + ' data-lista="true">' + esc(texto) + "</textarea>" +
        '<input class="entrada ed__acrescenta" list="ed-lista-' + slug(nome) + '" placeholder="escolher da lista e acrescentar" data-acrescenta="' + esc(nome) + '">' +
        datalist(nome) + dica + "</div>";
    }
    if (tipo === "longo") {
      return '<div class="' + classes + '"' + envolve + ">" + rotulo +
        '<textarea class="entrada" id="' + id + '" rows="6"' + dados + ">" + esc(v || "") + "</textarea>" + dica + "</div>";
    }
    if (tipo === "marcar") {
      // os que o site antigo tinha, mais qualquer valor guardado fora da lista
      var marcados = String(v || "").split(",").map(function (s) { return s.trim(); }).filter(Boolean);
      var todos = c.opcoes.slice();
      marcados.forEach(function (m) { if (todos.indexOf(m) < 0) todos.push(m); });
      return '<div class="' + classes + '"' + envolve + '><span class="ed__rotulo-grupo" id="' + id + '-rot">' + esc(c.rotulo) + "</span>" +
        '<div class="ed__marcar" role="group" aria-labelledby="' + id + '-rot"' + dados + ' data-marcar="true">' +
        todos.map(function (o) {
          return '<label class="ed__marca"><input type="checkbox" value="' + esc(o) + '"' +
            (marcados.indexOf(o) >= 0 ? " checked" : "") + "><span>" + esc(o) + "</span></label>";
        }).join("") + "</div>" + dica + "</div>";
    }
    if (tipo === "simnao" || tipo === "escolha") {
      var opcoes = tipo === "simnao" ? ["Sim", "Não"] : c.opcoes.slice();
      var atual = v == null ? "" : String(v);
      if (atual && opcoes.indexOf(atual) < 0) opcoes.push(atual);
      return '<div class="' + classes + '"' + envolve + ">" + rotulo +
        '<select class="entrada" id="' + id + '"' + dados + '><option value="">—</option>' +
        opcoes.map(function (o) { return "<option" + (o === atual ? " selected" : "") + ">" + esc(o) + "</option>"; }).join("") +
        "</select>" + dica + "</div>";
    }
    if (tipo === "data" || tipo === "data_br") {
      return '<div class="' + classes + '"' + envolve + ">" + rotulo +
        '<input class="entrada" type="date" id="' + id + '"' + dados + ' value="' + esc(paraEntrada(tipo, v)) + '">' + dica + "</div>";
    }
    var numero = tipo === "numero" || tipo === "inteiro" || tipo === "m2" || tipo === "m";
    var entrada = '<input class="entrada" id="' + id + '"' + dados +
      (tipo === "dinheiro" ? ' type="text" inputmode="decimal" autocomplete="off" data-dinheiro="true" placeholder="0"'
        : numero ? ' type="number" inputmode="decimal"' + (tipo === "inteiro" ? ' step="1"' : ' step="0.01"') + ' min="0"' : ' type="text"') +
      (c.lista ? ' list="ed-lista-' + slug(nome) + '"' : "") +
      ' value="' + esc(paraEntrada(tipo, v)) + '">';
    if (c.prefixo || c.sufixo) {
      entrada = '<span class="ed__unidade">' + (c.prefixo ? '<span class="ed__un">' + c.prefixo + "</span>" : "") +
        entrada + (c.sufixo ? '<span class="ed__un">' + c.sufixo + "</span>" : "") + "</span>";
    }
    return '<div class="' + classes + '"' + envolve + ">" + rotulo +
      entrada + (c.lista ? datalist(nome) : "") + dica + "</div>";
  }

  function eParceiro() { return $("ed-parceiro") ? $("ed-parceiro").checked : !!item.e_parceiro; }

  function chegaNaNay(situacao, noSite) {
    var bloq = inputDe("bloqueado");
    var bloqueado = bloq ? bloq.checked : !!item.bloqueado;
    return situacao === "Disponível" && noSite && !eParceiro() && !bloqueado;
  }

  function desenharEstado() {
    // no cadastro, só o botão: a situação aparece depois de criar
    if (novo) {
      $("ed-estado").innerHTML =
        '<div class="ed__estado-item"><span class="ed__estado-novo">Nenhum campo é obrigatório: preencha só o que tiver.</span></div>' +
        '<div class="ed__estado-salvar"><span class="ed__status-salvar" id="ed-status-salvar" role="status"></span>' +
          '<button class="btn-azul" type="submit" id="ed-salvar">Cadastrar imóvel</button></div>';
      return;
    }
    var sit = item.status || "Disponível";
    var opcoes = SITUACOES.slice();
    if (opcoes.indexOf(sit) < 0) opcoes.unshift(sit);
    $("ed-estado").innerHTML =
      '<div class="ed__estado-item"><span class="ed__rot">Situação</span>' +
        '<select class="ed-situacao" id="ed-situacao" style="' + corDaSituacao(sit) + '" aria-label="Situação do imóvel">' +
          opcoes.map(function (s) { return "<option" + (s === sit ? " selected" : "") + ">" + esc(s) + "</option>"; }).join("") +
        "</select></div>" +
      '<div class="ed__estado-item"><label class="ed__chave ed__chave--forte"><input type="checkbox" data-campo="publicado_no_site" id="ed-no-site"' +
        (item.publicado_no_site ? " checked" : "") + '><span class="ed__chave-trilho" aria-hidden="true"></span><span>No site</span></label></div>' +
      '<div class="ed__estado-item"><span class="ed__nay" id="ed-nay"></span></div>' +
      // 400 (Pedro, 17/10: "adicione uma Situação, Parceiros ... que fique sempre claro que esses são de parceiros"):
      // a marca à mão fica gravada e a leitura do site antigo não desfaz
      '<div class="ed__estado-item"><label class="ed__chave ed__chave--parceiro" title="Imóvel de parceiro: nunca vai a corretor ' +
        '(número Parceria); vai só a cliente final do número de captação (OLX)"><input type="checkbox" data-campo="e_parceiro" id="ed-parceiro"' +
        (item.e_parceiro ? " checked" : "") + '><span class="ed__chave-trilho" aria-hidden="true"></span><span>Parceiro</span></label>' +
        '<span class="etiqueta-parceiro" id="ed-selo-parceiro"' + (item.e_parceiro ? "" : " hidden") + '>Parceiro</span></div>' +
      '<div class="ed__estado-salvar"><span class="ed__status-salvar" id="ed-status-salvar" role="status"></span>' +
        (sit === "Excluído" ? "" : '<button class="btn-neutro ed__excluir" type="button" id="ed-excluir">Excluir imóvel</button>') +
        '<button class="btn-azul" type="submit" id="ed-salvar" disabled>Salvar</button></div>';
    atualizarNay();
  }

  function atualizarNay() {
    var el = $("ed-nay");
    if (!el) return;
    var sel = $("ed-situacao");
    var sit = sel ? sel.value : (item.status || "");
    var noSite = $("ed-no-site") ? $("ed-no-site").checked : false;
    var chega = chegaNaNay(sit, noSite);
    var soCliente = !chega && eParceiro() && sit === "Disponível";
    el.className = "ed__nay" + (chega ? " ed__nay--sim" : "");
    el.textContent = chega ? "Chega na Nay" : soCliente ? "Só cliente final (OLX, 8595)" : "Não chega na Nay";
    var selo = $("ed-selo-parceiro");
    if (selo) selo.hidden = !eParceiro();
  }

  function desenharCartoes() {
    $("ed-cartoes").innerHTML = GRUPOS.map(function (g) {
      var campos = g.campos.filter(aparece);
      var aviso = "";
      if (g.privado && privado === null) {
        aviso = '<p class="ed__cartao-nota ed__cartao-nota--erro">Não deu para abrir esta parte (ela pede a senha do painel). Recarregue a página.</p>';
      } else if (!campos.length) {
        return "";
      }
      return '<section class="ed__cartao' + (g.privado ? " ed__cartao--privado" : "") + (g.largo ? " ed__cartao--largo" : "") +
        '" style="--gc:' + g.cor + ";--gb:" + g.fundo + '"' + (g.id ? ' id="' + g.id + '"' : "") + ">" +
        '<h2 class="ed__cartao-titulo"><span class="ed__icone" aria-hidden="true">' + g.icone + "</span>" + esc(g.titulo) +
          (g.privado ? '<span class="ed__cartao-selo">uso interno</span>' : "") + "</h2>" +
        '<div class="ed__grade">' + (g.nota && !aviso ? '<p class="ed__cartao-nota">' + esc(g.nota) + "</p>" : "") + aviso +
          campos.map(campoHtml).join("") +
          (g.id === "ed-cartao-dono" && !aviso ? '<div class="ed__dono-extra" id="ed-dono-extra"></div>' : "") +
        "</div></section>";
    }).join("");
    desenharDono();
  }

  /* ---- o proprietário: de quem mais ele é dono, e "é outra pessoa" ---------- */
  function desenharDono() {
    var alvo = $("ed-dono-extra");
    if (!alvo) return;
    var dono = privado && privado.proprietario;
    if (donoNovo) {
      alvo.innerHTML = '<p class="ed__cartao-nota">Cadastrando <b>outro proprietário</b> para este imóvel ' +
        "(o de antes continua dono dos imóveis dele).</p>" +
        '<button type="button" class="ed__botao-link" data-dono-acao="desfazer">Desfazer</button>';
      return;
    }
    if (!dono) { alvo.innerHTML = ""; return; }
    var outros = dono.outros_imoveis || [];
    alvo.innerHTML = '<p class="ed__cartao-nota">' +
      (outros.length ? "Também é dono de " + outros.map(function (c) {
          return '<a href="imovel-editar.html?codigo=' + encodeURIComponent(c) + '">' + esc(c) + "</a>";
        }).join(", ") + " — o que mudar aqui vale para todos." : "Proprietário deste imóvel.") +
      '</p><button type="button" class="ed__botao-link" data-dono-acao="outra">É outra pessoa? Trocar o proprietário</button>';
  }

  function trocarDono(acao) {
    donoNovo = acao === "outra";
    ["o:nome", "o:telefone", "o:email", "o:documento", "o:tratamento"].forEach(function (n) {
      var el = inputDe(n);
      if (el) el.value = donoNovo ? "" : (valorGuardado(n) == null ? "" : valorGuardado(n));
    });
    desenharDono();
    atualizarBotao();
    var nome = inputDe("o:nome");
    if (donoNovo && nome) nome.focus();
  }

  // falta o dono? (a parte privada não abriu = não dá para saber, não avisa)
  function faltaDono() {
    if (privado === null) return false;
    if (privado.proprietario && !donoNovo) return false;
    return ["o:nome", "o:telefone"].every(function (n) {
      var el = inputDe(n);
      return !el || !String(el.value || "").trim();
    });
  }

  function irParaDono() {
    var cartao = $("ed-cartao-dono");
    if (!cartao) return;
    cartao.scrollIntoView({ behavior: "smooth", block: "center" });
    cartao.classList.remove("ed__cartao--chamando");
    void cartao.offsetWidth;   // reinicia a animação
    cartao.classList.add("ed__cartao--chamando");
    var nome = inputDe("o:nome");
    if (nome) setTimeout(function () { nome.focus({ preventScroll: true }); }, 350);
  }

  function desenharFotos() {
    var alvo = $("ed-fotos");
    alvo.hidden = false;
    // A BIBLIOTECA DE FOTOS (03/10/2026): o botão abre o popup de subir, reordenar e excluir
    // (assets/js/fotos-biblioteca.js). Sem `data-foto`: clicar nele não abre a foto grande.
    var gerenciar = function (rotulo) {
      return '<button type="button" class="fb-abrir" data-fotos-biblioteca>' + rotulo + "</button>";
    };
    if (!fotos.length) {
      alvo.classList.add("ed__fotos--vazio");
      alvo.innerHTML = '<div class="ed__sem-foto">Este imóvel ainda não tem foto. ' + gerenciar("Subir fotos") + "</div>";
      return;
    }
    alvo.classList.remove("ed__fotos--vazio");
    alvo.innerHTML =
      '<button type="button" class="ed__capa" data-foto="0"><img src="' + esc(fotos[0]) + '" alt="Foto principal"></button>' +
      '<div class="ed__miniaturas">' + fotos.slice(1).map(function (u, k) {
        return '<button type="button" class="ed__mini" data-foto="' + (k + 1) + '"><img loading="lazy" src="' + esc(u) + '" alt=""></button>';
      }).join("") + "</div>" +
      '<div class="ed__fotos-rodape"><span>' + fotos.length + " foto" + (fotos.length > 1 ? "s" : "") +
        " · a primeira é a capa</span>" + gerenciar("Gerenciar fotos") + "</div>";
  }

  /* as fotos do imóvel, na ordem (a capa primeiro). A biblioteca chama de novo quando fecha. */
  function carregarFotos() {
    return fetch(window.API_BASE + "/api/imoveis/" + encodeURIComponent(codigo) + "/fotos")
      .then(function (r) { return r.ok ? r.json() : { fotos: [] }; })
      .then(function (d) {
        var lista = (d.fotos || []).slice().sort(function (a, b) { return (b && b.capa ? 1 : 0) - (a && a.capa ? 1 : 0); });
        fotos = lista.map(function (u) { return typeof u === "string" ? u : (u.url || u.arquivo); }).filter(Boolean);
        desenharFotos();
      })
      .catch(function () { fotos = []; desenharFotos(); });
  }
  window.edFotos = { recarregar: function () { return novo ? Promise.resolve() : carregarFotos(); } };

  /* ---- o que mudou --------------------------------------------------------- */
  function inputDe(nome) { return form.querySelector('[data-campo="' + nome + '"]'); }

  function valorDe(el) {
    if (el.dataset.marcar === "true") {
      return Array.prototype.map.call(el.querySelectorAll("input:checked"), function (i) { return i.value; }).join(", ");
    }
    if (el.dataset.grupos === "true") return itensDoGrupo(el, "imovel").concat(itensDoGrupo(el, "condominio")).join("\n");
    if (el.type === "checkbox") return el.checked;
    if (el.dataset.lista === "true") return el.value.split("\n").map(function (l) { return l.trim(); }).filter(Boolean).join("\n");
    return String(el.value == null ? "" : el.value).trim();
  }

  // o valor que vai para o servidor (vazio vira null: apaga)
  function valorParaEnviar(el, nome) {
    if (el.dataset.marcar === "true") return valorDe(el) || null;
    if (el.dataset.grupos === "true") return valorDe(el) ? valorDe(el).split("\n") : [];
    if (el.type === "checkbox") return el.checked;
    if (el.dataset.lista === "true") return el.value.split("\n").map(function (l) { return l.trim(); }).filter(Boolean);
    var v = String(el.value == null ? "" : el.value).trim();
    if (v === "") return null;
    if (el.dataset.dinheiro === "true") return numeroDoDinheiro(v);     // "750.000" vai como 750000
    if (tipoDe(nome) === "data_br") { var p = v.split("-"); return p[2] + "/" + p[1] + "/" + p[0]; }
    return v;
  }

  function guardarInicial() {
    inicial = {};
    form.querySelectorAll("[data-campo]").forEach(function (el) { inicial[el.dataset.campo] = valorDe(el); });
    var sel = $("ed-situacao");
    if (sel) inicial.status = sel.value;
    condoInicial = seletorCondo ? (seletorCondo.valores()[0] || null) : condoInicial;
  }

  function mudancas() {
    var m = [];
    // desmarca tudo e marca de novo: um mesmo quadro pode ter dois campos (o
    // "o que tem" guarda a lista e, escondido, quais são do condomínio)
    form.querySelectorAll(".ed__campo--mudou").forEach(function (e) { e.classList.remove("ed__campo--mudou"); });
    form.querySelectorAll("[data-campo]").forEach(function (el) {
      var nome = el.dataset.campo;
      // o "no site" que a situação mexeu sozinha é só prévia: não conta nem vai
      if (nome === "publicado_no_site" && !noSiteMexido) return;
      var mudou = valorDe(el) !== inicial[nome];
      var envolve = el.closest ? el.closest("[data-envolve]") : null;
      if (mudou && envolve) envolve.classList.add("ed__campo--mudou");
      if (mudou) m.push(nome);
    });
    var sel = $("ed-situacao");
    if (sel && sel.value !== inicial.status) m.push("status");
    if (seletorCondo) {
      var agora = (seletorCondo.valores()[0] || {}).id || null;
      var antes = (condoInicial || {}).id || null;
      var envolveCondo = form.querySelector('[data-envolve="condominio"]');
      if (envolveCondo) envolveCondo.classList.toggle("ed__campo--mudou", agora !== antes);
      if (agora !== antes) m.push("condo_id");
    }
    return m;
  }

  /* ---- o endereço vem do condomínio escolhido (Tel, 30/09/2026) ------------
     "quando selecionado ele já preenche com os dados de endereço desse
     condomínio". Rua e cidade não existem na tabela `condominios` (ela tem só
     id, nome e bairro): vêm dos imóveis já ligados ao condomínio, pelo valor
     mais frequente -- ver /api/condominios/<id>/endereco.

     SÓ PREENCHE CAMPO VAZIO. Quem já digitou um endereço sabe de algo que o
     cadastro não sabe, e sobrescrever por conta própria apagaria isso em
     silêncio. O que não coube vai escrito na dica, para a pessoa decidir. */
  /* ---- quem já está no condomínio (Pedro, 01/10/2026) ----------------------
     "quando eu crie um imóvel e escolha um condomínio ele já mostre uma listinha
     de outros imóveis no condomínio para eu não acabar criando o imóvel
     duplicado". Aparece na hora em que o condomínio é escolhido, com a unidade
     (torre, apartamento...) de cada um, que é o que diz se é o mesmo imóvel.
     Cada linha abre o imóvel em outra aba, para conferir sem perder o que já foi
     digitado aqui. */
  var pedidoDoCondo = 0;
  function mostrarDoCondominio() {
    var caixa = $("ed-no-condo");
    if (!caixa) return;
    var escolhido = seletorCondo && seletorCondo.valores()[0];
    if (!escolhido || !escolhido.id) { caixa.hidden = true; caixa.innerHTML = ""; return; }
    var meu = ++pedidoDoCondo;   // trocou de condomínio no meio: vale só a última resposta
    caixa.hidden = false;
    caixa.innerHTML = '<p class="ed__no-condo-tit">Procurando os imóveis já cadastrados neste condomínio…</p>';
    fetch("api/imoveis/do-condominio/" + encodeURIComponent(escolhido.id), { credentials: "same-origin" })
      .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
      .then(function (d) {
        if (meu !== pedidoDoCondo) return;
        var itens = (d.itens || []).filter(function (i) { return String(i.codigo) !== String(codigo || ""); });
        if (!itens.length) {
          caixa.innerHTML = '<p class="ed__no-condo-tit ed__no-condo-tit--vazio">Nenhum ' + (novo ? "" : "outro ") +
            "imóvel cadastrado neste condomínio.</p>";
          return;
        }
        var total = Math.max(itens.length, (d.total || 0) - ((d.itens || []).length - itens.length));
        /* FECHADO POR PADRÃO (Pedro, 02/10: "põe em um menu sanfona por padrão fechado... só abre
           quando eu clico em uma setinha do lado"): a linha diz quantos são; a lista abre na seta. */
        caixa.innerHTML =
          '<details class="ed__no-condo-sanfona"><summary class="ed__no-condo-tit"><b>' +
            (total === 1 ? "Já existe 1 imóvel" : "Já existem " + total + " imóveis") +
            " neste condomínio.</b> Confira se não é o mesmo antes de " + (novo ? "cadastrar" : "salvar") + ".</summary>" +
          '<ul class="ed__no-condo-lista">' + itens.map(function (i) {
            var partes = [i.tipo, i.quartos ? i.quartos + " quarto" + (i.quartos > 1 ? "s" : "") : "",
                          i.area ? Math.round(i.area) + " m²" : ""].filter(Boolean).join(", ");
            var miolo = '<span class="ed__no-condo-cod">' + esc(i.codigo) + "</span>" +
              '<span class="ed__no-condo-sit" style="' + corDaSituacao(i.status) + '">' + esc(i.status) + "</span>" +
              '<span class="ed__no-condo-unidade">' + (i.unidade ? esc(i.unidade) : "sem unidade informada") + "</span>" +
              '<span class="ed__no-condo-resto">' + esc([partes, i.valor, i.proprietario].filter(Boolean).join(" · ")) + "</span>";
            return "<li>" + (i.noCatalogo
              ? '<a href="imovel-editar.html?codigo=' + encodeURIComponent(i.codigo) + '" target="_blank" rel="noopener" title="Abrir em outra aba">' + miolo + "</a>"
              : '<span class="ed__no-condo-so-consulta" title="Imóvel só do admin antigo">' + miolo + "</span>") + "</li>";
          }).join("") + "</ul>" +
          (total > itens.length ? '<p class="ed__dica">Mostrando ' + itens.length + " de " + total + ".</p>" : "") +
          "</details>";
      })
      .catch(function () {
        if (meu !== pedidoDoCondo) return;
        caixa.innerHTML = '<p class="ed__no-condo-tit ed__no-condo-tit--vazio">Não consegui buscar os imóveis deste condomínio. ' +
          "Confira na lista de imóveis antes de cadastrar.</p>";
      });
  }

  /* ---- excluir (Pedro, 01/10/2026: "e também uma opção de excluir imóvel") ---
     Linha de imóvel nunca se apaga do banco: excluir é a situação "Excluído",
     que tira do site, da Nay e da lista. Volta pelo filtro Situação > Excluído. */
  function excluirEsteImovel() {
    if (novo || !codigo) return;
    if (!window.confirm("Excluir o imóvel " + codigo + "?\n\n" +
        "Ele sai do site, da Nay e da lista de imóveis.\n" +
        "Fica guardado em Situação > Excluído, de onde dá para trazer de volta.")) return;
    var botao = $("ed-excluir"), status = $("ed-status-salvar");
    if (botao) botao.disabled = true;
    fetch("api/imoveis/" + encodeURIComponent(codigo), {
      method: "PUT", credentials: "same-origin",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status: "Excluído" })
    })
      .then(function (r) {
        return r.json().catch(function () { return {}; }).then(function (d) {
          if (!r.ok) throw new Error((d.detalhes && d.detalhes.join("; ")) || d.erro || ("HTTP " + r.status));
        });
      })
      .then(function () { window.location.href = "imoveis.html"; })
      .catch(function (e) {
        if (botao) botao.disabled = false;
        if (status) {
          status.className = "ed__status-salvar ed__status-salvar--erro";
          status.textContent = "Não consegui excluir: " + e.message;
        }
      });
  }
  document.addEventListener("click", function (e) {
    if (e.target && e.target.id === "ed-excluir") excluirEsteImovel();
  });

  /* ---- o endereço é do condomínio, e não se digita aqui (Pedro, 08/10/2026) --
     "essa parte ... do condomínio não precisa aparecer na parte do cadastro do
     imóvel, porque todo condomínio vai ter endereço fixo. Só ... andar ...
     deixaria na parte do cadastro do imóvel."
     Com o condomínio escolhido E com endereço cadastrado nele, rua, número,
     bairro, cidade, estado e CEP somem do cadastro do imóvel: fica uma linha com
     o endereço e o link para o cadastro do condomínio. Os valores continuam indo
     para o imóvel (o site e a Nay leem do imóvel) -- só não são digitados aqui.
     Ficam o complemento e o andar, que são do imóvel.
     Os campos CONTINUAM aparecendo em dois casos: o condomínio ainda não tem
     endereço (preenche uma vez, o servidor guarda nele), e o imóvel tem um
     endereço DIFERENTE do condomínio (esconder apagaria a divergência da vista). */
  var DO_CONDOMINIO = ["logradouro", "numero", "bairro", "cidade", "estado", "cep"];
  function divergeDoCondominio(e) {
    return DO_CONDOMINIO.some(function (nome) {
      var campo = $("ed-" + nome);
      if (!campo) return false;
      var meu = String(campo.value || "").trim().toLowerCase(), dele = String((e && e[nome]) || "").trim().toLowerCase();
      return !!meu && !!dele && meu !== dele;
    });
  }
  function enderecoDoCondominio(e, diverge) {
    var linha = $("ed-condo-endereco");
    var tem = !!(e && e.logradouro);
    var esconder = tem && !diverge;
    DO_CONDOMINIO.forEach(function (nome) {
      var envolve = form.querySelector('[data-envolve="' + nome + '"]');
      if (envolve) envolve.style.display = esconder ? "none" : "";
    });
    if (!linha) return;
    if (!e || !e.id) { linha.hidden = true; linha.innerHTML = ""; return; }
    var texto = [e.logradouro ? e.logradouro + (e.numero ? ", nº " + e.numero : "") : "", e.bairro,
                 [e.cidade, e.estado].filter(Boolean).join(" - "), e.cep ? "CEP " + e.cep : ""].filter(Boolean).join(" · ");
    var link = '<a href="imoveis.html?condominio=' + encodeURIComponent(e.id) + '" target="_blank" rel="noopener">';
    linha.hidden = false;
    linha.innerHTML = tem
      ? "<b>Endereço do condomínio:</b> " + esc(texto) + ". " +
        (diverge ? "O deste imóvel está diferente — confira abaixo. " : "") + link + "Editar o condomínio</a>"
      : "Este condomínio ainda não tem endereço cadastrado: preencha abaixo uma vez (fica guardado nele) ou " +
        link + "cadastre no condomínio</a>.";
  }
  /* ao abrir um imóvel que já tem condomínio: só confere e esconde, sem mexer em campo nenhum */
  function conferirEnderecoDoCondominio() {
    var escolhido = seletorCondo && seletorCondo.valores()[0];
    if (!escolhido || !escolhido.id) { enderecoDoCondominio(null); return; }
    fetch(window.API_BASE + "/api/condominios/" + encodeURIComponent(escolhido.id) + "/endereco")
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (e) { if (e) enderecoDoCondominio(e, divergeDoCondominio(e)); })
      .catch(function () {});
  }

  function preencherDoCondominio() {
    var escolhido = seletorCondo && seletorCondo.valores()[0];
    if (!escolhido || !escolhido.id) { enderecoDoCondominio(null); return; }
    fetch(window.API_BASE + "/api/condominios/" + encodeURIComponent(escolhido.id) + "/endereco")
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (e) {
        if (!e) return;
        var postos = [], divergentes = [];
        [["logradouro", "a rua"], ["numero", "o número"], ["bairro", "o bairro"], ["cidade", "a cidade"],
         ["estado", "o estado"], ["cep", "o CEP"]].forEach(function (par) {
          var campo = $("ed-" + par[0]), valor = e[par[0]];
          if (!campo) return;
          var atual = String(campo.value || "").trim();
          // o que EU pus do condomínio anterior sai junto com ele (trocou de condomínio, troca o endereço)
          var eraDoOutro = campo.dataset.doCondominio != null && atual === campo.dataset.doCondominio;
          if (!valor) {
            if (eraDoOutro && atual) {
              campo.value = ""; delete campo.dataset.doCondominio;
              campo.dispatchEvent(new Event("input", { bubbles: true }));
            }
            return;
          }
          valor = String(valor);
          if (!atual || eraDoOutro) {
            campo.value = valor;
            campo.dataset.doCondominio = valor;
            campo.dispatchEvent(new Event("input", { bubbles: true }));
            postos.push(par[1]);
          } else if (atual.toLowerCase() !== String(valor).toLowerCase()) {
            divergentes.push(par[1] + ' do condomínio é "' + valor + '"');
          }
        });
        /* A FICHA DO CONDOMÍNIO (Pedro, 30/09: "ao clicar no condomínio no cadastro
           pela OLX ele já preencha os outros campos"): o lazer da ficha vira chips
           em "Características do condomínio" (sem repetir o que já está), e andares
           e elevadores entram só se estiverem vazios. */
        // 11/10: as características do condomínio não viram chips do imóvel; ficam no bloco "Do condomínio"
        var daFicha = [];
        atualizarBotao();
        var dica = $("ed-condo-dica");
        if (!dica) return;
        var recado = [];
        if (daFicha.length) recado.push("Da ficha do condomínio: " + daFicha.join(", ") + ".");
        if (postos.length) {
          recado.push("Preenchi " + postos.join(", ") + " pelo cadastro do condomínio.");
        }
        if (divergentes.length) {
          recado.push("Não mexi no que já estava escrito — mas " + divergentes.join("; ") + ".");
        }
        enderecoDoCondominio(e, divergentes.length > 0);
        var faltam = [["logradouro", "a rua"], ["numero", "o número"], ["cep", "o CEP"]]
          .filter(function (par) { return !e[par[0]]; }).map(function (par) { return par[1]; });
        if (faltam.length) {
          recado.push("Este condomínio ainda não tem " + faltam.join(", ") +
            ": preencha uma vez aqui e fica guardado nele.");
        }
        dica.textContent = recado.join(" ");
      })
      .catch(function () {});
  }

  function atualizarBotao() {
    if (novo) return;
    var m = mudancas();
    var botao = $("ed-salvar");
    botao.disabled = !m.length;
    botao.textContent = m.length ? "Salvar " + m.length + " alteraç" + (m.length > 1 ? "ões" : "ão") : "Salvar";
    if (m.length) {
      $("ed-status-salvar").textContent = "";
      $("ed-status-salvar").className = "ed__status-salvar";
    }
  }

  /* ---- carregar ------------------------------------------------------------ */
  function json(r) { return r.ok ? r.json() : Promise.reject(r.status); }
  Promise.all([
    fetch(window.API_BASE + (novo ? "/api/imoveis/campos" : "/api/imoveis/" + encodeURIComponent(codigo))).then(json),
    // as listas e a parte privada vêm pelo próprio domínio, atrás da senha do painel
    fetch("api/imoveis/valores", { credentials: "same-origin" }).then(json).catch(function () { return {}; }),
    novo ? Promise.resolve({}) :
      fetch("api/imoveis/" + encodeURIComponent(codigo) + "/privado", { credentials: "same-origin" }).then(json).catch(function () { return null; })
  ]).then(function (tres) {
    VALORES = tres[1] || {};
    privado = tres[2];
    if (novo) {
      regras = tres[0];
      item = {};
      document.title = "Novo imóvel — Imob Easy";
      $("ed-titulo").textContent = "Novo imóvel";
      $("ed-sub").textContent = "Nasce como rascunho, fora do site e da Nay. Depois de cadastrar, você escolhe a situação.";
    } else {
      item = tres[0];
      regras = item.campos_editaveis || {};
      document.title = "Imóvel " + item.codigo + " — Imob Easy";
      $("ed-titulo").innerHTML = "Imóvel <span class=\"ed__codigo\">" + esc(item.codigo) + "</span>" +
        (item.condominio_nome ? " · " + esc(item.condominio_nome) : "") +
        (item.e_parceiro ? ' <span class="etiqueta-parceiro">Parceiro</span>' : "");
      $("ed-sub").textContent = [item.tipo, item.bairro, item.quartos ? item.quartos + " quartos" : "",
        item.criado_em ? "cadastrado em " + new Date(item.criado_em).toLocaleDateString("pt-BR") : ""]
        .filter(Boolean).join(" · ");
    }
    condoInicial = item.condo_id ? { id: item.condo_id, nome: item.condominio_nome || ("Condomínio " + item.condo_id) } : null;

    desenharEstado();
    desenharCartoes();
    aplicarRegrasDoTipo();
    carregando.hidden = true;
    form.hidden = false;

    var campoCondo = $("ed-condominio");
    if (campoCondo && window.criarSeletorCondominio) {
      seletorCondo = window.criarSeletorCondominio(campoCondo, {
        multiplo: false,
        aoMudar: function () { atualizarBotao(); preencherDoCondominio(); mostrarDoCondominio(); mostrarFichaDoCondominio(); }
      });
      if (condoInicial) { seletorCondo.definir([condoInicial]); conferirEnderecoDoCondominio(); mostrarFichaDoCondominio(); }
      if (!novo && item.condominio_nome && !item.condo_id) {
        $("ed-condo-dica").textContent = "Hoje está escrito \"" + item.condominio_nome + "\", sem ligação com o cadastro de condomínios — escolha na lista para ligar.";
      }
    }
    guardarInicial();
    atualizarBotao();

    if (!novo) {
      carregarFotos();

      /* o que falta preencher: é o que explica por que a Nay às vezes não acha o imóvel */
      fetch(window.API_BASE + "/api/imoveis/" + encodeURIComponent(codigo) + "/ficha")
        .then(function (r) { return r.ok ? r.json() : null; })
        .then(function (d) {
          if (!d || !d.falta || !d.falta.length) return;
          var el = $("ed-falta");
          el.hidden = false;
          el.innerHTML = "<b>Falta preencher</b>" + d.falta.map(function (f) { return '<span class="ed__falta-item">' + esc(f) + "</span>"; }).join("") +
            '<span class="ed__falta-nota">' + (d.a_nay_pode_oferecer
              ? "A Nay oferece este imóvel — o que falta aqui, ela não sabe responder."
              : "Hoje a Nay não oferece este imóvel.") + "</span>";
        })
        .catch(function () {});
    }
  }).catch(function () {
    carregando.textContent = "Não foi possível carregar este imóvel (código inexistente ou API fora do ar).";
  });

  /* ---- interações ---------------------------------------------------------- */
  /* a máscara do dinheiro: põe os pontos enquanto ele digita e devolve o cursor ao lugar. Na fase de
     captura, para os outros ouvintes (o botão, a porcentagem do cadastro) já lerem o valor arrumado. */
  form.addEventListener("input", function (e) {
    var el = e.target;
    if (!el || !el.dataset || el.dataset.dinheiro !== "true") return;
    var antes = el.value, novo = formatarDinheiro(antes);
    if (novo === antes) return;
    var pos = el.selectionStart == null ? antes.length : el.selectionStart;
    var conta = antes.slice(0, pos).replace(/[^\d,]/g, "").length;   // dígitos (e vírgula) à esquerda do cursor
    el.value = novo;
    var i = 0, vistos = 0;
    while (i < novo.length && vistos < conta) { if (/[\d,]/.test(novo.charAt(i))) vistos++; i++; }
    try { el.setSelectionRange(i, i); } catch (_) { /* campo sem seleção */ }
  }, true);
  form.addEventListener("input", atualizarBotao);
  form.addEventListener("input", function (e) { if (e.target && e.target.dataset && e.target.dataset.campo === "tipo") aplicarRegrasDoTipo(); });

  // o que tem: tirar, passar para o outro grupo, acrescentar (Enter não envia o formulário)
  form.addEventListener("click", function (e) {
    var acaoDono = e.target.closest ? e.target.closest("[data-dono-acao]") : null;
    if (acaoDono) { trocarDono(acaoDono.getAttribute("data-dono-acao")); return; }
    var botao = e.target.closest ? e.target.closest("[data-tirar], [data-mover]") : null;
    if (!botao) return;
    var chip = botao.closest(".ed__chip");
    var caixa = botao.closest("[data-grupos]");
    if (!chip || !caixa) return;
    if (botao.hasAttribute("data-tirar")) chip.remove();
    sincronizarGrupos(caixa);
    atualizarBotao();
  });
  form.addEventListener("keydown", function (e) {
    if (e.key === "Enter" && e.target.hasAttribute && e.target.hasAttribute("data-acrescentar-grupo")) {
      e.preventDefault();
      acrescentarNoGrupo(e.target);
    }
  });

  form.addEventListener("change", function (e) {
    var alvo = e.target;
    if (alvo.dataset && (alvo.dataset.campo === "tipo" || alvo.dataset.campo === "cobertura")) aplicarRegrasDoTipo();
    if (alvo.hasAttribute && alvo.hasAttribute("data-acrescentar-grupo")) {  // escolheu da lista
      acrescentarNoGrupo(alvo);
      return;
    }
    // escolher da lista ACRESCENTA uma linha nas características
    var acrescenta = alvo.getAttribute("data-acrescenta");
    if (acrescenta) {
      var v = String(alvo.value || "").trim();
      var area = inputDe(acrescenta);
      if (v && area) {
        var linhas = area.value.split("\n").map(function (x) { return x.trim(); }).filter(Boolean);
        if (linhas.indexOf(v) < 0) linhas.push(v);
        area.value = linhas.join("\n");
      }
      alvo.value = "";
    }
    if (alvo.id === "ed-situacao") {
      alvo.setAttribute("style", corDaSituacao(alvo.value));
      // mostra já o que o servidor vai fazer com o anúncio, se ele não mexeu no "no site"
      if (!noSiteMexido && $("ed-no-site")) $("ed-no-site").checked = alvo.value === "Disponível" && !eParceiro();
    }
    if (alvo.id === "ed-no-site") noSiteMexido = true;
    // parceiro sai do site (regra de 27/09): a tela mostra já o que o servidor vai fazer
    if (alvo.id === "ed-parceiro" && alvo.checked && !noSiteMexido && $("ed-no-site")) $("ed-no-site").checked = false;
    atualizarNay();
    atualizarBotao();
  });

  // as fotos: clicar abre grande; setas e teclado andam
  var visor = $("ed-visor");
  function abrirFoto(k) {
    if (!fotos.length) return;
    fotoAberta = (k + fotos.length) % fotos.length;
    $("ed-visor-img").src = fotos[fotoAberta];
    $("ed-visor-conta").textContent = (fotoAberta + 1) + " de " + fotos.length;
    if (!visor.open) { if (visor.showModal) visor.showModal(); else visor.setAttribute("open", ""); }
  }
  document.addEventListener("click", function (e) {
    var f = e.target.closest ? e.target.closest("[data-foto]") : null;
    if (f) { abrirFoto(Number(f.getAttribute("data-foto"))); return; }
    var v = e.target.closest ? e.target.closest("[data-visor]") : null;
    if (v) {
      var acao = v.getAttribute("data-visor");
      if (acao === "fechar") visor.close();
      else abrirFoto(fotoAberta + (acao === "prox" ? 1 : -1));
      return;
    }
    if (e.target === visor) visor.close();
  });
  document.addEventListener("keydown", function (e) {
    if (!visor.open) return;
    if (e.key === "ArrowRight") abrirFoto(fotoAberta + 1);
    if (e.key === "ArrowLeft") abrirFoto(fotoAberta - 1);
  });

  window.addEventListener("beforeunload", function (e) {
    if (!novo && mudancas().length) { e.preventDefault(); e.returnValue = ""; }
  });

  /* ---- salvar -------------------------------------------------------------- */
  // O AVISO DO PROPRIETÁRIO (Pedro, 28/09: "quando clica em salvar o imóvel ele
  // notifica para pôr os dados do proprietário"): sem dono, o salvar pergunta
  // antes -- preencher agora ou salvar assim mesmo.
  var avisoDono = $("ed-dono-aviso");
  if (avisoDono) {
    avisoDono.addEventListener("click", function (e) {
      var b = e.target.closest ? e.target.closest("[data-aviso-dono]") : null;
      if (!b) return;
      avisoDono.close();
      if (b.getAttribute("data-aviso-dono") === "salvar") {
        semDonoOk = true;
        if (form.requestSubmit) form.requestSubmit(); else form.dispatchEvent(new Event("submit", { cancelable: true }));
      } else {
        irParaDono();
      }
    });
  }

  form.addEventListener("submit", function (e) {
    e.preventDefault();
    var status = $("ed-status-salvar");
    if (avisoDono && faltaDono() && !semDonoOk) {
      if (avisoDono.showModal) avisoDono.showModal(); else irParaDono();
      return;
    }
    var corpo = {}, extras = {}, priv = {}, dono = {};
    var mudou = novo ? null : mudancas();

    form.querySelectorAll("[data-campo]").forEach(function (el) {
      var nome = el.dataset.campo;
      if (mudou && mudou.indexOf(nome) < 0) return;               // só o que mudou
      if (nome === "publicado_no_site" && !novo && !noSiteMexido) return; // a situação decide
      var v = valorParaEnviar(el, nome);
      if (novo && (v === null || v === false || (Array.isArray(v) && !v.length))) return; // cadastro: só o que tiver
      var f = fonte(nome);
      if (f === "x") extras[nome.slice(2)] = v;
      else if (f === "p") priv[nome.slice(2)] = v;
      else if (f === "o") dono[nome.slice(2)] = v;
      else corpo[nome] = v;
    });
    if (donoNovo) {   // outra pessoa: vai tudo o que está nos campos, não só o que mudou
      ["nome", "telefone", "email", "documento", "tratamento"].forEach(function (k) {
        var el = inputDe("o:" + k);
        if (el) dono[k] = valorParaEnviar(el, "o:" + k);
      });
      corpo.proprietario_novo = true;
    }
    if (Object.keys(extras).length) corpo.extras = extras;
    if (Object.keys(priv).length) corpo.privado = priv;
    if (Object.keys(dono).length) corpo.proprietario = dono;
    var donoAntes = privado && privado.proprietario ? privado.proprietario.id : null;
    var sel = $("ed-situacao");
    if (sel && mudou && mudou.indexOf("status") >= 0) corpo.status = sel.value;
    if (seletorCondo && (novo || (mudou && mudou.indexOf("condo_id") >= 0))) {
      var esc2 = seletorCondo.valores()[0] || null;
      if (novo ? esc2 : true) corpo.condo_id = esc2 ? esc2.id : null;
    }
    if (!novo && !Object.keys(corpo).length) return;

    status.textContent = novo ? "Cadastrando…" : "Salvando…";
    status.className = "ed__status-salvar";
    $("ed-salvar").disabled = true;

    fetch(novo ? "api/imoveis" : "api/imoveis/" + encodeURIComponent(codigo), {
      method: novo ? "POST" : "PUT",
      credentials: "same-origin",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(corpo)
    })
      .then(function (r) {
        if (r.status === 401) return { ok: false, dados: { erro: "a senha do painel não foi aceita — recarregue a página e entre de novo" } };
        return r.json().catch(function () { return {}; }).then(function (d) { return { ok: r.ok, dados: d }; });
      })
      .then(function (res) {
        if (res.ok && novo) {
          var destino = "imovel-editar.html?codigo=" + encodeURIComponent(res.dados.codigo) + "&criado=1";
          // AS FOTOS MONTADAS NO CADASTRO (03/10): sobem agora, na ordem, para o imóvel que acabou de nascer.
          // O imóvel já existe: foto que falhar não desfaz o cadastro, e dá para subir de novo no editor.
          var bib = window.FotosBiblioteca;
          if (bib && bib.pendentes && bib.pendentes()) {
            bib.enviarPendentes(res.dados.codigo, function (n, total) {
              status.textContent = "Cadastrado. Subindo as fotos: " + n + " de " + total + "…";
            }).then(function (r) {
              if (r.falhas.length) {
                window.alert("O imóvel foi cadastrado, mas " + r.falhas.length + (r.falhas.length === 1 ? " foto não subiu" : " fotos não subiram") +
                  ":\n\n" + r.falhas.join("\n") + "\n\nDá para subir de novo em Gerenciar fotos.");
              }
              window.location.href = destino;
            });
            return;
          }
          window.location.href = destino;
          return;
        }
        if (!res.ok) {
          status.textContent = (novo ? "Não cadastrou: " : "Não salvou: ") + ([].concat(res.dados.detalhes || []).join("; ") || res.dados.erro || "erro");
          status.className = "ed__status-salvar ed__status-salvar--erro";
          if (novo) $("ed-salvar").disabled = false; else atualizarBotao();
          return;
        }
        if ("e_parceiro" in corpo) item.e_parceiro = !!corpo.e_parceiro;
        if (corpo.status) {
          item.status = corpo.status;
          // o servidor aplicou a regra do anúncio: a tela passa a mostrar o mesmo
          if (!("publicado_no_site" in corpo) && $("ed-no-site")) $("ed-no-site").checked = corpo.status === "Disponível" && !eParceiro();
        }
        noSiteMexido = false;
        semDonoOk = false;
        var recado = "";
        if ("proprietario" in res.dados) {
          // os campos passam a mostrar o dono como ficou gravado -- se o telefone
          // já era de alguém, o imóvel foi ligado a essa pessoa
          var p = res.dados.proprietario;
          privado.proprietario = p;
          donoNovo = false;
          ["nome", "telefone", "email", "documento", "tratamento"].forEach(function (k) {
            var el = inputDe("o:" + k);
            if (el) el.value = p && p[k] != null ? p[k] : "";
          });
          desenharDono();
          if (p && p.id !== donoAntes && (p.outros_imoveis || []).length) {
            recado = " Esse proprietário já era dono de " + p.outros_imoveis.join(", ") + ": o imóvel foi ligado a ele.";
          }
        }
        guardarInicial();
        atualizarBotao();
        atualizarNay();
        status.textContent = "Salvo às " + new Date().toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" }) + "." + recado;
        status.className = "ed__status-salvar ed__status-salvar--ok";
      })
      .catch(function () {
        status.textContent = "Erro de conexão — nada foi salvo.";
        status.className = "ed__status-salvar ed__status-salvar--erro";
        if (novo) $("ed-salvar").disabled = false; else atualizarBotao();
      });
  });
})();
