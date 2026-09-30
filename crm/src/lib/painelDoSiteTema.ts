/**
 * O QUE O CRM ACRESCENTA À PÁGINA DO SITE quando a mostra por dentro (Pedro,
 * 30/09/2026): "retira o menu lá de cima e muda a cor da página para ser igual
 * à escolha do usuário no tema claro e escuro".
 *
 * 1. SEM O MENU DO SITE. O layout.js do site TROCA o marcador
 *    [data-layout-topo] por <header class="barra-topo"> + <nav
 *    class="nav-principal"> (outerHTML), então esconder o marcador não esconde
 *    nada -- foi o erro da primeira versão. Escondem-se as classes finais.
 *
 * 2. O TEMA DO CRM. O CRM guarda o tema na classe `dark` do <html> e em
 *    localStorage('follem-theme'); sem nada guardado, é escuro. O iframe é da
 *    mesma origem: lê a classe do pai e acompanha a troca ao vivo.
 *
 *    Trocar só as variáveis do tokens.css NÃO basta (segunda versão, que saiu
 *    com fundo lilás e tabela branca de letra clara). Três coisas do site
 *    passam por cima das variáveis:
 *      a) o fundo lilás é um `body::before` fixo (o "mesh"), não o --fundo;
 *      b) a "passada de contraste" do admin.css pinta cartão, abas, tabela,
 *         botões e campos com #ffffff escrito, e os :hover com lilás escrito;
 *      c) os scripts (multiseleção, condomínios) injetam <style> com cor fixa.
 *    Por isso, além das variáveis, há a lista das regras que o site escreve
 *    com cor fixa. Se o site ganhar um bloco novo com cor fixa, é aqui que ele
 *    entra -- confira nos dois temas.
 *
 *    A situação do imóvel (.ux-situacao / .ed-situacao) é uma pastilha com a
 *    cor própria de cada status: fica como está nos dois temas, de propósito.
 *
 * Nada do site é reescrito: isto é um <style> e um <script> a mais no <head>.
 */
