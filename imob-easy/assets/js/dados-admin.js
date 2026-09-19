/* ==========================================================================
   Imob Easy — Dados do sistema (estáticos, retirados das telas originais)
   ========================================================================== */

window.DADOS_ADMIN = {

  /* ======================= INÍCIO ======================= */
  indicadores: {
    imoveisDisponiveis: "1194",
    imoveisCadastrados: "5719",
    imoveisAguardandoRevisao: "—",
    corretoresParceiros: "447",
    parceirosAguardando: "26",
    condominiosCadastrados: "659"
  },

  usuariosRascunho: [
    { nome: "Paulo Renner Pereira da Silva", info: "Sem atualização há mais de 3 anos" },
    { nome: "Cíntia Vitoriano", info: "Sem atualização há mais de 3 anos" },
    { nome: "Bruno Sales", info: "Sem atualização há aproximadamente 3 anos" },
    { nome: "Adriana Ataide da Paixão", info: "Sem atualização há aproximadamente 3 anos" },
    { nome: "Jonas Gerbi", info: "Sem atualização há aproximadamente 3 anos" },
    { nome: "Rafaela Nogueira", info: "Sem atualização há aproximadamente 2 anos" },
    { nome: "Márcio Bentes", info: "Sem atualização há quase 2 anos" }
  ],

  imoveisRascunho: [
    { nome: "Imóvel #928", info: "Sem atualização há mais de 3 anos" },
    { nome: "Imóvel #412", info: "Sem atualização há mais de 4 anos" },
    { nome: "Imóvel #4532", info: "Sem atualização há quase 2 anos" },
    { nome: "Imóvel #185", info: "Sem atualização há mais de 5 anos" },
    { nome: "Imóvel #2751", info: "Sem atualização há aproximadamente 3 anos" },
    { nome: "Imóvel #3310", info: "Sem atualização há mais de 2 anos" },
    { nome: "Imóvel #5012", info: "Sem atualização há mais de 1 ano" }
  ],

  imoveisMaisVistos: [
    { nome: "962 - Apartamento - Solar da Praia", info: "1859 visualizações" },
    { nome: "4870 - Casa de condomínio - Via Veneto Residencial", info: "1356 visualizações" },
    { nome: "4993 - Casa de condomínio - Condomínio Itapuranga II", info: "1333 visualizações" },
    { nome: "4890 - Apartamento - Edifício Piedade Gavinho", info: "1249 visualizações" },
    { nome: "5106 - Apartamento - Vision Residence", info: "1112 visualizações" }
  ],

  contratosVencendo: [
    { nome: "Imóvel #292", info: "Aluguel até 02/06/2026" },
    { nome: "Imóvel #1800", info: "Aluguel até 01/01/2024" },
    { nome: "Imóvel #327", info: "Aluguel até 22/05/2024" },
    { nome: "Imóvel #407", info: "Aluguel até 13/06/2023" },
    { nome: "Imóvel #461", info: "Aluguel até 14/07/2026" },
    { nome: "Imóvel #508", info: "Aluguel até 30/08/2026" }
  ],

  /* Condomínios, Imóveis, Anúncios, Proprietários e Clientes saíram daqui
     (revisão 11/09/2026): eram cópias estáticas -- com nome, telefone e CPF
     de gente de verdade num arquivo aberto sem senha -- e as telas agora
     leem tudo da API. */
  imoveisResumo: "",

  /* ======================= AUDITORIA ======================= */
  auditoria: [
    {
      data: "03/09/26", hora: "às 19:22", tipo: "criado",
      titulo: "Imóvel Criado", autor: "Telmário Araújo", link: "Visualizar Imóvel",
      mudancas: []
    },
    {
      data: "03/09/26", hora: "às 19:19", tipo: "alterado",
      titulo: "Imóvel Alterado", autor: "Telmário Araújo", link: "Visualizar Imóvel",
      mudancas: [
        { campo: "Status", de: "Disponível", para: "Alugado" }
      ]
    },
    {
      data: "03/09/26", hora: "às 19:18", tipo: "alterado",
      titulo: "Imóvel Alterado", autor: "Telmário Araújo", link: "Visualizar Imóvel",
      mudancas: [
        { chave: "pt-BR.activerecord.attributes.real_estate.rented_until", para: "2027-09-05" },
        { chave: "pt-BR.activerecord.attributes.real_estate.front_image_id", de: "118215", para: "118265" }
      ]
    },
    {
      data: "03/09/26", hora: "às 17:29", tipo: "alterado",
      titulo: "Imóvel Alterado", autor: "Telmário Araújo", link: "Visualizar Imóvel",
      mudancas: [
        { campo: "Bairro", de: "Flores", para: "Parque 10 de Novembro" },
        { chave: "pt-BR.activerecord.attributes.real_estate.front_image_id", de: "118263", para: "118264" }
      ]
    },
    {
      data: "03/09/26", hora: "às 16:36", tipo: "alterado",
      titulo: "Imóvel Alterado", autor: "Telmário Araújo", link: "Visualizar Imóvel",
      mudancas: [
        { campo: "Valor de venda", de: "R$ 310.000,00", para: "R$ 295.000,00" }
      ]
    },
    {
      data: "03/09/26", hora: "às 15:04", tipo: "alterado",
      titulo: "Imóvel Alterado", autor: "Telmário Araújo", link: "Visualizar Imóvel",
      mudancas: [
        { campo: "Status", de: "Rascunho", para: "Disponível" }
      ]
    }
  ]
};

/* ==========================================================================
   Busca dados reais na API que lê o naydb (banco da VPS).

   De propósito NÃO busca proprietarios/clientes/auditoria: essas telas não
   têm login, e proprietarios/clientes do banco real teriam telefone e
   e-mail de gente de verdade. Ficam com o conteúdo estático de exemplo
   até existir autenticação nessa área -- ver README e a conversa que
   decidiu isso.
   ========================================================================== */
(function () {
  "use strict";
  if (!window.API_BASE) return;

  function buscar(caminho) {
    return fetch(window.API_BASE + caminho)
      .then(function (r) { return r.ok ? r.json() : null; })
      .catch(function () { return null; });
  }

  Promise.all([
    buscar("/api/indicadores"),
    buscar("/api/anuncios"),
    buscar("/api/avisos"),
    buscar("/api/status-sistema"),
    buscar("/api/corretores-ativos"),
  ]).then(function (resultados) {
    var indicadores = resultados[0];
    var anuncios = resultados[1];
    var avisos = resultados[2];
    var statusSistema = resultados[3];
    var corretoresAtivos = resultados[4];
    var algumaCoisaChegou = false;

    if (indicadores) {
      // mantém imoveisAguardandoRevisao do estático -- sem conceito
      // equivalente no banco, não inventamos esse número.
      Object.assign(window.DADOS_ADMIN.indicadores, indicadores);
      algumaCoisaChegou = true;
    }
    if (anuncios) { window.DADOS_ADMIN.anuncios = anuncios; algumaCoisaChegou = true; }
    if (avisos) { window.DADOS_ADMIN.avisos = avisos; algumaCoisaChegou = true; }
    if (statusSistema) { window.DADOS_ADMIN.statusSistema = statusSistema; algumaCoisaChegou = true; }
    if (corretoresAtivos) { window.DADOS_ADMIN.corretoresAtivos = corretoresAtivos; algumaCoisaChegou = true; }

    if (algumaCoisaChegou) {
      document.dispatchEvent(new CustomEvent("dados-admin-atualizados"));
    }
  });
})();
