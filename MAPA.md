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
| parceria na Nay NOVA (card, foto, lista) e a marca pelo captador "(Parceiro)" | gatilho `core_saida_validar` em `core_saida`; gatilho `imoveis_parceiro_pelo_captador` + `nai_captador_e_parceiro` em `imoveis` | 299 |
| quem ela atende / porta / lista de corretores | `nai_deve_atender`, `nai_pode_falar`, `nai_decidir_corretor` | 228 |
| quem responde: Nay, Tel, Rayssa, secretária | `nai_abrir_turno`, `nai_com_a_rayssa`, `nai_tel_com_a_conversa`, `nai_mente_registrar` | 197, 215 |
| botões do CRM (Parar/Voltar, etapas) | `crm_nay_parar`, `crm_nay_voltar`, `crm_etapa_manual` | 212, 228 |
| conjuntos, avenidas, zonas → bairros | `nai_lugar_citado`, `nai_bairros_do_lugar`, `nai_bairros_do_conjunto`; tabelas `nai_lugar_conjunto`, `nai_lugar_avenida`, `bairro_zona`, `imovel_lugar` | 206, 229, 231 |
| imóveis ao redor pelo mapa | `nai_bairros_ao_redor` | 219 |
| card, lista bonita, ficha | `nai_card_do_imovel`, `nai_bloco_oferta`, `nai_ficha_imovel` | 222 |
| status do imóvel (disponível/alugado) | `nai_status_do_imovel` | 214 |
| ele MARCOU o card/lista do grupo (Nay nova) | nay-core: `contexto/resolver_imovel.resolver`, `classificador/atalhos.decidir`, `cerebro/repo.codigos_da_citacao`; listas dos grupos em `envios_lista_grupo` (publicador `_registrar_lista`) | 281, core 013 |
| imóvel sai do mercado (Vendido, Alugado...) por qualquer caminho, e o aviso no grupo Easy | gatilho `imoveis_aviso_de_saida` → `nay_enfileirar_aviso_de_saida` (SECURITY DEFINER; motivo pela situação) → cron `avisar_saidas.sh`; pelo comando: `nai_marcar_imovel` | 289 |
| o aviso de saída SÓ vai ao grupo Easy depois do SIM do Tel: a Nay pergunta no PV dele e espera (24 h; das 22h às 7h não pergunta) | `nay_saidas_perguntar` (dentro do `nai_agenda_tick`) → tabela `aviso_de_saida_pergunta`; a resposta é comando: `nay_saida_resposta_ler` / `_valida` (em `nai_abrir_turno`) e `nay_saida_responder` (em `nai_comando_tel`); `nay_saidas_a_avisar` só devolve o que tem SIM. Chaves `aviso_saida_pergunta` (nao = avisa sozinha, como antes), `aviso_saida_validade_h`, `aviso_saida_hora_ini` / `_fim`. No publicador, `_liberar_vaga` não posta mais: `_deixar_o_aviso_na_fila` | 334 |
| de quem é cada mensagem que saiu pelo número (a Nay, envio automático ou gente digitando), pelo id | `crm_quem_mandou(text[])` (só leitura; o CRM usa no histórico de atendimento do card) | 290 |
| captação: quem já recebeu mensagem nossa nunca volta para a fila do disparo (a abertura não sai duas vezes) | gatilho `captacao_ja_chamado_nao_volta` em `captacao_leads`; a fila é `status IN ('novo','erro')`, lida pelo nó "Pegar lead novo" do n8n da VPS2 | 291, 291a |
| imóvel já enviado à pessoa não vai de novo sem ela confirmar (sem prazo, card e fotos); e a lista para a tela | nay-core `nay/acoes/ja_enviei.py` + `templates/ja_mandei.md` + `cerebro/repo.py::ja_enviado` (lê `core_saida` e `imovel_enviado_no_dia`); CRM: `crm_imoveis_enviados(text)` → `ImoveisJaEnviados.tsx` no card | 292 (core 014) |
| a Nay nova enxerga na hora o imóvel que saiu ou mudou de valor | nay-core `worker.talvez_refresh` (assinatura de `imoveis` a cada ciclo, antes dos turnos); `acoes/enviar_imovel.fora_do_mercado` (só condomínio de verdade, mesmo negócio) | core 8eb01ed, 07a2f9f |
| número digitado no cadastro ("750.000", piso de venda/aluguel) | site `imovel-editar.js` (`tipo: "dinheiro"`); API `numeros.py` (`numero_br`, `valor_que_nao_existe`) em `app.py` e `olx_api._valor_do_popup` | 03/10 |
| ele marcou a FOTO do post, ou a lista sendo contato novo | `envios_foto` (publicador `_registrar_fotos`, uma linha por foto de grupo ou de corretor); `nay_imovel_da_citacao` (passo 1b) e nay-core `codigos_da_citacao` leem; marcar a LISTA abre a porta em `nai_abrir_turno` (o código do turno não muda). Valor por extenso ("R$ 470 mil") no validador do nay-core: `validador/validar._valores` | 287; core c15711a |
| "os dois", "o primeiro", "entre 2 e 3" (Nay nova) | nay-core: `acoes/varios.py`, `core_conversa.ultima_lista`, `texto.faixa_em_reais`/`teto_na_escala` | core 013 |
| qual fluxo do n8n recebe a mensagem (grupo vai à NAI só para o espelho do CRM) | `nai_quem_atende(text,boolean,text)` | 282 |
| visita (dono, Rayssa, lembretes) | `nai_visita_*`, `nai_agenda_*` | 179, 197 |
| corretor confirma a visita com a NAY NOVA (nay-core): cria a visita e segue o caminho de produção (proprietário, Rayssa, Tel, etapa Visitas do CRM, Nay calada) | `nai_core_visita_confirmada` -> `nai_visita_corretor_confirmou`; quem chama é `nay/saida/visita_velha.py` no nay-core, só no modo real; quem cala é `nai_com_a_rayssa` e quem põe na etapa é `crm_parceria_com_a_rayssa` | 302 |
| gente respondeu à mão: os 30 min valem mesmo quando o corretor cita outro imóvel (a 240 não solta nesse tempo) | `nai_gente_escreveu_ha_pouco` (lê `mensagens` + `crm_quem_mandou`), usada na 240 dentro de `nai_abrir_turno` | 303 |
| instrução do CRM ("instruir a Nay"): quem lê e executa é a NAY NOVA, uma vez só (nay-core `nay/instrucao/`, marca em `core_instrucao_feita`); a velha deixa de ver a que a nova já executou | `nai_core_atende` (sem o WHEN da 303), `nai_instrucao_texto`, `crm_nay_instruir`; prova: `scripts/prova_instrucoes.py` no nay-core | 304 |
| captação só para PROPRIETÁRIO: corretor (lista dos grupos), nome de corretor/imobiliária/parceria e imóvel de parceiro não recebem disparo nem lembrete, e a IA da captação não responde | `captacao_fora_da_campanha`, gatilho `captacao_so_proprietario` em `captacao_leads` (cancela a reserva), `captacao_ainda_e_da_ia` | 308 |
| NAY DE CAPTAÇÃO EM PYTHON (número oficial; hoje só os telefones de `captacao_config.python_telefones`): o modelo que abre a conversa, a resposta, a pergunta da indicação | serviço `nay-captacao` (`nay-captacao/`, systemd no srv1894338, `/root/nay-captacao`); gatilho `captacao_mensagem_do_python` ('Recebido py'), `captacao_e_do_python`, `captacao_indicacao_pendente` / `captacao_indicacao_guardar`, `privado.captacao_indicacao`; o modelo sai por `crm/src/app/api/webhooks/captacao-oficial/route.ts` (`template`); as ferramentas vêm do fluxo do n8n (`nay-captacao/scripts/extrair_ferramentas.py`) | 315, 316 |
| DISPARO do modelo `situacao_imovel_cadastrado_1` para a fila da captação (um por minuto em média): ligar, desligar, ritmo, quem entra e quem fica de fora | `captacao_config.python_disparo` (sim/nao), `python_disparo_seg_min` / `_seg_max`; `captacao_py_fila_do_disparo` (quem pode receber), `captacao_py_disparo_motivo` (por que não sai), `captacao_py_reservar_disparo`, `captacao_py_disparo_placar`; `captacao_nao_disparar` (fora desta rodada, com o motivo), `captacao_motor` (quem recebeu o modelo passa a ser atendido pelo Python); no serviço, `nay-captacao/captacao/worker.py` (`disparador`) e `disparo.py` (`proximo`) | 317 |
| Captação: o imóvel do proprietário JÁ está no cadastro e ele diz "disponível" (só o valor, sem ficha de quartos e fotos) | `captacao_ficha` (tipo `atualizar` + `captacao_leads.codigo` em `imoveis`) | 318 |
| Captação em Python: o que ela anotou e a pergunta em DUAS mensagens; aviso de escalada e de foto ao Tel | `nay-captacao/captacao/resposta.py` (`em_duas_viagens`), `ferramentas.py` (`aviso_da_escalada`), `atender.py` (`_avisar_tel`, por `crm_avisar_tel`) | - |
| Captação: a frase da pergunta da INDICAÇÃO (demanda de fim de ano; "alugar ou vender" conforme o imóvel dele) | `captacao_indicacao_frase(telefone)`; `captacao_indicacao_pendente` devolve a mesma frase; o serviço a entrega ao modelo em `nay-captacao/captacao/atender.py` (`_prompt`) | 320 |
| A RESPOSTA DO DONO NA CAPTAÇÃO ATUALIZA O CADASTRO: situação, valor do aluguel, fim do contrato; o que não entra sozinho; as fotos da conversa no imóvel | `captacao_aplicar_pendentes` / `captacao_aplicar_ao_cadastro`, `captacao_data_do_contrato`, `captacao_fotos_a_puxar`; registro em `captacao_aplicado` (`mudou`, `conferir`); trava `imoveis.travado_motivo` = 'captação: o dono disse ...'; no serviço, `nay-captacao/captacao/cadastro.py` (a cada 5 min) | 321 |
| Cartão de contato que chega pelo número oficial (antes "[Mensagem recebida]"); indicação encaminhada na hora | `crm/src/app/api/webhooks/facebook/route.ts` (`textoDosContatos`); `nay-captacao/captacao/ferramentas.py` (`texto_da_indicacao`) e `atender.py` (`_encaminhar_indicacao`, para `captacao_config.telefone_relatorio`) | - |
| CADASTRO DE CONDOMÍNIO (aba "Adicionar condomínio" em Imóveis, no site e no CRM): criar, editar, endereço fixo, características; o "editar" da aba Condomínios | `site_condominio_salvar(id, dados)`; `nay-site-api/app.py` (`/admin/api/imoveis/condominios` GET/POST/PUT, `/api/condominios/nomes`); `imob-easy/assets/js/condominio-cadastro.js`, `condominios-aba.js`, `admin/imoveis.html` | 322 |
| Campo de condomínio que filtra LETRA A LETRA (cadastro de imóvel, anúncios, cadastro de condomínio) | `imob-easy/assets/js/seletor-condominio.js` (lista inteira lida uma vez de `/api/condominios/nomes`; `window.recarregarCondominios()`); `/api/condominios/sugerir` aceita uma letra | - |
| Cadastro de IMÓVEL: com condomínio que tem endereço, rua/número/bairro/cidade/estado/CEP não aparecem (ficam complemento e andar) | `imob-easy/assets/js/imovel-editar.js` (`enderecoDoCondominio`, `conferirEnderecoDoCondominio`) | - |
| o que vai para a NAY NOVA: todo turno de corretor, inclusive o que fala de visita, o de quem tem visita com a janela vencida e o que traz foto/documento; ficam no caminho antigo só equipe (comandos do Tel), proprietário, acompanhante, teste, a ficha de cadastro aberta e quem tem visita em `confirmando` (a pergunta que o velho já fez, por 24 h) | `nai_core_atende`, bloco 269 de `nai_abrir_turno`; a visita na janela é calada antes por `nai_com_a_rayssa` | 306, 307 |
| resposta curta ("Sim", "Isso, por favor") a uma pergunta da NAY NOVA: a porta reconhece a conversa que o núcleo já está atendendo (`core_saida`), como já fazia com a caixa da velha | `nai_deve_atender` (bloco 305, antes de "MARCOU UMA MENSAGEM") | 305 |
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
| a Agenda do CRM só mostra visita posta por GENTE: a que vem da Nay fica fora (continua valendo para a etapa Visitas e para calar a Nay) e vira a visita da equipe quando alguém agenda à mão o mesmo corretor e imóvel | `crm_visitas`, `crm_visita_agendar`; corte em `nai_config.agenda_sem_visita_da_nay_desde` (apagar a chave volta a mostrar) | 312 |
| agendar no CRM com visita velha ainda aberta do mesmo corretor no mesmo imóvel (índice `nai_visita_uma_aberta`): a que já passou é encerrada, a futura muda de horário | `crm_visita_agendar` | 330 |
| visita com a equipe (`com_rayssa`) cujo dia já passou fecha sozinha e para de contar na aba Visitas agendadas | `nai_visitas_fechar_dia_passado` (dentro do `nai_agenda_tick`); evento `fechada_pelo_dia` | 333 |
| a barrinha do disparo pela API oficial: lista da vez, quantos saíram, quanto falta, quando volta | `crm_captacao_disparo_oficial` (lê `captacao_py_fila_do_disparo`, `captacao_retomada_oficial`, `captacao_motor`) | 331 |
| Cadastro rápido: "O que a IA supõe que é" (o palpite de cada item da fila) | tabela `cadastro_rapido_palpite`; quem escreve é `nay-captacao/captacao/palpite.py`, no cron do preparar | 332 |
| robô de fora (Grok) avisa o Tel, com limite por hora/dia | `crm_avisar_tel`, tabela `aviso_externo`; chaves `aviso_externo_por_hora` / `_por_dia` | 251 |
| o texto do PEDIDO de visita e o "anotei a sua visita" | `nai_texto_confirmar_visita`, `nai_texto_corretor_confirmou` | 255 |
| ela não cita colega (Tel, Rayssa) para quem é de fora | conferência 12 em `nai_conferir_resposta`; chave `aprovador_visita_nome`; prompt do corretor | 255, 256 |
| o Tel recebe as visitas do bloco (manhã/tarde/noite) para ligar ao dono que não respondeu | `nai_visitas_do_bloco_avisar` (dentro do `nai_agenda_tick`), tabela `nai_aviso_bloco`; chaves `resumo_tel_manha` / `_tarde` / `_noite` / `_ligado` | 265 (texto), 266 |
| o imóvel que está NA FRENTE dele (último card/lista da Nay, 2 h): "manda aí", "quero as fotos", "as duas" | `nai_imoveis_na_frente`; passo 3b de `nai_imovel_da_conversa`; gatilho duplo em `nai_deve_mandar_fotos`; conferência 15 | 267 |
| o tipo (casa/apto) que continua de um pedido para o outro | `nai_buscar_por_perfil` (`v_tipo`): mesmo negócio e perfil de até 3 h herdam; negócio diferente pergunta (241) | 241, 267 |
| "que aceite financiamento" num pedido de busca não sobe ao Tel | conferência 05p em `nai_conferir_resposta` | 191, 267 |
| de qual imóvel é a pergunta (nome de condomínio na frase) | `nai_imovel_da_conversa`, `nai_condominio_da_pergunta`, `crm_condominio_pelo_texto` | 240, 257 |
| qual modelo cada agente usa; ligar/desligar a leitura de imagem | nós do n8n (`_mapa.md`); `scripts/madrugada/patch_modelo_n8n.py`, `patch_sem_ler_imagem.py`, `modelo_madrugada.sh` | — |
| bot da OLX CONSULTA um anúncio e recebe "fechar" ou "abordar" + a mensagem para o anunciante | `crm_anuncio_decidir` (decide), `crm_anuncio_mesma_unidade` (é a mesma unidade?), `crm_anuncio_mensagem`; tabelas `privado.anuncio_consulta` (o que foi consultado e respondido) e `anuncio_abordagem_texto` (o texto); os parecidos vêm da `crm_imovel_candidatos`; `crm_imovel_vincular_anuncio`, `imovel_anuncio`; `crm/docs/bots/webhook-consulta.md` | 258, 262, 263, 309, 310, 311 (o texto) |
| bot de fora CADASTRA imóvel para aprovação (aba Imóveis da OLX Bot) | `crm_olx_bot_receber`, tabela `privado.olx_bot_imovel`; rotas `/admin/api/olx-bot` em `olx_api.py`; `captacao-olx-bot.js`; `crm/docs/bots/webhook-cadastro.md` | 260, 261, 264 |
| aba Chat OLX do CRM, botão "Consultas do bot": os anúncios que o bot consultou e a mensagem entregue para cada anunciante | `crm_olx_abordagens` (lê `privado.anuncio_consulta`); `crm/src/app/api/olx/abordagens/route.ts`, `crm/src/components/Chat/ChatOlx.tsx` | 313 |
| CHAT DA OLX no CRM (receber e responder), uma aba por conta (proprietários, corretores) | banco: `privado.olx_conta` / `olx_chat` / `olx_chat_mensagem` e as funções `crm_olx_conta_*`, `crm_olx_chat_*`; CRM: `src/lib/olxChat.ts`, `/api/public/olx-chat/[conta]/[segredo]` (a OLX chama), `/api/olx/conectar`, `/api/olx/oauth`, `/api/olx/chat`, `ChatOlxContas.tsx`; documentação da OLX e desenho em `crm/docs/olx/chat-da-olx.md`; `.env` do CRM: `OLX_CLIENT_ID`, `OLX_CLIENT_SECRET` | 314 |
| menu do CRM: sem Início ("/" e o login abrem na Parceria; o painel de números ficou em `/inicio`), "+ Mais" com Grupos, Corretores e Configurações | `crm/src/components/Shared/Navbar.tsx` (`NAV_ITEMS`, `mais: true`), `crm/src/app/(authenticated)/page.tsx`, `LoginForm.tsx` | — |
| popup "Proprietário do imóvel" (lista de imóveis do site e aba Imóveis do CRM): UM dono, o ligado ao imóvel, nunca procurado pelo nome | `api_imovel_proprietario` em `nay-site-api/imoveis_api.py`; vínculo `imovel_privado.proprietario_id` e, senão, `imoveis.proprietario_id` (o mesmo da 296); `imoveis_api.py` NÃO sobe pelo `./scripts/nay site`: copiar e subir a API | 296 |
| ligar qualquer bot novo a um webhook nosso | `crm/docs/bots/COMO-LIGAR-O-GROK-A-UM-WEBHOOK.md`; `crm/src/lib/botDeImoveis.ts` | — |
| a chave do contato (telefone com e sem o 9, @lid); erro "nai_fone_br does not exist" no log do Postgres | `nai_chave` chama `public.nai_fone_br` e `public.nay_fone_chave`: função usada em índice tem de qualificar o que chama, porque o autovacuum e o pg_restore rodam sem search_path | 268 |
| a Nay NOVA (nay-core) responde os corretores desde 02/10 14:13: ligar, desligar, canário, "quem respondeu?" | interruptor `core_atende` e `core_atende_so` em `nai_config`; `nai_core_atende`, o trecho 269 de `nai_abrir_turno`, `nai_core_turno`, `nai_core_escalou`; vigia em `scripts/servidor/core_vigia.sql`; o código em `C:\Users\pedro\nay-core` (`docs/CORTE.md`, `docs/PROGRESSO.md`); o pacote e a auditoria em `nay-pacote-completo/nay-pacote/` | 269 |
| endereço, número, CEP, andares, elevadores e características DO CONDOMÍNIO (cadastrados uma vez só) | `condominio_ficha` (logradouro, numero, cidade, estado, cep, lazer); `site_condominio_guardar` grava a partir do cadastro do imóvel (`_guardar_no_condominio` em `app.py`); `/api/condominios/<id>/endereco` devolve (ficha > endereço em texto > o mais comum nos imóveis); o cadastro (`imovel-editar.js`, `CadastroDeImovel.tsx`) preenche ao escolher. O andar saiu da tela e da régua (`nai_imovel_pontos`) | 273 |
| "esse imóvel está Disponível, a Nay oferece?"; rascunho que parece publicado | gatilho `imoveis_a_situacao_manda`: quem não está Disponível nunca fica no site nem disponível; a Nay oferece o que é nosso, Disponível, no site e sem bloqueio (`nay_esta_no_mercado`); a lista do admin mostra "a Nay oferece / NÃO oferece: fora do site, bloqueado" (`imoveis-ux.js`); cópia de antes em `privado.imoveis_antes_274` | 274 |
| a Nay nova não entendeu a resposta à lista, repetiu a lista, respondeu outra coisa sobre o imóvel | no nay-core: `contexto.da_lista` (nome ou ordem da opção), `_mesma_lista` e `qual_da_lista.md`, `lista_ao_redor.md`, `cerebro/ficha.py` (assuntos), `responder_duvida.py` (a frase da ficha é sugestão para a Luna); refazer a conversa sem enviar: `docker exec nay-core python scripts/ensaiar_conversa.py "msg 1" "msg 2"` | — |
| Nay nova: "É este imóvel?", "já te enviei", filtros que recomeçam, recado, dúvida sem ficha que vira pendência para o Tel (sem pausa), ERRO do Tel, resumo das 21h | nay-core Alteração 2 (05/10): `validador/coerencia.py`, `acoes/ja_enviei.py`, `estado/filtros.py` (`pedido_novo`), `estado/prazos.py`, `acoes/duvida.py`, `saida/erro_do_tel.py`, `scripts/resumo_diario.py`; tabelas `core_pendencia`, `core_erro`; `nay-core/docs/FLUXO.md` | core 015–018 |
| envio MANUAL de imóvel (Enviar imóvel do site/CRM, Me envia, ENVIA) não chegou, ficou preso, ou "a pausa da Nay parou o envio" | fila `nai_saida` com `papel_destino = 'entrega'`; quem entrega é o serviço `nay-enviador-manual` (srv1894338, systemd; `nay-publicador/enviador_manual.py`, `--ensaio` não manda nada) via `nai_liberar_saida(NULL, true)` → Z-API → `nai_confirmar_envio`. O n8n não vê mais a entrega; a pausa da Nay não vale para ela. `journalctl -u nay-enviador-manual` | 300, 301 |

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
- Cadastro rápido (`cadastro-rapido.js`): a fila vem em ordem de categoria (`palpite` em `/admin/api/imoveis/cadastro-pendente`),
  a lista suspensa entre as setas passa só por uma categoria, e "Ver conversa" abre o chat em popup
  (`/admin/api/imoveis/conversa` → CRM `/api/conversas/por-telefone`; sem o CRM, vai o texto de `captacao_mensagens`).
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
- admin › Nova Nay (`admin/nova-nay.html`, `assets/js/nova-nay.js`, `assets/css/nova-nay.css`): o painel da Nay em Python
  (abas Nós, Treinamento, Logs). A página só mostra o que a API `/painel/*` do nay-core devolve, pela ponte
  `/admin/api/nova-nay/<rota>` em `nay-site-api/app.py` (senha do /admin no navegador; `NAY_CORE_URL` +
  `NAY_CORE_PAINEL_TOKEN` no compose do site, `PAINEL_TOKEN` no .env do nay-core). O código do painel mora no
  nay-core: `nay/painel/`, `painel/fluxo.yaml`, `painel/nos.yaml`, `scripts/gerar_mapa.py` (gera `painel/mapa.json` no deploy).
  LISTA de imóveis pela tela (285/286): a vaga de lista (categoria, negócio, destino) se cria e se edita ali; o texto é
  automático (montado na hora) ou ESCRITO À MÃO em `vagas.texto_fixo` — o publicador manda esse texto e só tira a linha
  "cod 1234" do imóvel que saiu do ar (`_lista_escrita_a_mao` e `_codigos_no_ar` em `publicador.py`; `disparar_grade.py`
  leva o `texto_fixo`). Prévia: `site_grade_lista_previa` (`/admin/api/grade/lista`).
  Aba MÉTRICAS: `site_grade_metricas(de, ate)` (`/admin/api/grade/metricas`): vezes que cada mensagem saiu, posts, quem
  marcou o post no privado e quem escreveu o código em 6 h; por mensagem da grade e por imóvel. Lista só conta desde a 281.

