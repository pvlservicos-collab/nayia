# Mapa da Nay: onde mexer para cada pedido

O que roda é `producao/funcoes/<nome>(<tipos>).sql` (foto do banco). Toda mudança: migração
numerada em `Arquivos/nai/NNN_*.sql` (a próxima é a maior + 1) → `./scripts/nay ensaio` →
`./scripts/nay backup` → `./scripts/nay aplicar` → commit. Comandos: `./scripts/nay`.

## Achar em segundos (tudo local, da foto)
| quero saber | comando |
|---|---|
| onde está uma frase que ela disse, um nome, uma chave de config | `./scripts/nay onde "frase"` |
| o que uma função faz, quem a chama, que migrações mexeram nela | `./scripts/nay fn nai_x` |
| as colunas de uma tabela, quem pode ler/escrever, que funções gravam nela | `./scripts/nay tabela nome` |
| o que um nó do n8n faz (código, SQL, prompt) | `producao/n8n/<fluxo>/<nó>.js\|.sql\|.prompt.txt` |
| a ordem dos nós, o modelo de cada agente, o que está desativado | `producao/n8n/<fluxo>/_mapa.md` |
| o prompt vivo de cada papel | `producao/prompts/<papel>.md` |
| os textos e números de configuração | `producao/nai_config.tsv` |

Frase seca que ela mandou no WhatsApp quase sempre mora numa FUNÇÃO (`nai_texto_*`), não no
prompt: comece pelo `nay onde`.