export const TEMA_DO_CRM = `
<style id="crm-embutido">
.barra-topo,.nav-principal,.rodape-sistema,.pular-conteudo,[data-layout-topo],[data-layout-rodape]{display:none!important}
body::before{display:none!important}
body.admin{background-image:none!important}

/* ---------- claro: os cinzas neutros do CRM, sem o lilás do site ---------- */
html.crm-claro{
  --fundo:#f4f4f2;--fundo-alt:#fafaf9;--grad-fundo:none;
  --superficie-2:#f7f7f5;--borda:#e2e2de;--borda-forte:#cfcfca;
  --texto:#16161a;--texto-medio:#3f3f45;--texto-fraco:#6f6f74}
html.crm-claro body.admin{background:#f4f4f2}
html.crm-claro .tabela thead th{background:#f4f4f2}
html.crm-claro .tabela tbody tr:hover{background:#f7f7f5}

/* ---------- escuro: os pretos do CRM ---------- */
html.crm-escuro{color-scheme:dark;
  --fundo:#0a0a0a;--fundo-alt:#101010;--grad-fundo:none;
  --superficie:#151515;--superficie-solida:#151515;--superficie-2:#1d1d1d;
  --vidro:#151515;--vidro-forte:#1d1d1d;--grad-vidro:#151515;
  --borda:rgba(255,255,255,.10);--borda-forte:rgba(255,255,255,.20);
  --texto:#ededea;--texto-medio:#c8c8c3;--texto-fraco:#9a9a94;
  --roxo:#a78bfa;--roxo-hover:#c4b5fd;--marca-roxo:#c4b5fd;--azul:#a78bfa;--azul-forte:#c4b5fd;--azul-info:#a78bfa;
  --roxo-suave:rgba(139,92,246,.16);--roxo-borda:rgba(139,92,246,.42);
  --azul-claro:rgba(139,92,246,.16);--azul-borda:rgba(139,92,246,.42);
  --rosa-claro:rgba(224,123,196,.14);--lilas:rgba(139,92,246,.30);
  --verde-suave:rgba(92,185,140,.16);--laranja-suave:rgba(232,168,124,.16);--vermelho-suave:rgba(224,132,151,.16);
  --sombra-1:0 1px 2px rgba(0,0,0,.5);--sombra-2:0 8px 22px rgba(0,0,0,.55);--sombra-3:0 20px 50px rgba(0,0,0,.7);
  --brilho-roxo:0 10px 26px rgba(0,0,0,.5);--foco:0 0 0 3px rgba(167,139,250,.35);--foco-roxo:0 0 0 3px rgba(167,139,250,.35)}
html.crm-escuro body.admin{background:#0a0a0a;color:#ededea}

/* as superfícies que o admin.css pinta de #ffffff */
html.crm-escuro .indicador,html.crm-escuro .painel,html.crm-escuro .tabela-envolucro,html.crm-escuro .ficha,
html.crm-escuro .abas,html.crm-escuro .linha-tempo,html.crm-escuro .avisos__coluna,html.crm-escuro .status-recursos,
html.crm-escuro .filtro-vencimento,html.crm-escuro .form-imovel__grupo,html.crm-escuro .form-imovel__rodape,
html.crm-escuro .popup-imovel,html.crm-escuro .menu-mais__lista,html.crm-escuro .cartao{background:#151515}

/* botões secundários e paginação */
html.crm-escuro .btn-neutro,html.crm-escuro .btn-mini,html.crm-escuro .btn-azul-vazado,
html.crm-escuro .filtro-vencimento__grupo button,html.crm-escuro .paginacao-sistema button,
html.crm-escuro .paginacao-sistema a,html.crm-escuro .paginacao-sistema span{background:#1d1d1d;border-color:rgba(255,255,255,.20)}
html.crm-escuro .btn-neutro{color:#ededea}
html.crm-escuro .btn-neutro:hover,html.crm-escuro .btn-mini:hover,html.crm-escuro .btn-azul-vazado:hover,
html.crm-escuro .filtro-vencimento__grupo button:hover,html.crm-escuro .paginacao-sistema a:hover,
html.crm-escuro .paginacao-sistema button:hover,html.crm-escuro .abas__item:hover,html.crm-escuro .painel__item:hover,
html.crm-escuro .busca-lateral button:hover,html.crm-escuro .grupo-opcoes button:hover,
html.crm-escuro .lista-passos__lapis:hover,html.crm-escuro .tabelas-banco__item:hover{background:#282828;border-color:rgba(255,255,255,.28);color:#ededea}

/* o que fica roxo chapado de letra branca (aba ativa, botão principal, página atual) */
html.crm-escuro .abas__item[aria-selected="true"],html.crm-escuro .abas__item[aria-selected="true"]:hover,
html.crm-escuro .filtro-vencimento__grupo button[aria-pressed="true"],html.crm-escuro .filtro-vencimento__grupo button[aria-pressed="true"]:hover,
html.crm-escuro .paginacao-sistema .ativo,html.crm-escuro .grupo-opcoes button[aria-pressed="true"],
html.crm-escuro .etiqueta--azul,html.crm-escuro .selecao--azul{background:#6d28d9;border-color:#6d28d9;color:#fff}
html.crm-escuro .btn-azul:hover{background:#7c3aed;color:#fff}
html.crm-escuro .op[aria-pressed="true"],html.crm-escuro .mapa-filtros .op[aria-pressed="true"],html.crm-escuro .ux-qtd{background:var(--cor,#6d28d9);border-color:var(--cor,#6d28d9);color:#fff}
html.crm-escuro .ed__codigo{background:#6d28d9}

/* campos (a pastilha da situação fica de fora: tem a cor do status) */
html.crm-escuro input:not([type="checkbox"]):not([type="radio"]):not([type="range"]):not([type="file"]),
html.crm-escuro select:not(.ux-situacao):not(.ed-situacao),html.crm-escuro textarea,
html.crm-escuro .entrada:focus,html.crm-escuro .selecao:focus,html.crm-escuro .form-imovel__campo textarea:focus
  {background-color:#1b1b1b;color:#ededea;border-color:rgba(255,255,255,.18)}
html.crm-escuro input::placeholder,html.crm-escuro textarea::placeholder{color:#8d8d88}
html.crm-escuro select:not(.ux-situacao):not(.ed-situacao) option{background:#1b1b1b;color:#ededea}

/* tabela */
html.crm-escuro .tabela thead th{background:#1d1d1d;color:#ededea}
html.crm-escuro .tabela tbody td{border-bottom-color:rgba(255,255,255,.08)}
html.crm-escuro .tabela tbody tr:hover{background:#1d1d1d}
html.crm-escuro .tabela--ux tbody tr:hover td{background:rgba(139,92,246,.12)}
html.crm-escuro .cd-detalhe td{background:#101010}

/* etiquetas, avisos e letras com cor escrita para fundo claro */
html.crm-escuro .etiqueta--verde{color:#8fd9b4;border-color:rgba(92,185,140,.4)}
html.crm-escuro .etiqueta--laranja,html.crm-escuro .etiqueta--alerta,html.crm-escuro .marca-sincronizado{color:#f0b890;border-color:rgba(232,168,124,.4)}
html.crm-escuro .etiqueta--contorno-quente{color:#f2a3a3;border-color:rgba(224,132,151,.45)}
html.crm-escuro .etiqueta--contorno-morno{color:#e8c07a;border-color:rgba(230,199,141,.4)}
html.crm-escuro .etiqueta--cinza-ux,html.crm-escuro .cd-chip--antigo,html.crm-escuro .ed__chip,html.crm-escuro .ed__nay{background:rgba(255,255,255,.10);color:#c8c8c3}
html.crm-escuro .etiqueta--vermelha-ux{background:rgba(224,80,80,.18);color:#f2a3a3}
html.crm-escuro .cd-chip{background:rgba(139,92,246,.18);color:#c4b5fd}
html.crm-escuro .atalho--alerta b,html.crm-escuro .ed__status-salvar--erro,html.crm-escuro .ed__cartao-nota--erro{color:#f28b8b}
html.crm-escuro .atalho--morno b{color:#e8c07a}
html.crm-escuro .ed__status-salvar--ok{color:#8fd9b4}
html.crm-escuro .ux-datas__tit .ux-ico,html.crm-escuro .ed__selo--parceiro{color:#f0b890}
html.crm-escuro .form-imovel__aviso,html.crm-escuro .ed__falta{background:rgba(232,168,124,.12);border-color:rgba(232,168,124,.4);color:#f0b890}
html.crm-escuro .ed__falta-item{background:#1d1d1d;border-color:rgba(232,168,124,.4)}
html.crm-escuro .ed__falta-nota{color:#f0b890}
html.crm-escuro .ed__aviso--ok,html.crm-escuro .ed__nay--sim{background:rgba(92,185,140,.16);color:#8fd9b4}
html.crm-escuro .ed__selo--parceiro{background:rgba(232,168,124,.16)}
/* tela de edição: cada cartão traz a cor do grupo (--gc) e um fundo claro (--gb)
   escritos no próprio elemento; no escuro o fundo vira a cor bem diluída e a
   letra, a mesma cor clareada (--gc-claro) */
html.crm-escuro .ed__cartao{--gc-claro:color-mix(in srgb,var(--gc) 45%,#fff)}
html.crm-escuro .ed__cartao-titulo{background:color-mix(in srgb,var(--gc) 18%,#151515);color:var(--gc-claro)}
html.crm-escuro .ed__cartao-selo,html.crm-escuro .ed__dono-extra a,html.crm-escuro .ed__botao-link,html.crm-escuro .ed__chip-botao:hover{color:var(--gc-claro)}
html.crm-escuro .ed__cartao-selo,html.crm-escuro .ed__marca span{background:#1d1d1d}
html.crm-escuro .ed__marca input:checked + span{background:var(--gc);color:#fff}
html.crm-escuro .ed__chip-botao:hover{background:#282828}
html.crm-escuro .ed__chave-trilho{background:#3a3a3a}
html.crm-escuro .ux-recado{background:#2a2a2a;border:1px solid rgba(255,255,255,.16)}
html.crm-escuro .ux-recado--erro{background:#b42323}

/* véus e listas suspensas */
html.crm-escuro .sobreposicao,html.crm-escuro .ux-veu{background:rgba(0,0,0,.62)}
html.crm-escuro .sel-condo__lista,html.crm-escuro .sel-condo__item{background:#1b1b1b;color:#ededea}
html.crm-escuro .sel-condo__item[aria-selected=true],html.crm-escuro .sel-condo__item:hover,html.crm-escuro .sel-condo__etiqueta{background:rgba(139,92,246,.22)}
html.crm-escuro .sel-condo__etiqueta{border-color:rgba(139,92,246,.5)}
html.crm-escuro .leaflet-tooltip.ux-rotulo-bairro{color:#ede9fe;text-shadow:0 0 3px #000,0 0 3px #000}
</style>
<script>
(function () {
  var raiz = document.documentElement;
  function escuroNoCrm() {
    try { if (window.parent && window.parent !== window) return window.parent.document.documentElement.classList.contains("dark"); } catch (e) {}
    try { return localStorage.getItem("follem-theme") !== "light"; } catch (e) { return true; }
  }
  function aplicar() {
    var escuro = escuroNoCrm();
    raiz.classList.toggle("crm-escuro", escuro);
    raiz.classList.toggle("crm-claro", !escuro);
  }
  aplicar();
  try {
    new MutationObserver(aplicar).observe(window.parent.document.documentElement, { attributes: true, attributeFilter: ["class"] });
  } catch (e) {}
})();
</script>
`