## CRM (crm.imobeasy.online, Next.js) — `crm/`
- Nay no card do contato: `src/components/Chat/PainelContatoParceria.tsx` + `src/app/api/leads/[id]/nay/route.ts` + `src/lib/nayLeitura.ts`.
- Etapas/abas: `src/lib/etapaDaParceria.ts`, `LeadList.tsx`, `EtapaDoLead.tsx`. Deploy: `./scripts/nay crm src/...` (4 min, ~10 s fora do ar).
  Aviso depois de salvar a etapa (03/10): `resultadoDaMudanca` e `abaDaConversa` em `etapaDaParceria.ts` dizem onde a conversa FICOU e por quê;
  a notificação é `AvisoFlutuante.tsx` (card da Parceria e da captação); `marcasDepoisDeMudar` relê as marcas da Nay na hora.
  Pausa de 30 min (mensagem à mão) NÃO é aba Tel: `nayEmPausa`/`comAlguemPelaNay` em `etapaDaParceria.ts`; o motivo mais forte vem de `crm_parceria_marcas` (288).
- Histórico de atendimento no card ("Quem atendeu", 05/10): fila de tags Nay / Tel / Rayssa / Celular / Envio automático em
  `src/components/Chat/HistoricoDeAtendimento.tsx`; a conta em `src/lib/historicoDeAtendimento.ts`; a rota `src/app/api/leads/[id]/atendimento`.
  Quem saiu pelo CRM vem da conta (`actor_member_id`, nomes e cores em `src/lib/atendentes.ts`); o eco, de `crm_quem_mandou` (290) no naydb.
  Nada é gravado: sai das mensagens, 1 leitura ao abrir o card.