## Pedido → função (banco)
| pedido do Tel/Pedro | função viva | migração-exemplo |
|---|---|---|
| a busca por bairro/valor/quartos/mobília, a ordem das perguntas do filtro | `nai_buscar_por_perfil` | 190, 222, 225 |
| a faixa de valor (-20%/+10%) | `nai_oferta_serve`, `nai_pede_mais_em_conta`; chaves `faixa_abaixo_pct`/`faixa_acima_pct` | 225 |
| busca de GENTE x busca da NAY | gente: `nai_disparo_buscar` (não esconde o que não sabemos; entende conjunto/avenida) e `/api/imoveis-lista`. Nay: `nai_oferta_serve` (estrita: mobiliado é só o campo mobília) | 253 |
| o perfil do cliente (elevador etc.) | `nai_perfil_*`, tabela `nai_perfil_cliente` | 223 |
| o que a Nay diz antes de mandar (conferências 1–24) | `nai_conferir_resposta` | 213–216, 224 |
| como a resposta vira mensagens (card, foto, sugestão de visita) | `nai_enfileirar_resposta`, `nai_enfileirar_card` | 224 |
| foto: quando sai | `nai_deve_mandar_fotos`, `nai_menciona_foto`, `nai_pede_envio_do_imovel` | 224 |
| condomínio que não aparece na lista, na aba Condomínios nem no seletor do cadastro | tabela `condominios` (+ `condominio_ficha`); nome escrito no imóvel sem `condo_id` não conta: cadastrar e ligar no molde da 284 | 238, 284 |
| subir, reordenar e excluir as fotos do imóvel (biblioteca do cadastro) | `site_fotos_lista`, `site_foto_adicionar`, `site_fotos_ordenar`, `site_foto_apagar`; marca `imovel_fotos_manual` (a varredura `varrer_fotos.py` e `nai_gravar_fotos_do_site` pulam); API `nay-site-api/fotos_api.py`; tela `assets/js/fotos-biblioteca.js` | 283 |
| casa/apto, venda/locação da conversa | `nai_tipo_pedido`, `nai_tipo_da_conversa`, `nay_negocio_pedido`, `nai_negocio_da_conversa` | 224, 225 |
| paredes na caixa de saída (parceiro, finalidade, 24 h, foto errada) | gatilho `nai_saida_validar`, `nai_conferir_imoveis_da_saida`, `nai_saida_sem_sobras` | 190, 224 |
| quem ela atende / porta / lista de corretores | `nai_deve_atender`, `nai_pode_falar`, `nai_decidir_corretor` | 228 |
| quem responde: Nay, Tel, Rayssa, secretária | `nai_abrir_turno`, `nai_com_a_rayssa`, `nai_tel_com_a_conversa`, `nai_mente_registrar` | 197, 215 |
| botões do CRM (Parar/Voltar, etapas) | `crm_nay_parar`, `crm_nay_voltar`, `crm_etapa_manual` | 212, 228 |
| conjuntos, avenidas, zonas → bairros | `nai_lugar_citado`, `nai_bairros_do_lugar`, `nai_bairros_do_conjunto`; tabelas `nai_lugar_conjunto`, `nai_lugar_avenida`, `bairro_zona`, `imovel_lugar` | 206, 229, 231 |
| imóveis ao redor pelo mapa | `nai_bairros_ao_redor` | 219 |
| card, lista bonita, ficha | `nai_card_do_imovel`, `nai_bloco_oferta`, `nai_ficha_imovel` | 222 |
| status do imóvel (disponível/alugado) | `nai_status_do_imovel` | 214 |
| ele MARCOU o card/lista do grupo (Nay nova) | nay-core: `contexto/resolver_imovel.resolver`, `classificador/atalhos.decidir`, `cerebro/repo.codigos_da_citacao`; listas dos grupos em `envios_lista_grupo` (publicador `_registrar_lista`) | 281, core 013 |
| "os dois", "o primeiro", "entre 2 e 3" (Nay nova) | nay-core: `acoes/varios.py`, `core_conversa.ultima_lista`, `texto.faixa_em_reais`/`teto_na_escala` | core 013 |
| qual fluxo do n8n recebe a mensagem (grupo vai à NAI só para o espelho do CRM) | `nai_quem_atende(text,boolean,text)` | 282 |
| visita (dono, Rayssa, lembretes) | `nai_visita_*`, `nai_agenda_*` | 179, 197 |
| escalar ao Tel, mídia | `nai_escalar`, `nai_avisar_tel`, `nai_parar_chat` | 195 |
| prompt do corretor | tabela `nai_prompt` (versão), `nai_salvar_prompt`; texto em `producao/prompts/corretor.md` | 224 |
| textos fixos (config) | `nai_config` (`producao/nai_config.tsv`), `nai_cfg()` | — |
| casos de teste | `nai_caso` + `nai_rodar_casos()`; `./scripts/nay bateria` | 213+ |
| captação: o dono manda só foto (salva, avisa o Tel, segue a pergunta do cadastro; nunca "não consigo ver") | fluxo da VPS2, nós `Reservar mensagens` (`ja_seguiu_depois_de_foto`), `Juntar mensagens` (`seguirSemFoto`) e `Preparar resposta` (`NAO_VE`); patch em `scripts/madrugada/patch_captacao_imagem_continua.py` | 03/10 |
| etapa da captação escolhida à mão (com Follow-up) | `crm_captacao_etapa_manual`, tabela `captacao_etapa_manual`; abas em `crm_captacao_donos` | 242 |
| quanto o cadastro de um imóvel está preenchido (0 a 100%) | `nai_imovel_pontos`, `vw_imovel_pontuacao`, `crm_imoveis_pontuacao` | 244, 245, 246 |
| o popup de cadastro no card da captação (condomínios com endereço, pré-cadastro, características) | `crm_captacao_cadastro_opcoes`, `crm_condominio_pelo_texto`, `crm_imovel_para_cadastro`, `crm_captacao_dono_cadastro` | 246, 247 |
| o que falta cadastrar e quem termina (aba CADASTRO PENDENTE) | `nai_cadastro_pendente`, `nai_cadastro_importar`, `nai_foto_trocar_url` | 248, 249 |
| visita agendada à mão no CRM (nasce da equipe, a Nay não manda nada) | `crm_visita_agendar`, `crm_visitas_extra`; colunas `nai_visita.duracao_min` / `criada_no_crm_por` | 250 |
| robô de fora (Grok) avisa o Tel, com limite por hora/dia | `crm_avisar_tel`, tabela `aviso_externo`; chaves `aviso_externo_por_hora` / `_por_dia` | 251 |
| o texto do PEDIDO de visita e o "anotei a sua visita" | `nai_texto_confirmar_visita`, `nai_texto_corretor_confirmou` | 255 |
| ela não cita colega (Tel, Rayssa) para quem é de fora | conferência 12 em `nai_conferir_resposta`; chave `aprovador_visita_nome`; prompt do corretor | 255, 256 |
| o Tel recebe as visitas do bloco (manhã/tarde/noite) para ligar ao dono que não respondeu | `nai_visitas_do_bloco_avisar` (dentro do `nai_agenda_tick`), tabela `nai_aviso_bloco`; chaves `resumo_tel_manha` / `_tarde` / `_noite` / `_ligado` | 265 (texto), 266 |
| o imóvel que está NA FRENTE dele (último card/lista da Nay, 2 h): "manda aí", "quero as fotos", "as duas" | `nai_imoveis_na_frente`; passo 3b de `nai_imovel_da_conversa`; gatilho duplo em `nai_deve_mandar_fotos`; conferência 15 | 267 |
| o tipo (casa/apto) que continua de um pedido para o outro | `nai_buscar_por_perfil` (`v_tipo`): mesmo negócio e perfil de até 3 h herdam; negócio diferente pergunta (241) | 241, 267 |
| "que aceite financiamento" num pedido de busca não sobe ao Tel | conferência 05p em `nai_conferir_resposta` | 191, 267 |
| de qual imóvel é a pergunta (nome de condomínio na frase) | `nai_imovel_da_conversa`, `nai_condominio_da_pergunta`, `crm_condominio_pelo_texto` | 240, 257 |
| qual modelo cada agente usa; ligar/desligar a leitura de imagem | nós do n8n (`_mapa.md`); `scripts/madrugada/patch_modelo_n8n.py`, `patch_sem_ler_imagem.py`, `modelo_madrugada.sh` | — |
| bot de fora CONSULTA se um anúncio já é nosso | `crm_imovel_candidatos`, `crm_imovel_vincular_anuncio`, tabela `imovel_anuncio`; `crm/docs/bots/webhook-consulta.md` | 258, 262, 263 |
| bot de fora CADASTRA imóvel para aprovação (aba Imóveis da OLX Bot) | `crm_olx_bot_receber`, tabela `privado.olx_bot_imovel`; rotas `/admin/api/olx-bot` em `olx_api.py`; `captacao-olx-bot.js`; `crm/docs/bots/webhook-cadastro.md` | 260, 261, 264 |
| ligar qualquer bot novo a um webhook nosso | `crm/docs/bots/COMO-LIGAR-O-GROK-A-UM-WEBHOOK.md`; `crm/src/lib/botDeImoveis.ts` | — |
| a chave do contato (telefone com e sem o 9, @lid); erro "nai_fone_br does not exist" no log do Postgres | `nai_chave` chama `public.nai_fone_br` e `public.nay_fone_chave`: função usada em índice tem de qualificar o que chama, porque o autovacuum e o pg_restore rodam sem search_path | 268 |
| a Nay NOVA (nay-core) responde os corretores desde 02/10 14:13: ligar, desligar, canário, "quem respondeu?" | interruptor `core_atende` e `core_atende_so` em `nai_config`; `nai_core_atende`, o trecho 269 de `nai_abrir_turno`, `nai_core_turno`, `nai_core_escalou`; vigia em `scripts/servidor/core_vigia.sql`; o código em `C:\Users\pedro\nay-core` (`docs/CORTE.md`, `docs/PROGRESSO.md`); o pacote e a auditoria em `nay-pacote-completo/nay-pacote/` | 269 |
| endereço, número, CEP, andares, elevadores e características DO CONDOMÍNIO (cadastrados uma vez só) | `condominio_ficha` (logradouro, numero, cidade, estado, cep, lazer); `site_condominio_guardar` grava a partir do cadastro do imóvel (`_guardar_no_condominio` em `app.py`); `/api/condominios/<id>/endereco` devolve (ficha > endereço em texto > o mais comum nos imóveis); o cadastro (`imovel-editar.js`, `CadastroDeImovel.tsx`) preenche ao escolher. O andar saiu da tela e da régua (`nai_imovel_pontos`) | 273 |
| "esse imóvel está Disponível, a Nay oferece?"; rascunho que parece publicado | gatilho `imoveis_a_situacao_manda`: quem não está Disponível nunca fica no site nem disponível; a Nay oferece o que é nosso, Disponível, no site e sem bloqueio (`nay_esta_no_mercado`); a lista do admin mostra "a Nay oferece / NÃO oferece: fora do site, bloqueado" (`imoveis-ux.js`); cópia de antes em `privado.imoveis_antes_274` | 274 |
| a Nay nova não entendeu a resposta à lista, repetiu a lista, respondeu outra coisa sobre o imóvel | no nay-core: `contexto.da_lista` (nome ou ordem da opção), `_mesma_lista` e `qual_da_lista.md`, `lista_ao_redor.md`, `cerebro/ficha.py` (assuntos), `responder_duvida.py` (a frase da ficha é sugestão para a Luna); refazer a conversa sem enviar: `docker exec nay-core python scripts/ensaiar_conversa.py "msg 1" "msg 2"` | — |

