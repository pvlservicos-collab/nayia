# nay-olx: os anúncios da OLX que sobem sozinhos e o chat pronto para a Nay

Pedro, 13/10/2026: "quero fazer tudo no automático, tanto subir anúncio, quanto responder, e futuramente vou criar
uma nay só para responder na olx então já deixa as funções prontas".

## O que é

O serviço que fala com a OLX no lugar de gente. Roda no srv1894338, em `/root/nay-olx`, como o serviço systemd
`nay-olx`. Faz duas coisas, e **as duas nascem desligadas**:

1. **Anúncios.** Sobe para a OLX o imóvel nosso que está Disponível e no site, atualiza quando o cadastro muda e
   remove quando o imóvel deixa de estar Disponível.
2. **Chat.** Tem a fila, o contexto e o envio prontos para a Nay da OLX responder as conversas. A Nay em si ainda
   não existe: o lugar dela é `olx/nay.py`.

A conta da OLX é conectada pelo CRM (Chat OLX › Informações), que guarda o token no banco. A mensagem do cliente
também entra pelo CRM (o webhook que a OLX chama). Este serviço só lê o token e manda.

## Quem decide é o banco (migrações 364 e 365)

| o quê | onde |
|---|---|
| as chaves (ligar, a conta, o teto, o telefone) | `privado.olx_config` |
| o anúncio de um imóvel no formato da OLX, ou por que não vai | `olx_anuncio_montar(codigo, 'venda' \| 'locacao')` |
| o que a próxima rodada faz: remover, atualizar, publicar | `olx_anuncios_plano()` |
| os nossos anúncios e o que a OLX respondeu de cada um | `privado.olx_anuncio`, diário em `privado.olx_anuncio_log` |
| as conversas que esperam a Nay | `olx_nay_fila()` |
| tudo o que ela precisa para responder uma | `olx_nay_contexto(chat)` |
| a tela (CRM › Chat OLX › Anúncios) | `crm_olx_anuncios_painel()`, `crm_olx_config_gravar()` |

O que **nunca** sobe: imóvel de parceiro, bloqueado, fora do nosso site ou que não está Disponível. O que nunca vai
no texto: número da casa, torre, apartamento, o dono, a observação interna e qualquer telefone, e-mail ou link que
esteja dentro da descrição do cadastro. O id do anúncio na OLX é `IE<código>V` (venda) ou `IE<código>L` (locação).

Imóvel sem CEP ou sem foto JPG/PNG/GIF não sobe: aparece em "O que falta" na tela, com o código.

## As chaves

```
SELECT chave, valor, descricao FROM privado.olx_config ORDER BY 1;
```

| chave | nasce | o que faz |
|---|---|---|
| `publicar` | `nao` | `sim` = o serviço manda anúncios à OLX |
| `conta_que_publica` | vazio | `proprietarios` ou `corretores`; sem ela nada sobe |
| `teto` | `5` | quantos anúncios nossos podem estar na OLX ao mesmo tempo |
| `por_rodada` | `10` | quantos vão em cada chamada |
| `telefone`, `mostrar_telefone` | oculto | a OLX exige o telefone; oculto, o contato vem pelo chat |
| `nay_responde` | `nao` | `sim` = a Nay da OLX responde as conversas |
| `nay_silencio_s`, `humano_cala_horas` | 20 s, 24 h | o silêncio antes de responder; quanto a Nay fica quieta depois que gente responde |
| `permissao`, `permissao_detalhe`, `permissao_em` | | o que a OLX respondeu à última importação (gravado pelo serviço) |

As chaves se mudam pela tela do CRM. O serviço relê a cada volta: vale em segundos, sem reiniciar.

## Por que os anúncios ainda não sobem (13/10/2026)

A OLX respondeu `statusCode -6 "Without permission"` para a conta de proprietários. Pela documentação dela, a
importação por API exige **plano profissional habilitado para integração de anúncios**. O chat funciona; anúncio
pela API só depois de a OLX liberar a conta. Com `publicar = sim`, o serviço pergunta de novo a cada 6 horas com a
SONDA (a remoção de um id que não existe: não cria nem apaga nada) e começa sozinho quando a resposta mudar.

**Nenhum anúncio de verdade foi mandado até hoje.** O formato segue a documentação e os testes, mas a primeira
publicação real é a prova: comece com o teto baixo e confira o anúncio na OLX.

## A Nay da OLX (o que falta)

`olx/nay.py`, função `decidir(contexto)`. Hoje devolve `None` (não responde). Quando ela existir, devolve os
balões a mandar e/ou o motivo para passar a conversa para gente. O resto já funciona: a fila, a reserva (uma
conversa é respondida por um de cada vez), o envio pelo chat da OLX, a gravação que aparece no CRM, e a regra de
que **gente respondeu, a Nay cala** naquela conversa.

## Rodar

```
systemctl status nay-olx            journalctl -u nay-olx -n 50
cd /root/nay-olx && set -a && . ./.env && set +a
.venv/bin/python -m olx.anuncios plano            # o que a próxima rodada faria; NÃO fala com a OLX
.venv/bin/python -m olx.anuncios ver 3050 venda   # o anúncio de um imóvel, como iria (ou por que não vai)
.venv/bin/python -m olx.anuncios sonda            # a OLX deixa esta conta publicar? (não publica nada)
.venv/bin/python -m olx.chat fila                 # as conversas que esperam resposta
.venv/bin/python -m olx.chat contexto 12          # o que a Nay recebe para responder a conversa 12
.venv/bin/python -m olx.chat responder 12 "..."   # manda DE VERDADE no chat da OLX
python -m unittest discover -s tests              # as partes puras (roda em qualquer máquina)
```

`.env` (fora do git): `DATABASE_URL` (o mesmo banco do nay-captacao). Opcionais em `olx/config.py`.

Publicar uma versão nova: copiar `olx/` para `/root/nay-olx/olx/` e `systemctl restart nay-olx`.

## Parar

Só os anúncios: `publicar = nao` (o que já está no ar continua no ar; para tirar tudo, deixe o teto em 0 e remova
pela OLX, ou peça a remoção). Só a Nay: `nay_responde = nao`. Tudo: `systemctl stop nay-olx`.

## A API da OLX usada aqui (developers.olx.com.br, lida em 13/10/2026)

| chamada | para quê |
|---|---|
| `PUT /autoupload/import` `{access_token, ad_list}` | inserir, editar (inserir de novo com o mesmo id) e remover |
| `POST /autoupload/import/<token>` `{access_token}` | o que a moderação fez com cada anúncio daquela importação |
| `GET /autoupload/v1/published` (Bearer) | a situação de todos os anúncios da conta, paginado por `page_token` |
| `POST /autoservice/v1/chat/send` (Bearer) | responder uma conversa |

Categorias: 1020 apartamentos, 1040 casas, 1100 terrenos, 1120 comércio e indústria. Parâmetro opcional vazio ou
zero faz a importação falhar, e um anúncio que falha cancela a importação inteira: o que o cadastro não sabe não é
mandado, e quem falha fica 6 horas fora das rodadas.
