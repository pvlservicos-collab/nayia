/* ==========================================================================
   Condomínio: o selo "(Google)" na label do campo

   Tel (11/10/2026): "nesses campos poe la quando eu for ver ou editar
   condominio na label (Google) pra eu saber que esse dado veio do google,
   MAS ISSO NÃO PASSA PARA A IA, não quero que ela saiba que o dado veio do
   google, esse dado vem do mesmo lugar que os outros para ela"

   ONDE A SEPARAÇÃO ACONTECE DE VERDADE -- não é aqui, é no banco:
   a Nay lê `condominio_ficha` pelas colunas de sempre (logradouro, torres,
   lazer...). A procedência mora numa coluna A MAIS, `campos_google`, que só
   a rota do admin (atrás de senha) devolve. O `/api/condominios/<id>/ficha`
   público não a manda, e nenhuma função `nai_*` toca nesta tabela. Então
   para a Nay o dado é um dado -- este arquivo é um óculos do Tel, não um
   campo do sistema.

   Quem marca `campos_google` é o gatilho `condominio_google_tg`, comparando
   o valor gravado com a pesquisa (Arquivos/condominio_google.sql). Se o Tel
   reescrever o campo com o dado dele, o selo cai sozinho -- aqui só se
   desenha o que o banco disser.

   Arquivo separado, com um gancho de uma linha dentro do
   `condominio-cadastro.js` (`window.condominioGoogleMarcar`): aquele arquivo
   está sendo mexido por outra frente hoje, e uma linha é o menor encosto
   possível.
   ========================================================================== */
(function () {
  "use strict";

  /* o nome da coluna -> onde ele aparece na tela.
     Os campos de texto têm `label[for="cc-<campo>"]`; as três listas são
     caixinhas, cuja label é o `<p class="cc__secao">` logo antes. */
  var SECAO = { lazer: "lazer", seguranca: "seguranca", comodidades: "comodidades" };

  function selo() {
    var s = document.createElement("span");
    s.className = "cg-selo";
    s.textContent = "(Google)";
    s.title = "Este dado veio de pesquisa na web, não do seu cadastro. " +
              "Reescreva por cima e o selo sai.";
    return s;
  }

  function estilo() {
    if (document.getElementById("cg-estilo")) return;
    var e = document.createElement("style");
    e.id = "cg-estilo";
    e.textContent = [
      ".cg-selo { margin-left: 6px; padding: 1px 6px; border-radius: 999px;",
      "  background: #eaf1fd; color: #1a56a8; border: 1px solid #c7dbf7;",
      "  font-size: 10.5px; font-weight: 600; letter-spacing: .01em;",
      "  vertical-align: middle; white-space: nowrap; cursor: help }"
    ].join("\n");
    document.head.appendChild(e);
  }

  function limpar() {
    var velhos = document.querySelectorAll(".cg-selo");
    for (var i = 0; i < velhos.length; i++) velhos[i].remove();
  }

  /* chamada por `preencher()` do condominio-cadastro.js a cada condomínio
     aberto -- inclusive com lista vazia, que é o caso de limpar os selos do
     condomínio anterior */
  window.condominioGoogleMarcar = function (campos) {
    estilo();
    limpar();
    if (!campos || !campos.length) return;

    for (var i = 0; i < campos.length; i++) {
      var k = campos[i], onde = null;

      if (SECAO[k]) {
        // a caixinha: a label é o <p class="cc__secao"> imediatamente antes
        var grupo = document.querySelector('[data-grupo="' + SECAO[k] + '"]');
        onde = grupo ? grupo.previousElementSibling : null;
        if (onde && !onde.classList.contains("cc__secao")) onde = null;
      } else if (k === "observacao") {
        // a observação não tem <label>: o título da seção faz o papel
        var ta = document.getElementById("cc-observacao");
        onde = ta ? ta.previousElementSibling : null;
        if (onde && !onde.classList.contains("cc__secao")) onde = null;
      } else {
        onde = document.querySelector('label[for="cc-' + k + '"]');
      }

      // campo que a pesquisa trouxe mas a tela não mostra (ex.: `bairro` da
      // ficha, que no formulário é o bairro do condomínio): sem selo, sem erro
      if (onde) onde.appendChild(selo());
    }
  };
})();
