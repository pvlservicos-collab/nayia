-- Captacao de proprietarios -- campanha temporaria de atualizacao de cadastro.
--
-- Estas tabelas sao as que o fluxo n8n `Nay - captacao proprietarios`
-- (id CjsUJefRYcQIIi1F) ja chamava. O fluxo foi escrito por uma IA que NAO
-- tinha acesso a este banco, entao ele referenciava cinco tabelas que nunca
-- existiram. Este arquivo cria exatamente o que o SQL do fluxo espera --
-- nome de coluna por nome de coluna. Renomear coluna aqui quebra o fluxo.
--
-- A campanha e temporaria: varre a base de proprietarios, pergunta a
-- situacao de cada imovel e vai gerando a lista de imoveis disponiveis.
-- Terminada a campanha, estas tabelas podem ser arquivadas.
--
-- Idempotente: pode rodar de novo sem quebrar nada.

BEGIN;

-- ---------------------------------------------------------------------
-- 1. CONFIG -- os interruptores. Ficam no BANCO, nao no JavaScript.
--
-- O fluxo le estes valores dentro do proprio SQL que reserva o lead. Isso
-- e de proposito: se um no de codigo do n8n falhar, nada sai mesmo assim.
-- E FALHA FECHADA -- toda leitura usa COALESCE(..., valor_que_bloqueia):
-- linha ausente significa PAUSADO, e teto diario ausente significa ZERO.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS captacao_config (
  chave  text PRIMARY KEY,
  valor  text NOT NULL,
  nota   text
);

INSERT INTO captacao_config (chave, valor, nota) VALUES
  ('captacao_pausada', 'sim',
   'Interruptor geral do DISPARO. sim = nao sai nenhuma mensagem nova.'),
  ('resposta_pausada', 'sim',
   'Interruptor da RESPOSTA automatica. sim = a IA nao responde quem escrever.'),
  ('limite_dia', '0',
   'Teto de mensagens enviadas por dia (aquecimento do numero). 0 = nada sai.'),
  ('max_followup', '2',
   'Quantas vezes insistir com quem nao responde, no mesmo horario do dia seguinte.'),
  ('modo_teste', 'sim',
   'MODO TESTE. sim = TODA mensagem vai para telefone_teste, seja qual for o lead.'),
  ('telefone_teste', '5596991712835',
   'Numero do Tel. So e usado quando modo_teste = sim.')
ON CONFLICT (chave) DO NOTHING;

-- ---------------------------------------------------------------------
-- 2. LEADS -- uma linha por proprietario na campanha.
--
-- `telefone` e UNIQUE porque e por ele que o webhook encontra o lead: a
-- mensagem que chega so traz o numero. Dois leads com o mesmo telefone
-- fariam a resposta cair no lead errado.
--
-- imovel_desc/condominio/bairro sao DESNORMALIZADOS de proposito: a
-- mensagem cita o imovel ("o seu imovel no Condominio X"), e congelar o
-- texto no momento da importacao evita que uma varredura mude o endereco
-- no meio da campanha e a Nay cite um imovel diferente do que citou ontem.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS captacao_leads (
  id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  telefone          text NOT NULL UNIQUE,
  nome              text,
  tratamento        text DEFAULT 'Sr.',
  -- de onde veio e sobre qual imovel se fala
  proprietario_id   integer,
  codigo            text,
  imovel_desc       text,
  condominio        text,
  bairro            text,
  tipo_imovel       text,
  lista_id          bigint,
  quem_importou     text,
  -- maquina de estado do disparo
  status            text NOT NULL DEFAULT 'novo',
  etapa             text DEFAULT 'novo',
  tentativas        integer NOT NULL DEFAULT 0,
  opt_out           boolean NOT NULL DEFAULT false,
  pergunta_pendente text,
  ultimo_envio_em   timestamptz,
  respondeu_em      timestamptz,
  -- o que a campanha existe para descobrir
  situacao          text,
  contrato_ate      text,
  tem_outro_imovel  boolean NOT NULL DEFAULT false,
  -- fecho
  motivo_fim        text,
  fechado_em        timestamptz,
  criado_em         timestamptz NOT NULL DEFAULT now(),
  atualizado_em     timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT captacao_lead_status_ok CHECK (status IN
    ('novo','reservado','enviado','erro','respondendo','concluido')),
  CONSTRAINT captacao_lead_etapa_ok CHECK (etapa IS NULL OR etapa IN
    ('novo','aguardando_situacao','aguardando_prazo','aguardando_mes',
     'aguardando_outros','concluido')),
  CONSTRAINT captacao_lead_situacao_ok CHECK (situacao IS NULL OR situacao IN
    ('disponivel','alugado','vendido')),
  -- telefone cru, so digitos, com DDI. E o formato que a Z-API usa e o que
  -- o webhook devolve; guardar formatado faria o lead nunca ser encontrado.
  CONSTRAINT captacao_lead_telefone_cru CHECK (telefone ~ '^[0-9]{12,13}$')
);