## O número caiu? (vigia do WhatsApp, 272)
- "Não chegou" com a caixa dizendo `enviado`: olhe primeiro a conexão. A Z-API aceita o envio mesmo desconectada e
  guarda na fila dela; na volta solta tudo de uma vez (02/10: 68 mensagens em 2 minutos).
- `scripts/servidor/vigia_whatsapp.py` (VPS1, `/root/vigia_whatsapp/`, cron `/etc/cron.d/vigia-whatsapp`, um por número):
  avisa no grupo da equipe PELO OUTRO número quando um cai, guarda e limpa a fila da Z-API enquanto está fora, e na volta
  reenvia devagar (`intervalo_s`, padrão 15 s; só das 7h às 21h; nada com mais de 12 h). Ajustes e segredos em
  `config.json` no servidor, montado por `vigia_whatsapp_instalar.sh`. Log: `/var/log/vigia_whatsapp.log`.
  `python3 vigia_whatsapp.py parceria --situacao` diz o que ele sabe; `--teste` manda uma linha de teste ao grupo.
- Nenhuma função da caixa mudou. O reenvio troca o id da mensagem com `nai_whatsapp_reenviado` (caixa velha, caixa do
  núcleo novo, `mensagem_saida`, `envios`) e no CRM (`zapi_message_id`). Teste sem enviar nada:
  `python scripts/servidor/teste_vigia_whatsapp.py`.