- "Não chega mensagem / demora a aparecer" (04/10): a mensagem chega por webhook + conferência (`src/lib/espelhoDaNay.ts`, cron de 10 s);
  a TELA se atualiza por `src/hooks/usePusher.ts` (canal compartilhado conta os usos; refaz a ligação ao voltar para a aba depois de 30 s;
  `usePusherConectado`), `src/contexts/LeadsContext.tsx` (lista: 60 s com a ligação de pé, 8 s sem ela) e `src/hooks/useParceriaMarcas.ts`
  + `/api/parceria/marcas?esperar=1` (a aba de cada pessoa: a leitura de fundo espera a conta nova).
- Aviso no celular (web push, 04/10): QUEM é avisado decide `src/lib/precisaDeGente.ts` (só conversa com pessoa: fora da aba Todos, Nay em
  pausa, captação "Com o Tel" ou fora da campanha; nunca grupo, número nosso, equipe, "ok/obrigado"); QUANTO, `src/lib/push.ts` (um por
  rajada de 10 min, nada se respondemos há menos de 5 min). Cada pessoa liga no próprio aparelho em Configurações › Notificações
  (`usePushNotifications.ts`; no iPhone, antes, "Adicionar à Tela de Início"). Chaves VAPID só no `.env` do servidor: trocá-las desliga todos.