-- O disparo pergunta "quem e o proximo?" varias vezes por hora. Sem estes
-- indices ele varre a tabela inteira toda vez.
CREATE INDEX IF NOT EXISTS captacao_leads_fila_idx
  ON captacao_leads (status, id) WHERE NOT opt_out;
CREATE INDEX IF NOT EXISTS captacao_leads_followup_idx
  ON captacao_leads (status, ultimo_envio_em) WHERE respondeu_em IS NULL;
CREATE INDEX IF NOT EXISTS captacao_leads_situacao_idx
  ON captacao_leads (situacao, atualizado_em DESC);

-- ---------------------------------------------------------------------
-- 3. MENSAGENS -- o log de envio que o CRM mostra.
--
-- Uma linha por balao, nos dois sentidos, com o message_id da Z-API. E
-- desta tabela que saem as metricas da aba Captacao e o teto diario.
-- `status` guarda Falhou quando a Z-API nao devolveu id: envio que nao
-- aconteceu nao pode contar como enviado.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS captacao_mensagens (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  lead_id     bigint REFERENCES captacao_leads(id) ON DELETE SET NULL,
  telefone    text,
  direcao     text NOT NULL,
  origem      text,
  texto       text,
  status      text,
  message_id  text,
  criada_em   timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT captacao_msg_direcao_ok CHECK (direcao IN ('enviada','recebida'))
);

CREATE INDEX IF NOT EXISTS captacao_mensagens_lead_idx
  ON captacao_mensagens (lead_id, criada_em);
-- O teto diario conta as enviadas de hoje a cada reserva de lead.
CREATE INDEX IF NOT EXISTS captacao_mensagens_dia_idx
  ON captacao_mensagens (direcao, criada_em DESC);
-- O no 'Reservar mensagens' busca por telefone + direcao + status.
CREATE INDEX IF NOT EXISTS captacao_mensagens_fila_idx
  ON captacao_mensagens (telefone, direcao, status);

-- ---------------------------------------------------------------------
-- 4. IMOVEIS EXTRA -- o "tem algum outro imovel?" da ETAPA 4.
--
-- Guarda CRU, nas palavras do proprietario. Quem separa depois e o Tel,
-- pela curadoria no CRM. Nao tenta virar cadastro sozinho.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS captacao_imoveis_extra (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  lead_id    bigint NOT NULL REFERENCES captacao_leads(id) ON DELETE CASCADE,
  descricao  text NOT NULL,
  negocio    text NOT NULL DEFAULT 'nao_informado',
  curado     boolean NOT NULL DEFAULT false,
  criado_em  timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT captacao_extra_negocio_ok CHECK (negocio IN
    ('venda','locacao','ambos','nao_informado'))
);

CREATE INDEX IF NOT EXISTS captacao_extra_lead_idx
  ON captacao_imoveis_extra (lead_id);

-- ---------------------------------------------------------------------
-- 5. MEMORIA DO AGENTE -- mesma forma da `nay_memoria` que ja roda no
-- fluxo de atendimento. O no Postgres Chat Memory do n8n exige estas tres
-- colunas com estes nomes.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS nay_captacao_memoria (
  id          integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  session_id  varchar(255) NOT NULL,
  message     jsonb NOT NULL
);

CREATE INDEX IF NOT EXISTS nay_captacao_memoria_sessao_idx
  ON nay_captacao_memoria (session_id, id);

COMMIT;