## Site (imobeasy.online)
- API Flask: `nay-site-api/app.py` + `nay-site-api/olx_api.py` (OLX e o cadastro vindo do CRM).
  (`/api/imoveis-lista` filtros; `/api/imoveis/opcoes` listas; `/api/condominios*`).
  Papel de leitura `nay_site_leitura` (GRANT em migração). Deploy: `./scripts/nay site [arquivos do imob-easy]`.
- Admin estático: `imob-easy/admin/*.html` + `imob-easy/assets/js/*.js` (Imóveis: `imoveis-ux.js`; condomínios: `condominios-aba.js`; cadastro pendente: `cadastro-pendente.js`).
  As rotas de `/admin/api/imoveis/...` pedem a senha do /admin -- e também abrem com o segredo do painel dentro do CRM.
  Troque o `?v=` do script no HTML quando mudar o JS.
- A página pública do imóvel (02/10, 271): `imobeasy.online/imovel/<código>-<nome>`. O desenho é do Pedro
  (`Novateladeverimovel.html`, na raiz); `python scripts/montar_pagina_do_imovel.py` gera `imob-easy/imovel.html` trocando
  o script de exemplo por `assets/js/imovel-publico.js`. Mudou o desenho? Gere de novo, não edite o `imovel.html`.
  Dados: `site_imovel_publico(código)` por `/api/imovel-publico/<código>` (só a região: sem rua, número, CEP, andar).
  O nginx serve `/imovel/…` com `scripts/servidor/nginx_pagina_do_imovel.sh`. "Ver Imóvel" do site: `site.js`.
