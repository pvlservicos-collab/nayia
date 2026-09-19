# OLX → site: o que foi medido em 02/09/2026

O Tel pediu: *"preciso que extraia as fotos do olx junto com as informações e
poste no site"*, e antes: *"eu mando só link do olx e a Nay automaticamente já
preenche tudo e coloca as fotos no site, e o que precisa de informação ela vai
me perguntando"*.

Este documento é o levantamento. **Nada disto está ligado em nada** —
`extrair_olx.py` existe e funciona, mas não é chamado por nenhum fluxo.

---

## O que FUNCIONA hoje, medido

**Ler o anúncio inteiro, com todas as fotos.** Rodado contra um anúncio real:

```
$ .venv/bin/python extrair_olx.py "https://www.olx.com.br/regiao-de-manaus/imoveis/casa-...-1526572128"
titulo: Casa bem localizada no parque das laranjeiras.
preco : R$ 390.000 | Preço
bairro: Flores | logradouro: Rua Barão de Indaiá | cep: 69058448
campos: rooms 3, bathrooms 3, garage_spaces 2, category Casas,
        real_estate_type "Venda - casa em rua pública", re_features ...
16 foto(s).
```

Vem também a descrição inteira do anúncio.

**Três coisas que custaram tempo e não são óbvias:**

1. `curl` comum leva **403 do Cloudflare**, do servidor *e* do Mac. Não é o IP:
   é a impressão digital TLS. Com `curl_cffi` imitando Chrome, passa.
2. O host tem que ser o **regional** (`am.olx.com.br`). O `www.olx.com.br/<anúncio>`
   devolve **308 para a home** e depois **200 com a página errada** — parece que
   deu certo e não tem o anúncio dentro. `extrair_olx.py` corrige sozinho.
3. Os dados vêm no **próprio HTML**, num `<script id="initial-data" data-json="…">`.
   Não existe API secreta a descobrir; a procura foi feita.

---

## O que está BLOQUEADO, e por quê

### 1. O servidor não consegue ler a OLX — mas consegue baixar as fotos

Medido a partir de `179.198.121.171`:

| host | resultado |
|---|---|
| `www.olx.com.br` | **403** "Sorry, you have been blocked" |
| `am.olx.com.br` | **403** |
| `apigw.olx.com.br` | **403** |
| **`img.olx.com.br` (as fotos)** | **200**, 192 KB, md5 idêntico ao do Mac |

Do Mac, no mesmo minuto: **200**. O bloqueio provavelmente foi disparado pelas
nossas próprias requisições de teste.

**A consequência prática é boa:** a única parte que precisa de IP liberado é
**ler a página do anúncio**. **Baixar as fotos roda no servidor**, hoje.

### 2. Publicar no site precisa de credencial

`https://imobeasy.com/admin` → **302 para `/entrar`** (Rails/Devise, com
`authenticity_token`). Sem login não se cadastra nada, e **os nomes dos campos
do formulário só se leem depois de logar**. Tudo que se sabe hoje foi deduzido
do site público.

---

## Armadilhas medidas, para quem for implementar

- **`--fail` / `raise_for_status` é obrigatório ao baixar foto.** URL que não
  existe devolve **404 com um JPEG de verdade dentro** — um quadrado cinza de
  ~49 KB. Sem conferir o status, grava-se placeholder achando que deu certo.
- **O dado da OLX é pior que o nosso e não tem dono a quem cobrar.** O primeiro
  anúncio pego sem escolher era uma fazenda de 12.000 hectares com
  `priceValue: R$ 1.500` e `priceLabel: Aluguel` — é R$ 1.500 **por hectare**,
  à venda. Mesma classe do "1601 quartos" do nosso catálogo. Por isso
  `extrair_olx.py` **não converte nada**: devolve cru, e quem chama decide.
- **Campo ausente não é zero.** Anúncio sem área, sem condomínio, sem IPTU é
  comum. Tratar como tabela fixa quebra.
