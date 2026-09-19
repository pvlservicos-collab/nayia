# NAI atendimento locação

Fluxo n8n **`NAI atendimento locação`** (id `NaiAtendLocacao1`), montado em
10/09/2026 a partir de uma cópia do `Nay- recebe mensagem`, seguindo o fluxo
desenhado no editor (`site_fluxos` 'locacao', v3).

## Quem cai na NAI

O fluxo antigo ganhou **um** nó logo depois do Webhook, `NAI ou Nay? (quem atende)`,
que pergunta ao banco `nai_quem_atende(telefone)`. A resposta vem de
`nai_config.modo`:

| modo | quem a NAI atende |
|---|---|
| `desligado` | ninguém — tudo como antes |
| `teste` | só `numeros_teste` (hoje: 5596991712835, o Tel) |
| `todos` | todo mundo; o fluxo antigo só repassa |

Erro no banco, ou a NAI fora do ar → a mensagem segue na Nay de sempre.

    UPDATE nai_config SET valor='todos' WHERE chave='modo';      -- ir pra valer
    UPDATE nai_config SET valor='desligado' WHERE chave='modo';  -- desligar a NAI
    UPDATE nai_config SET valor='sim' WHERE chave='pausada';     -- NAI não envia nada

## Modo teste (visível, não escondido)

- O que iria para **proprietário, Fernando ou Tel** vai para
  `telefone_teste_destino`, com a etiqueta `🧪 TESTE · iria para o PROPRIETÁRIO ...`.
- Para responder **como proprietário**: marque a mensagem da etiqueta, ou
  comece com `P:`. Como **Fernando**: marque, ou `M:`. Como **Tel**: `T:`.
  Sem nada disso, é o corretor falando.
- **Parede:** no teste, nada sai para número fora da lista. Nem por engano.
- Comandos antigos (RESPOSTA, posta, dispara) não rodam do número de teste:
  continuam pelo número principal do Tel.

## As camadas que impedem mensagem errada para a pessoa errada

1. **Uma pessoa = uma chave** (`nai_contato.chave`, DDI+DDD+8 dígitos). O 9 a
   mais ou a menos não vira outra pessoa; duas pessoas nunca dividem chave.
   **@lid não é "adivinhado" pelo nome** (a Nay antiga faz isso — dois
   corretores com o mesmo nome no WhatsApp podiam virar um só): o @lid tem
   conversa própria, e a resposta vai sempre para quem escreveu.
2. **Cabeçalho do turno** (`nai_abrir_turno` → `nai_turno`): quem escreveu,
   em que papel, sobre qual visita, qual memória. As ferramentas recebem o
   **turno**, nunca um telefone vindo do modelo.
3. **Memória separada**: tabela `nai_memoria`, sessão
   `nai:<papel>:<contato>[:v<visita>]`. Proprietário tem memória por visita.
4. **Caixa de saída com gatilho** (`nai_saida` + `nai_saida_validar`): a
   linha só entra se o destino for parte da conversa (resposta ao turno) ou
   da visita (o corretor/proprietário/Fernando **daquela** visita). O
   telefone sai de `nai_contato` pelo id. Depois de enfileirada, o destino não
   muda (`nai_saida_imutavel`).
5. **Liberação** (`nai_liberar_saida`): confere a chave de novo, pausa,
   janela de horário (06h–22h para o que a NAI inicia), modo teste,
   repetição em 10 min.
6. **Conferir cabeçalho** (nó JavaScript): recalcula a chave com outra
   implementação e compara. Conferido contra 1.202 telefones reais: 0
   diferenças.

## Fotos: checagem dupla

Caso de origem: 01/09, a Regiane perguntou "Tem imagens?" do 2014 e ouviu
"não temos imagens" — o anúncio tinha 24.

1. Tabela `imovel_fotos`.
2. Vazia para imóvel nosso e no ar → o nó `Buscar fotos no site` lê o anúncio
   ao vivo e grava antes de responder (nunca apaga).
3. **Guarda de negação**: ela negou foto, ele tinha pedido, a foto existe →
   a frase é trocada por "segue as fotos" e as fotos saem.