- A tela `/imoveis` (02/10, 275), o link que vai para os corretores acharem e se enviarem imóveis: desenho do Pedro
  (`Telaenviarmovel.html`, na raiz); `python scripts/montar_pagina_de_enviar.py` gera `imob-easy/imoveis.html` trocando o
  script de exemplo por `assets/js/imoveis-enviar.js` (mapa Leaflet no lugar do ilustrativo). Dados:
  `site_imoveis_para_enviar()` por `/api/imoveis-para-enviar` (só o que a Nay oferece; sem rua, número, andar ou dono).
  Abre já num imóvel, numa busca ou em Alugar: `/imoveis?codigo=5717`, `?q=Ponta Negra`, `?alugar`.
- "Me envia" (o corretor digita o próprio WhatsApp): `POST /api/me-envia` → `site_me_envia()` → `nai_disparo_enfileirar`
  (as paredes de sempre: parceiro não sai, 24h por pessoa) com tetos por número, por IP e por dia. Registro em
  `privado.me_envia`; quem mais se envia: `site_me_envia_ranking(dias)` em `/admin/api/me-envia/ranking` (senha do /admin),
  mostrado no topo de `admin/corretores.html` (`assets/js/me-envia-ranking.js`).
  Quem aponta para a página: "Ver Imóvel" do site, a ficha da aba Imóveis do admin/CRM (`imoveis-ux.js`) e o popup do
  imóvel da mensagem no CRM (`ImovelCitado.tsx`).

- admin › Grupos (`admin/grupos.html`, `assets/js/grupos-agenda.js`): a agenda das mensagens de imóvel nos grupos.
  É a GRADE do publicador (`vagas`), que `disparar_grade.sh` posta no minuto marcado; criar/editar/excluir por
  `site_grade_salvar`/`site_grade_excluir`, a semana e a métrica de 6 h por `site_grade_agenda` (rotas `/admin/api/grade*`). 279.
  Cor por grupo, tachinhas e a mensagem em balões de WhatsApp (texto do card, depois a metadinha ou todas as fotos):
  regras por grupo em `site_grade_opcoes` (280: todas_fotos, pisos, lotado); o card e a `colagem` por `/api/imovel-card/<código>`.
  LISTA de imóveis pela tela (285/286): a vaga de lista (categoria, negócio, destino) se cria e se edita ali; o texto é
  automático (montado na hora) ou ESCRITO À MÃO em `vagas.texto_fixo` — o publicador manda esse texto e só tira a linha
  "cod 1234" do imóvel que saiu do ar (`_lista_escrita_a_mao` e `_codigos_no_ar` em `publicador.py`; `disparar_grade.py`
  leva o `texto_fixo`). Prévia: `site_grade_lista_previa` (`/admin/api/grade/lista`).
  Aba MÉTRICAS: `site_grade_metricas(de, ate)` (`/admin/api/grade/metricas`): vezes que cada mensagem saiu, posts, quem
  marcou o post no privado e quem escreveu o código em 6 h; por mensagem da grade e por imóvel. Lista só conta desde a 281.

