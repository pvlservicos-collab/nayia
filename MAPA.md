# Mapa da Nay: onde mexer para cada pedido

O que roda é `producao/funcoes/<nome>(<tipos>).sql` (foto do banco). Toda mudança: migração
numerada em `Arquivos/nai/NNN_*.sql` (a próxima é a maior + 1) → `./scripts/nay ensaio` →
`./scripts/nay backup` → `./scripts/nay aplicar` → commit. Comandos: `./scripts/nay`.

## Pedido → função (banco)
| pedido do Tel/Pedro | função viva | migração-exemplo |
|---|---|---|
| a busca por bairro/valor/quartos/mobília, a ordem das perguntas do filtro | `nai_buscar_por_perfil` | 190, 222, 225 |
| a faixa de valor (-20%/+10%) | `nai_oferta_serve`, `nai_pede_mais_em_conta`; chaves `faixa_abaixo_pct`/`faixa_acima_pct` | 225 |
| o perfil do cliente (elevador etc.) | `nai_perfil_*`, tabela `nai_perfil_cliente` | 223 |
| o que a Nay diz antes de mandar (conferências 1–24) | `nai_conferir_resposta` | 213–216, 224 |
| como a resposta vira mensagens (card, foto, sugestão de visita) | `nai_enfileirar_resposta`, `nai_enfileirar_card` | 224 |
| foto: quando sai | `nai_deve_mandar_fotos`, `nai_menciona_foto`, `nai_pede_envio_do_imovel` | 224 |
| casa/apto, venda/locação da conversa | `nai_tipo_pedido`, `nai_tipo_da_conversa`, `nay_negocio_pedido`, `nai_negocio_da_conversa` | 224, 225 |
| paredes na caixa de saída (parceiro, finalidade, 24 h, foto errada) | gatilho `nai_saida_validar`, `nai_conferir_imoveis_da_saida`, `nai_saida_sem_sobras` | 190, 224 |
| quem ela atende / porta / lista de corretores | `nai_deve_atender`, `nai_pode_falar`, `nai_decidir_corretor` | 228 |
| quem responde: Nay, Tel, Rayssa, secretária | `nai_abrir_turno`, `nai_com_a_rayssa`, `nai_tel_com_a_conversa`, `nai_mente_registrar` | 197, 215 |
| botões do CRM (Parar/Voltar, etapas) | `crm_nay_parar`, `crm_nay_voltar`, `crm_etapa_manual` | 212, 228 |
| conjuntos, avenidas, zonas → bairros | `nai_lugar_citado`, `nai_bairros_do_lugar`, `nai_bairros_do_conjunto`; tabelas `nai_lugar_conjunto`, `nai_lugar_avenida`, `bairro_zona`, `imovel_lugar` | 206, 229, 231 |
| imóveis ao redor pelo mapa | `nai_bairros_ao_redor` | 219 |
| card, lista bonita, ficha | `nai_card_do_imovel`, `nai_bloco_oferta`, `nai_ficha_imovel` | 222 |
| status do imóvel (disponível/alugado) | `nai_status_do_imovel` | 214 |
| visita (dono, Rayssa, lembretes) | `nai_visita_*`, `nai_agenda_*` | 179, 197 |
| escalar ao Tel, mídia | `nai_escalar`, `nai_avisar_tel`, `nai_parar_chat` | 195 |
| prompt do corretor | tabela `nai_prompt` (versão), `nai_salvar_prompt`; texto em `producao/prompts/corretor.md` | 224 |
| textos fixos (config) | `nai_config` (`producao/nai_config.tsv`), `nai_cfg()` | — |
| casos de teste | `nai_caso` + `nai_rodar_casos()`; `./scripts/nay bateria` | 213+ |
| etapa da captação escolhida à mão (com Follow-up) | `crm_captacao_etapa_manual`, tabela `captacao_etapa_manual`; abas em `crm_captacao_donos` | 242 |
| quanto o cadastro de um imóvel está preenchido (0 a 100%) | `nai_imovel_pontos`, `vw_imovel_pontuacao`, `crm_imoveis_pontuacao` | 244, 245, 246 |
| o popup de cadastro no card da captação (condomínios com endereço, pré-cadastro, características) | `crm_captacao_cadastro_opcoes`, `crm_condominio_pelo_texto`, `crm_imovel_para_cadastro`, `crm_captacao_dono_cadastro` | 246, 247 |
| o que falta cadastrar e quem termina (aba CADASTRO PENDENTE) | `nai_cadastro_pendente`, `nai_cadastro_importar`, `nai_foto_trocar_url` | 248, 249 |
| visita agendada à mão no CRM (nasce da equipe, a Nay não manda nada) | `crm_visita_agendar`, `crm_visitas_extra`; colunas `nai_visita.duracao_min` / `criada_no_crm_por` | 250 |
| robô de fora (Grok) avisa o Tel, com limite por hora/dia | `crm_avisar_tel`, tabela `aviso_externo`; chaves `aviso_externo_por_hora` / `_por_dia` | 251 |

## Site (imobeasy.online)
- API Flask: `nay-site-api/app.py` + `nay-site-api/olx_api.py` (OLX e o cadastro vindo do CRM).
  (`/api/imoveis-lista` filtros; `/api/imoveis/opcoes` listas; `/api/condominios*`).
  Papel de leitura `nay_site_leitura` (GRANT em migração). Deploy: `./scripts/nay site [arquivos do imob-easy]`.
- Admin estático: `imob-easy/admin/*.html` + `imob-easy/assets/js/*.js` (Imóveis: `imoveis-ux.js`; condomínios: `condominios-aba.js`; cadastro pendente: `cadastro-pendente.js`).
  As rotas de `/admin/api/imoveis/...` pedem a senha do /admin -- e também abrem com o segredo do painel dentro do CRM.
  Troque o `?v=` do script no HTML quando mudar o JS.

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

## n8n (fluxo `NAI atendimento locação`, `producao/n8n/`)
- Import só de madrugada (espelho-madrugada). Modelo/memória: pela interface. Ler execuções: sqlite só leitura (scratch `n8nq.sh`).
- O procedimento da madrugada está em `scripts/madrugada/` (cópia em `/root/`): exporta o fluxo vivo, aplica um
  patch de UM nó com contagem exata, reimporta, religa e reinicia, e devolve o backup se os fluxos não voltarem
  ativos. Travas: só 1h–5h de Manaus e só com a Nay parada. Depois do import, rodar `./scripts/foto_producao.sh`.
- Testar sem WhatsApp: espelho `…0001` via `/root/nai_treino_rodar.py` ou POST no webhook `172.16.0.2:5678/webhook/nai-atendimento-locacao`.

## Regras que valem sempre
CLAUDE.md, `Arquivos/REGRAS-E-BUGS.md`, memória em `~/.claude/projects/.../memory/MEMORY.md`.