4. **Guarda de promessa**: ele pediu foto de imóvel sem foto em lugar nenhum
   → "vou confirmar com o Tel" e o Tel é avisado.
5. Cada foto sai amarrada ao código: o gatilho confere que aquela URL é
   daquele imóvel no banco.

## A visita (as 15 etapas do fluxo desenhado)

`coletando` → `aguardando_proprietario` ⇄ `negociando` → `aguardando_acesso`
→ `aguardando_motoboy` → `confirmada` → `realizada` → `encerrada`
(e `cancelada`, `expirada`, `com_tel`).

A agenda (`nai_agenda_tick`, todo minuto) cuida de: cobrar dados que faltam,
reenviar ao proprietário a cada 30 min (máx. 3), avisar o corretor da demora,
avisar o Tel 2h antes sem confirmação, cobrar o Fernando, lembrete no começo
do período e 1h antes, senha/chave ao Fernando 30 min antes, "como foi?" 1h
depois (e a senha é apagada), devolver a chave.

Comandos do Tel: `VISITAS` · `VISITA <n> OK` · `VISITA <n> CANCELA` ·
`VISITA <n> HORARIO 16h` · `VISITA <n> AVISA 10h` · `VISITA <n> FERNANDO OK` ·
`ACESSO <código> chave com a gente | buscar a chave na portaria | fechadura | proprietário abre` ·
`ASSUMIR <telefone>` · `DEVOLVER <telefone>`.

## Fluxo v10/v11 do editor (11/09/2026)

O Tel mudou o fluxo no editor (v10) e eu preenchi os cards de mensagem com
os modelos (v11, "Claude: mensagens modelo"). Os textos das ferramentas SQL
são os dos cards — mudou um card de mensagem, mude o texto na função.

- **Prospecção na ordem do fluxo** (prompt, seção "O FLUXO DO TEL"): bairro →
  faixa de preço → mobiliado/semi, uma pergunta por mensagem; `buscar_por_perfil`
  agora é `nai_buscar_por_perfil`, que manda o bairro **e** os bairros ao redor
  ("Esses são os que eu encontrei dos bairros ao redor…"), sem os que ele já recebeu.
- **Visita sem forçar a barra**: ela sugere visita no máximo UMA vez
  (`nai_contato.visita_sugerida_em`); a sugestão repetida é cortada em
  `nai_enfileirar_resposta` (guarda `visita_repetida_cortada`). Quando o
  corretor fala de visita (`nay_pede_visita`), nada é cortado.
- **A conversa continua, não recomeça** (`nai_contexto_corretor`): o agente
  recebe se já estão conversando (12h), o que ele já recebeu (`envios`, 30
  dias), se ela já sugeriu visita, e — enquanto a memória da NAI é curta — as
  últimas 10 falas dele com a Nay antiga (`nay_memoria`).
- **O Tel assumiu** (igual à captação): mensagem `fromMe` sem `fromApi` no
  número da Nay → espera 15s → `nai_tel_assumiu` (confere que não é eco nosso
  por ID/texto) → `nai_contato.humano_assumiu_em`. Daí `nai_abrir_turno` não
  responde (mensagens ficam 'Com o Tel') e `nai_liberar_saida` bloqueia tudo
  para essa pessoa (`tel_assumiu`). Volta com `DEVOLVER <telefone>`.
  **Depende da Z-API mandar as mensagens enviadas pelo celular** ("Notificar as
  enviadas por mim também" na instância 3F7729…). Sem isso, só pelo comando
  `ASSUMIR <telefone>`.

## Arquivos

- `01_tabelas.sql` … `08_agenda.sql` — o banco (tudo novo; a única mudança em
  tabela existente é a coluna `mensagens.fluxo`, anulável).
- `teste_nai.sql` — 77 verificações, rodam dentro de transação com ROLLBACK.
- Montador do fluxo: `montar_nai.py` + `nai_prompts.py` (scratchpad da sessão).
- Backup do fluxo antigo antes da mudança:
  `/root/backups-n8n/bk_20260910_1945_antes_nai.json`.