- Celular (04/10): campo com 16 px `!important` (iPhone não dá mais zoom), `.aviso-no-pe` (avisos acima da barra de baixo) e a área de
  toque dos botões pequenos em `src/globals.css`; topo da agenda em `VisitasAgendadas.tsx`; popups com `dvh`.
- Card da captação: `src/components/Chat/PainelContatoCaptacao.tsx` (+ `EtapaDaCaptacao.tsx`, `CadastroDeImovel.tsx`,
  `src/lib/pontuacaoDoCadastro.ts` -- a régua da 244 repetida em TS só para a barra andar enquanto se digita)
  e rotas `src/app/api/captacao/*`, `src/app/api/leads/[id]/captacao-etapa`. Quem grava o imóvel é a API do site
  (`nay-site-api/olx_api.py`, `/api/captacao/crm/imovel`), com a senha de máquina.
- Banco do CRM: `crm/drizzle/NNNN_*.sql` (tabela nova com `SET LOCAL ROLE crm`).
- Agendar visita (azul): `src/components/Chat/AgendarVisita.tsx` no card do proprietário e no + da agenda (`VisitasAgendadas.tsx`);
  rota `POST /api/parceria/visitas`; o lembrete é um follow-up preso à visita (`src/lib/lembreteDaVisita.ts`, drizzle 0132).
  O imóvel da visita por código OU nome do condomínio: `EscolherImovelDaVisita.tsx` + `src/lib/imovelDaVisita.ts` (fonte `/api/imoveis-nay`);
  vale no formulário e no lápis do imóvel do painel da visita. Hora de visita e de follow-up é sempre a de MANAUS:
  `src/lib/fusoDeManaus.ts` (formulários, card, topo da conversa e lista), nunca o relógio do computador. 03/10.
