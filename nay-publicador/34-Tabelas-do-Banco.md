# O que é cada tabela do `naydb`

Levantado em 04/09/2026, com as contagens do dia. Serve para responder
"posso mexer nisso?" sem abrir o código.

**Onde mora:** PostgreSQL 16 no container `nay-postgres`, servidor
**srv1894338** (179.198.121.171), volume `postgres_nay_pgdata`. Backup diário
às 03h05 em `/root/backups-banco` (ver `backup_banco.sh`).

---

## 1. O catálogo — veio da Imob Easy

| tabela | linhas | o que é |
|---|---|---|
| `imoveis` | 1.217 | Os imóveis, 44 colunas. **Atualiza sozinha de hora em hora** pela varredura do site (`sincronizar_catalogo.py`, aos :17). Nunca se apaga linha daqui. |
| `imovel_fotos` | 16.979 | As fotos de cada imóvel, em ordem, com a capa marcada. É daqui que a Nay responde "tem imagens?" — não do site. |
| `proprietarios` | 5.612 | Nome, telefone, e-mail. Da importação de agosto: **não atualiza sozinha**. Sem CPF nem RG, de propósito. |
| `imovel_privado` | 1.172 | O que é NOSSO sobre o imóvel e **não vai para o site**: quem é o proprietário, se ele acompanha a visita, e como a visita funciona naquele imóvel. Fora do alcance das ferramentas de corretor. |
| `condominios` | 361 | Os nomes de condomínio, da importação. |
| `imoveis_backup_20260828` | 1.201 | Foto do catálogo antes de uma mudança grande. Arquivo morto — pode ser descartado quando o backup diário tiver histórico. |
| `condominio_taxas` | **0** | Criada e nunca preenchida. |
| `contratos_locacao` | **0** | Criada e nunca preenchida. Se for populada, dá para avisar de vencimento. |

## 2. A conversa no WhatsApp

| tabela | linhas | o que é |
|---|---|---|
| `mensagens` | 4.292 | **Tudo que chega.** É aqui que se lê a conversa real antes de propor qualquer coisa. |
| `mensagem_saida` | 75 | **Tudo que sai**, com o ID da mensagem. É o que faz a citação resolver: o corretor marca um card e a Nay sabe qual imóvel é. Começou em 01/09. |
| `nay_memoria` | 2.758 | A memória de conversa do agente — janela de 40 mensagens, por telefone. Quando ela "inventa" algo, é o primeiro lugar a olhar. |
| `corretores` | 1.053 | Quem ela atende. Fora daqui, ninguém recebe nada — o Tel está nesta lista, e tirá-lo derruba os comandos dele. |
| `identidade_lid` | 40 | O `@lid` que o WhatsApp manda no lugar do telefone → telefone real. Aprende sozinha pelo nome. |
| `equipe` | 1 | O Fernando, que acompanha visita. Fica FORA de `corretores` de propósito, senão o porteiro o atenderia como corretor. |
| `contato_corretor` | 3 | Registro de quando falamos com um corretor e por quê — usado para não repetir contato. |

## 3. Os disparos nos grupos

| tabela | linhas | o que é |
|---|---|---|
| `grupos` | 15 | Os grupos de WhatsApp, com o que cada um aceita (venda, locação, todas as fotos) e o teto por dia. |
| `vagas` | 9 | **A grade de postagem**: horário, recorrência e quais códigos. É o que o `Nay posta o X todo dia às 14h` cria. |
| `envios` | 441 | Toda vez que um imóvel foi enviado — para grupo ou para corretor — com o ID da mensagem. Alimenta a citação e os lembretes. |
| `easy_publicacoes` | 26 | Quais códigos já foram ao grupo Easy. É a reserva atômica que impede postar o mesmo duas vezes. |
| `entrega_pendente` | 4 | O imóvel que ela prometeu e ainda não mandou. Um cron entrega. |
| `lembrete` | 1 | A cobrança de retorno ao corretor ("conseguiu falar com o cliente?"). |
| `publicacoes` | **0** | Não usada por nada no projeto. |
| `fila_publicacao` | **0** | Não usada por nada no projeto. |

