# Imob Easy — réplica estática

Cópia fiel das dez telas enviadas (site público + sistema), em HTML, CSS e JavaScript puro.
Sem build, sem dependências, sem backend. Basta abrir `index.html` no navegador.

## Estrutura

```
imob-easy/
├── index.html              Home pública — "Comece seu sonho pela busca!"
├── comprar.html            Resultados de venda (bairro Adrianópolis)
├── alugar.html             Resultados de locação
│
├── admin/
│   ├── inicio.html         Painel com indicadores e listas
│   ├── condominios.html    Tabela de condomínios
│   ├── imoveis.html        Tabela de imóveis + filtros laterais
│   ├── anuncios.html       Tabela de anúncios
│   ├── proprietarios.html  Cartões + funil
│   ├── clientes.html       Cartões + funil + temperatura
│   └── auditoria.html      Linha do tempo de alterações
│
└── assets/
    ├── css/
    │   ├── tokens.css      Paleta, tipografia, espaçamento, reset
    │   ├── site.css        Site público (roxo)
    │   └── admin.css       Sistema (azul)
    ├── js/
    │   ├── dados-site.js   Conteúdo dos imóveis do site
    │   ├── dados-admin.js  Conteúdo das telas do sistema
    │   ├── site.js         Cartões de imóvel e interações públicas
    │   ├── layout.js       Barra superior, navegação e rodapé do sistema
    │   └── admin.js        Tabelas, cartões, funis e linha do tempo
    └── img/                Logo, banner e fotos de exemplo (SVG)
```

O cabeçalho e o menu do sistema são montados por `layout.js` a partir de uma única definição,
então incluir uma nova tela é questão de criar o HTML e adicionar uma entrada na lista `MENU`.

Todo o conteúdo visível vem de `dados-site.js` e `dados-admin.js`. Trocar textos, valores ou
adicionar registros não exige mexer no HTML.

## Navegação entre as duas áreas

- Site público → sistema: botão **Ir para o Admin**.
- Sistema → site público: botão **Pesquisar Imóveis**.

Não há tela de login, conforme combinado.

## O que mudou em relação aos prints

Posições, ordem dos elementos, rótulos e dados foram mantidos. As mudanças são só de acabamento:

- **Fundo** — o cinza-branco lavado deu lugar a um neutro levemente azulado (`#eef1f6`), com os
  cartões em branco. Isso separa cartão de fundo sem precisar de borda pesada.
- **Contraste de texto** — os cinzas muito claros dos prints (rótulos, telefones, endereços)
  subiram para tons que passam no critério AA de contraste.
- **Hierarquia dos cartões** — borda de 1px mais sombra sutil no lugar da borda dura; a sombra
  aumenta no hover.
- **Estados** — hover, foco e ativo em todos os botões, links, linhas de tabela e itens de menu.
  O foco de teclado é sempre visível.
- **Tabelas** — cabeçalho com fundo próprio, linhas com destaque no hover, coluna de ações
  alinhada à direita e rolagem horizontal em telas estreitas.
- **Funil** — as barras verdes agora são proporcionais ao maior valor da lista e os itens têm
  largura uniforme.
- **Auditoria** — as chaves técnicas (`pt-BR.activerecord...`) ficaram em fonte monoespaçada
  dentro de uma cápsula, separando o dado do sistema do texto legível.
- **Responsivo** — as telas funcionam de 1440px até 360px sem rolagem horizontal.
- **Acessibilidade** — link "pular para o conteúdo", marcos semânticos, `aria-current` na
  navegação, rótulos em todos os campos e `prefers-reduced-motion` respeitado.

## Observações sobre o conteúdo

- **Fotos**: os prints não trazem os arquivos originais, então cada imóvel usa um SVG de
  placeholder (`assets/img/imovel-0X.svg`). Substituir é só trocar o caminho em `dados-site.js`.
- **Logo e banner**: redesenhados como SVG a partir dos prints, já que os originais não estavam
  disponíveis.
- **Clientes**: dois cadastros da tela original eram mensagens de spam com links de phishing.
  Os cartões foram mantidos na mesma posição e com o mesmo formato, mas o texto foi substituído
  por um marcador. Os links não foram copiados.

## Próximos passos sugeridos

Autenticação, telas de cadastro e edição, e a troca dos arquivos JS de dados por chamadas a uma
API — a camada de renderização já está isolada em `site.js` e `admin.js`.