- Aviso de robô ao Tel: `src/app/api/public/aviso-ao-tel/route.ts`; a chave é `AVISO_TEL_CHAVE` no `.env` do servidor (fora do git).
  Pela porta 80 só entra o aviso LACRADO (`src/lib/avisoLacrado.ts`: cifrado + assinado, a chave não viaja) -- a nuvem do bot
  corta HTTPS para cá. A rota da porta 80 é `/docker/traefik/dynamic/aviso-ao-tel.yml` (cópia em `scripts/servidor/`), e o
  redirecionamento 80→443 do Traefik ficou com prioridade 2000000000 para ela poder passar.

- Abrir conversa pela lupa de cima: `src/components/Chat/BuscaDaLista.tsx` pergunta Parceria ou Captação (`/api/leads/abrir`). Quem só responde na captação (a Rayssa): `src/lib/captacaoSoResponde.ts` (lista e aviso) e
  `captacaoSoRespondeServidor.ts` (a parede, chamada em `abrir`, `messages` e `enviar-imovel`).

- Aba Oficial: quem ESCREVEU fica em cima (`ultima_recebida`, de `/api/leads`, antes de `last_activity_at`: o modelo disparado
  não sobe a conversa), filtro só "Não lido" e o nome do dono no cabeçalho (`nomeDoDono` em `LeadListItem.tsx`).
- Aba Oficial: os filtros são os da Captação (`comAbasDaCaptacao` em `LeadList.tsx`) e, em cima, a barrinha do disparo
  (`BarraDoDisparoOficial.tsx` → `/api/captacao/disparo-oficial` → `crm_captacao_disparo_oficial`, 331).
- A conversa de um telefone para quem está FORA do CRM (o Cadastro rápido do site): `/api/conversas/por-telefone`,
  todas as linhas, com a mídia em endereço assinado (`enderecoParaFora`). No CRM o nome do contato é `leads.title`.
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