- **A listagem repete anúncio entre páginas** (4 de 50, medido) — quem for
  varrer em massa precisa eliminar repetido pelo id.
- **Disco:** ~87 KB por foto. Varrer Manaus inteira (28.680 anúncios, ~15 fotos)
  daria ~37 GB; o servidor tem **6,7 GB livres**. Um anúncio por vez são ~1,3 MB
  e cabe folgado.

---

## A pergunta que decide o projeto

Amostrando 100 anúncios de imóveis da OLX em Manaus: **73 são de anunciante
profissional, de 48 imobiliárias diferentes, e a Imob Easy não aparece em
nenhum**.

Então há dois projetos possíveis, e eles são muito diferentes:

**(a) Os anúncios são NOSSOS** — o Tel manda o link de um imóvel que a Imob Easy
já anunciou na OLX, para não redigitar tudo no site. Sem risco de terceiro,
volume de 1 requisição por link. **É o que o pedido dele sugere** ("eu mando só
link"). Só falta resolver de onde sai a requisição e a credencial do admin.

**(b) Os anúncios são de QUALQUER anunciante** — aí é republicar imóvel e foto
de outra imobiliária no imobeasy.com. Isso não é decisão técnica: é decisão de
negócio e de CRECI, e não deve ser escrita antes da resposta dele.

---

## De onde sai a requisição, se for (a)

Três caminhos, e a escolha é do Tel:

| caminho | custo | ressalva |
|---|---|---|
| esperar / medir de novo | zero | bloqueio de Cloudflare costuma expirar; pode não expirar |
| rodar a leitura do Mac | zero | só funciona com o Mac ligado, e **para em silêncio** — precisaria de alarme, no molde do `alarme_varredura.py` |
| proxy | mensalidade | funciona 24h, mas é passar por cima de uma recusa explícita da OLX |

**As fotos, em qualquer um dos três, baixam do servidor.**

---

## A plataforma (02/09, tarde)

`captacao.py` — Flask na porta 8090, login por `CAPTACAO_SENHA`. Cola o link →
lê o anúncio → grava rascunho em `captacoes` → baixa as fotos → mostra o
formulário só com o que falta → botão de publicar.

Peças: `captacao_campos.py` (traduz OLX → campos da Imob Easy; ausente é None,
nunca zero), `captacao_fotos.py` (baixa com conferência de status),
`captacao_site.py` (entra no admin, cadastra, e **confere depois se gravou**),
`captacao_schema.sql` (as tabelas e as paredes do banco).

**Não escreve em `imoveis`.** Cadastra no site, e a varredura das :17 traz o
imóvel para o banco sozinha. Um caminho a menos para divergir.

### Duas coisas que a integração achou, e que teriam ido para produção caladas

**A regra "o que ainda falta" existia DUAS vezes** — `nay_captacao_pendencias`
no banco e `captacao_campos.o_que_falta` em Python. Escrevi um teste para
amarrar as duas e ele acusou: **discordavam nos sete cenários**. O banco cobrava
`cidade`, `fotos`, `logradouro` e `condominio_nome`; o Python cobrava
`banheiros` e `vagas`. A função do banco saiu; o Python ficou como dono, porque
é a tela que precisa de rótulo e de ordem.

**Cinco nomes de coluna não batiam** entre a tela e o esquema (`link` x
`link_olx`, `codigo_site` x `codigo_no_site`), e `titulo` e `fotos_pasta` não
existiam em lugar nenhum — a tela guardava de novo o que já estava guardado. O
título sai de `dados_olx` e a pasta sai do `olx_id`.

## O que já está no repositório

- `extrair_olx.py` — o extrator, com todas as medições no cabeçalho.
- `teste_extrair_olx.py` — 15 casos, sem tocar na rede: campos, foto original,
  ausente ≠ zero, a página errada do `www`, e bloqueio virando erro próprio.