## CRM (crm.imobeasy.online, Next.js) — `crm/`
- Nay no card do contato: `src/components/Chat/PainelContatoParceria.tsx` + `src/app/api/leads/[id]/nay/route.ts` + `src/lib/nayLeitura.ts`.
- Etapas/abas: `src/lib/etapaDaParceria.ts`, `LeadList.tsx`, `EtapaDoLead.tsx`. Deploy: `./scripts/nay crm src/...` (4 min, ~10 s fora do ar).
- Card da captação: `src/components/Chat/PainelContatoCaptacao.tsx` (+ `EtapaDaCaptacao.tsx`, `CadastroDeImovel.tsx`,
  `src/lib/pontuacaoDoCadastro.ts` -- a régua da 244 repetida em TS só para a barra andar enquanto se digita)
  e rotas `src/app/api/captacao/*`, `src/app/api/leads/[id]/captacao-etapa`. Quem grava o imóvel é a API do site
  (`nay-site-api/olx_api.py`, `/api/captacao/crm/imovel`), com a senha de máquina.
- Banco do CRM: `crm/drizzle/NNNN_*.sql` (tabela nova com `SET LOCAL ROLE crm`).
- Agendar visita (azul): `src/components/Chat/AgendarVisita.tsx` no card do proprietário e no + da agenda (`VisitasAgendadas.tsx`);
  rota `POST /api/parceria/visitas`; o lembrete é um follow-up preso à visita (`src/lib/lembreteDaVisita.ts`, drizzle 0132).
- Aviso de robô ao Tel: `src/app/api/public/aviso-ao-tel/route.ts`; a chave é `AVISO_TEL_CHAVE` no `.env` do servidor (fora do git).
  Pela porta 80 só entra o aviso LACRADO (`src/lib/avisoLacrado.ts`: cifrado + assinado, a chave não viaja) -- a nuvem do bot
  corta HTTPS para cá. A rota da porta 80 é `/docker/traefik/dynamic/aviso-ao-tel.yml` (cópia em `scripts/servidor/`), e o
  redirecionamento 80→443 do Traefik ficou com prioridade 2000000000 para ela poder passar.

- Abrir conversa pela lupa de cima: `src/components/Chat/BuscaDaLista.tsx` pergunta Parceria ou Captação (`/api/leads/abrir`). Quem só responde na captação (a Rayssa): `src/lib/captacaoSoResponde.ts` (lista e aviso) e
  `captacaoSoRespondeServidor.ts` (a parede, chamada em `abrir`, `messages` e `enviar-imovel`).

- Os GRUPOS do número da Parceria (CRM › Grupos, `/chat/grupos`): `src/lib/gruposParceria.ts`, rotas `/api/parceria/grupos/**`,
  `GruposDaParceria.tsx`. Editar só onde o número é admin; a Z-API não dá histórico: as mensagens são guardadas pelo
  webhook do CRM (`/api/webhooks/zapi` → `nai_grupo_guardar`, em `privado.grupo_conversa`). Migrações 277 e 278.

## n8n (fluxo `NAI atendimento locação`, `producao/n8n/`)
- Import só de madrugada (espelho-madrugada). Modelo/memória: pela interface. Ler execuções: sqlite só leitura (scratch `n8nq.sh`).
- O procedimento da madrugada está em `scripts/madrugada/` (cópia em `/root/`): exporta o fluxo vivo, aplica um
  patch de UM nó com contagem exata, reimporta, religa e reinicia, e devolve o backup se os fluxos não voltarem
  ativos. Travas: só 1h–5h de Manaus e só com a Nay parada. Depois do import, rodar `./scripts/foto_producao.sh`.
- Testar sem WhatsApp: espelho `…0001` via `/root/nai_treino_rodar.py` ou POST no webhook `172.16.0.2:5678/webhook/nai-atendimento-locacao`.

## Regras que valem sempre
CLAUDE.md, `Arquivos/REGRAS-E-BUGS.md`, memória em `~/.claude/projects/.../memory/MEMORY.md`.