## 4. Escalação e aprendizado

| tabela | linhas | o que é |
|---|---|---|
| `pendencias` | 35 | O que o corretor perguntou e a Nay não sabia. O `RESPOSTA <id>` do Tel responde daqui — e a resposta fica guardada e é **reusada**. |
| `pendencia_interessado` | 12 | Quem mais perguntou a mesma coisa e ficou esperando. Ao responder, todos recebem. |
| `resposta_a_entregar` | 0 | Fila de entrega dessas respostas. Vazia = nada pendente. |
| `pendencia_rascunho` | 0 | O rascunho do "responder conversando" (o Tel escreve a resposta sem digitar `RESPOSTA 17`). |
| `escalacoes` | 35 | O histórico do que foi acionado ao Tel. |
| `imovel_conhecimento` | 1 | O que o Tel já explicou de um imóvel, por assunto (quitação, entrada, condições). Ela consulta ANTES de escalar. |
| `regras` | 48 | **As regras que a Nay segue.** É desta tabela que o prompt dela é gerado (`sincronizar_regras.py`). Mudou aqui, roda o gerador, importa o fluxo. |

## 5. Bairros e região

| tabela | linhas | o que é |
|---|---|---|
| `bairro_zona` | 56 | A zona de cada bairro de Manaus. **Precisa da conferência do Tel** — é o que impede oferecer Ponta Negra a quem procura no Parque 10. |
| `bairro_vizinho` | 24 | Quais bairros fazem divisa, para os casos que a zona não pega. |

## 6. A captação do OLX (pronta, não ligada)

| tabela | linhas | o que é |
|---|---|---|
| `captacoes` | 0 | O rascunho do imóvel captado: o link, o que veio do anúncio, o que o Tel preencheu, e o status. |
| `captacao_fotos` | 0 | As fotos do anúncio, com o que já foi baixado. |

Zeradas porque a plataforma ainda **não está em produção** — falta a
credencial do admin da Imob Easy. Ver `33-OLX-Para-o-Site.md`.

## 7. Configuração e diagnóstico

| tabela | linhas | o que é |
|---|---|---|
| `config` | 7 | As chaves gerais, mudadas com um UPDATE e valendo na hora: `atendimento_pausado` (a pausa), `unidade_nivel`, `varredura_rodou_em`, `pendencia_horas_para_cobrar`, `imovel_em_foco_horas`. |
| `imagem_estrutura` | 1.341 | Captura da estrutura crua do que a Z-API manda. Foi lendo isto que se descobriu o campo da citação (`referenceMessageId`). Diagnóstico. |
| `payload_estrutura` | **0** | Criada para isso e nunca usada — quem recebe a captura é a `imagem_estrutura`. |
| `escalacoes_arquivo_20260827`, `pendencias_arquivo_20260827`, `regras_arquivo_20260828`, `regras_arquivo_20260828b` | 8 / 3 / 5 / 5 | Arquivos de antes de mudanças grandes. Histórico. |

## 8. NÃO são deste projeto

| tabela | linhas | o que é |
|---|---|---|
| `site_listas` | 0 | Nenhum arquivo deste repositório menciona. |
| `site_proximos_passos` | 5 | Idem. O conteúdo fala de "telas", "login no admin", "Avisos" e "endereço de API" — é de outra frente, criada em 04/09. |
| `visitas` | 0 | Agenda de visita com confirmação de proprietário, Fernando e corretor. Desenho antigo, **nunca usado**: quem decide visita hoje é `nay_avaliar_visita` + `imovel_privado`. |

---

## Resumo do que está morto

Zeradas e sem ninguém lendo: `publicacoes`, `fila_publicacao`,
`payload_estrutura`, `condominio_taxas`, `visitas`, `site_listas`. Mais os
quatro `*_arquivo_*` e o `imoveis_backup_20260828`, que são histórico.

Nenhuma delas atrapalha nada, e apagar tabela é operação sem volta — ficam
como estão até alguém precisar do espaço (o banco tem 24 MB e o disco tem
90 GB livres).
