-- =====================================================================
-- NAI atendimento locacao -- 01: tabelas e configuracao
--
-- Tudo aqui e NOVO e aditivo: CREATE ... IF NOT EXISTS, nenhum DROP,
-- nenhuma tabela da Nay antiga alterada. A unica mudanca em tabela
-- existente e uma COLUNA NOVA, anulavel e sem default, em `mensagens`
-- (`fluxo`), para saber qual fluxo gravou cada mensagem. O INSERT da Nay
-- antiga lista as colunas, entao ela nem enxerga a coluna nova.
--
-- A regra de organizacao que atravessa tudo:
--   * PESSOA e `nai_contato`, com UMA chave por pessoa (DDI+DDD+8 ultimos
--     digitos, a mesma de `nay_fone_chave`). O 9 a mais ou a menos nao cria
--     duas pessoas, e duas pessoas nunca dividem uma chave.
--   * Nada e chaveado por texto de telefone solto: visita, turno, saida e
--     memoria apontam para `nai_contato.id`.
--   * Toda mensagem que sai passa por `nai_saida`, e o gatilho dela recusa
--     mensagem cujo destino nao seja parte daquela conversa ou visita.
-- =====================================================================

-- --------------------------------------------------------- configuracao
CREATE TABLE IF NOT EXISTS nai_config (
  chave         text PRIMARY KEY,
  valor         text NOT NULL,
  descricao     text,
  atualizado_em timestamptz NOT NULL DEFAULT now()
);

INSERT INTO nai_config (chave, valor, descricao) VALUES
 ('modo', 'teste',
  'QUEM CAI NA NAI. desligado = ninguem | teste = so os numeros_teste | todos = todo mundo (a Nay antiga so repassa). MODO TESTE: para ir pra valer, troque para todos.'),
 ('numeros_teste', '5596991712835',
  'Numeros que caem na NAI no modo teste, separados por virgula. 5596991712835 = Tel (Macapa).'),
 ('telefone_teste_destino', '5596991712835',
  'MODO TESTE: tudo que iria para proprietario, Fernando ou Tel vai para ESTE numero, com uma etiqueta dizendo para quem iria.'),
 ('tel_telefone', '559294717316',
  'O numero do Tel que recebe avisos e manda comandos.'),
 ('pausada', 'nao',
  'sim = a NAI nao envia nada (as mensagens continuam gravadas). Vale na hora.'),
 ('envio_simulado', 'nao',
  'sim = a NAI monta tudo mas NAO chama a Z-API (estado simulado). So para teste automatico.'),
 ('janela_inicio', '06:00', 'Mensagem que a NAI INICIA (lembrete, aviso) so sai a partir desta hora (Manaus). Resposta sai sempre.'),
 ('janela_fim', '22:00', 'Mensagem que a NAI INICIA so sai ate esta hora (Manaus).'),
 ('reenvio_proprietario_min', '30', 'Minutos sem resposta do proprietario ate mandar de novo.'),
 ('reenvios_proprietario_max', '3', 'Quantas vezes, no maximo, ela manda de novo ao proprietario sozinha.'),
 ('aviso_tel_horas_antes', '2', 'Visita ainda sem confirmacao do proprietario a esta distancia do horario: avisa o Tel.'),
 ('reenvio_motoboy_min', '30', 'Minutos sem resposta do Fernando ate cobrar de novo.'),
 ('lembrete_corretor_min', '60', 'Minutos antes da visita para lembrar o corretor.'),
 ('aviso_motoboy_min', '30', 'Minutos antes da visita para mandar a senha / conferir a chave com o Fernando.'),
 ('pos_visita_min', '60', 'Minutos depois do horario para perguntar ao corretor como foi.'),
 ('inicio_manha', '08:00', 'Comeco do periodo da manha (lembrete do periodo).'),
 ('inicio_tarde', '12:00', 'Comeco do periodo da tarde.'),
 ('inicio_noite', '18:00', 'Comeco do periodo da noite.'),
 ('dados_primeiro_lembrete_min', '3', 'Minutos ate cobrar o nome/CPF que faltou pela primeira vez.'),
 ('dados_lembretes_max', '3', 'Quantas vezes cobrar os dados que faltam antes de passar ao Tel.'),
 ('antecedencia_minima_horas', '3', 'Visita pedida com menos que isto e URGENTE: vai para o Tel e a NAI para (decisao do Tel, 12/09).')
ON CONFLICT (chave) DO NOTHING;

CREATE OR REPLACE FUNCTION nai_cfg(p_chave text, p_padrao text DEFAULT NULL)
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT coalesce((SELECT valor FROM nai_config WHERE chave = p_chave), p_padrao);
$$;

CREATE OR REPLACE FUNCTION nai_cfg_int(p_chave text, p_padrao int)
RETURNS int LANGUAGE sql STABLE AS $$
  SELECT coalesce(NULLIF(regexp_replace(nai_cfg(p_chave, ''), '\D', '', 'g'), '')::int, p_padrao);
$$;

-- ------------------------------------------------------------- pessoas
CREATE TABLE IF NOT EXISTS nai_contato (
  id              bigserial PRIMARY KEY,
  -- DDI+DDD+8 digitos (ou lid:<digitos> quando o WhatsApp so manda o @lid)
  chave           text NOT NULL UNIQUE CHECK (chave ~ '^([0-9]{8,15}|lid:[0-9]{6,20})$'),
  -- O identificador EXATO que chegou por ultimo -- e para ele que se responde.
  telefone        text NOT NULL CHECK (telefone ~ '^[0-9]{8,15}(@lid)?$'),
  nome_whatsapp   text,
  nome_completo   text,
  cpf             text CHECK (cpf IS NULL OR cpf ~ '^[0-9]{11}$'),
  creci           text,
  criado_em       timestamptz NOT NULL DEFAULT now(),
  atualizado_em   timestamptz NOT NULL DEFAULT now()
);

-- O TEL ASSUMIU a conversa (11/09, pedido do Tel): se ele escreveu nesse
-- chat pelo celular do numero da Nay, a NAI para de mandar QUALQUER coisa
-- para essa pessoa (resposta, lembrete, aviso) ate ele mandar DEVOLVER.
ALTER TABLE nai_contato ADD COLUMN IF NOT EXISTS humano_assumiu_em timestamptz;
ALTER TABLE nai_contato ADD COLUMN IF NOT EXISTS humano_motivo text;
-- Quando ela sugeriu visita a este corretor por conta propria. "Sem forcar
-- a barra" (Tel, 11/09): no maximo UMA sugestao; depois, so se ELE pedir.
ALTER TABLE nai_contato ADD COLUMN IF NOT EXISTS visita_sugerida_em timestamptz;

-- -------------------------------------------- acesso ao imovel (aprende)
-- Como se entra no imovel. Aprendido com o proprietario (ou com o Tel pelo
-- comando ACESSO) e reusado na proxima visita. A SENHA nunca mora aqui --
-- ela fica so na visita e e apagada depois dela.
CREATE TABLE IF NOT EXISTS nai_acesso_imovel (
  codigo        int PRIMARY KEY REFERENCES imoveis(codigo),
  acesso        text NOT NULL CHECK (acesso IN ('chave_conosco','buscar_chave','fechadura','proprietario_acompanha')),
  detalhe       text,
  fonte         text NOT NULL,
  atualizado_em timestamptz NOT NULL DEFAULT now()
);

-- -------------------------------------------------------------- visitas
CREATE TABLE IF NOT EXISTS nai_visita (
  id                    bigserial PRIMARY KEY,
  codigo                int NOT NULL REFERENCES imoveis(codigo),
  corretor_id           bigint NOT NULL REFERENCES nai_contato(id),
  proprietario_id       bigint REFERENCES nai_contato(id),
  proprietario_cadastro int,
  proprietario_nome     text,
  motoboy_id            bigint REFERENCES nai_contato(id),
  quando                timestamptz,
  quando_sugerido       timestamptz,
  estado                text NOT NULL DEFAULT 'coletando' CHECK (estado IN (
                          'coletando','aguardando_proprietario','negociando','aguardando_acesso',
                          'aguardando_motoboy','confirmada','com_tel','realizada',
                          'encerrada','cancelada','expirada')),
  aguardando            text CHECK (aguardando IN ('corretor','proprietario','motoboy','tel')),
  urgente               boolean NOT NULL DEFAULT false,
  qualificado           boolean,
  visitante_nome        text,
  visitante_cpf         text CHECK (visitante_cpf IS NULL OR visitante_cpf ~ '^[0-9]{11}$'),
  acesso                text CHECK (acesso IN ('chave_conosco','buscar_chave','fechadura','proprietario_acompanha')),
  acesso_detalhe        text,
  senha                 text,
  prop_ok_em            timestamptz,
  moto_ok_em            timestamptz,
  confirmada_em         timestamptz,
  ult_msg_prop_em       timestamptz,
  ult_resp_prop_em      timestamptz,
  reenvios_prop         int NOT NULL DEFAULT 0,
  aviso_demora_em       timestamptz,
  aviso_tel_em          timestamptz,
  proximo_aviso_prop_em timestamptz,
  ult_msg_moto_em       timestamptz,
  ult_resp_moto_em      timestamptz,
  reenvios_moto         int NOT NULL DEFAULT 0,
  aviso_tel_moto_em     timestamptz,
  proximo_lembrete_dados_em timestamptz,
  lembretes_dados       int NOT NULL DEFAULT 0,
  aviso_tel_dados_em    timestamptz,
  lembrete_periodo_em   timestamptz,
  lembrete_1h_em        timestamptz,
  aviso_motoboy_em      timestamptz,
  pos_visita_em         timestamptz,
  devolver_chave_em     timestamptz,
  resultado             text,
  motivo                text,
  criado_em             timestamptz NOT NULL DEFAULT now(),
  atualizado_em         timestamptz NOT NULL DEFAULT now(),
  encerrada_em          timestamptz
);

-- Uma visita ABERTA por corretor e imovel. Pedir de novo atualiza a mesma,
-- nunca cria duas que depois brigam pelo mesmo proprietario.
CREATE UNIQUE INDEX IF NOT EXISTS nai_visita_uma_aberta
  ON nai_visita (corretor_id, codigo)
  WHERE estado NOT IN ('realizada','encerrada','cancelada','expirada');
CREATE INDEX IF NOT EXISTS nai_visita_estado ON nai_visita (estado, quando);
CREATE INDEX IF NOT EXISTS nai_visita_prop ON nai_visita (proprietario_id) WHERE proprietario_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS nai_visita_evento (
  id        bigserial PRIMARY KEY,
  visita_id bigint NOT NULL REFERENCES nai_visita(id),
  quando    timestamptz NOT NULL DEFAULT now(),
  tipo      text NOT NULL,
  detalhe   text
);
CREATE INDEX IF NOT EXISTS nai_visita_evento_v ON nai_visita_evento (visita_id, id);

-- ---------------------------------------------------------------- turno
-- Um turno = um lote de mensagens de UMA pessoa, respondido de uma vez.
-- E o "cabecalho": quem escreveu, em que papel, sobre qual visita. Tudo o
-- que o fluxo faz depois le daqui, e nunca do texto ou do modelo.
CREATE TABLE IF NOT EXISTS nai_turno (
  id          bigserial PRIMARY KEY,
  contato_id  bigint NOT NULL REFERENCES nai_contato(id),
  papel       text NOT NULL CHECK (papel IN ('corretor','proprietario','motoboy','tel')),
  visita_id   bigint REFERENCES nai_visita(id),
  teste       boolean NOT NULL DEFAULT false,
  texto       text,
  msg_ids     bigint[],
  criado_em   timestamptz NOT NULL DEFAULT now(),
  fechado_em  timestamptz
);
CREATE INDEX IF NOT EXISTS nai_turno_contato ON nai_turno (contato_id, id DESC);

-- ---------------------------------------------------------------- saida
-- A caixa de saida. UNICO caminho de mensagem da NAI para fora.
CREATE TABLE IF NOT EXISTS nai_saida (
  id             bigserial PRIMARY KEY,
  turno_id       bigint REFERENCES nai_turno(id),
  visita_id      bigint REFERENCES nai_visita(id),
  contato_id     bigint NOT NULL REFERENCES nai_contato(id),
  papel_destino  text NOT NULL CHECK (papel_destino IN ('turno','corretor','proprietario','motoboy','tel')),
  chave_destino  text NOT NULL,
  tipo           text NOT NULL CHECK (tipo IN ('texto','imagem')),
  texto          text,
  imagem_url     text,
  codigo         int,
  ordem          int NOT NULL DEFAULT 0,
  motivo         text,
  estado         text NOT NULL DEFAULT 'pendente'
                   CHECK (estado IN ('pendente','enviando','enviado','bloqueado','erro','simulado')),
  bloqueio       text,
  enviar_apos    timestamptz NOT NULL DEFAULT now(),
  telefone_final text,
  redirecionado  boolean NOT NULL DEFAULT false,
  message_id     text,
  resposta       jsonb,
  criado_em      timestamptz NOT NULL DEFAULT now(),
  enviado_em     timestamptz,
  CHECK ((tipo = 'texto'  AND nullif(btrim(texto), '') IS NOT NULL)
      OR (tipo = 'imagem' AND imagem_url IS NOT NULL AND codigo IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS nai_saida_pendente ON nai_saida (id) WHERE estado = 'pendente';
CREATE INDEX IF NOT EXISTS nai_saida_msgid ON nai_saida (message_id) WHERE message_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS nai_saida_contato ON nai_saida (contato_id, id DESC);

-- ------------------------------------------------------------- memoria
-- Mesmo formato da `nay_memoria` (o no Postgres Chat Memory do n8n). Tabela
-- SEPARADA: a memoria da NAI nunca se mistura com a da Nay antiga, e a
-- chave de sessao e nai:<papel>:<contato_id>, nunca um telefone cru.
CREATE TABLE IF NOT EXISTS nai_memoria (
  id         serial PRIMARY KEY,
  session_id varchar(255) NOT NULL,
  message    jsonb NOT NULL
);
CREATE INDEX IF NOT EXISTS nai_memoria_sessao ON nai_memoria (session_id, id);

-- ------------------------------------------- de qual fluxo e a mensagem
ALTER TABLE mensagens ADD COLUMN IF NOT EXISTS fluxo text;

-- O modelo respondeu "Esse horario ja passou" SEM chamar pedir_visita (teste do
-- Tel, 12/09/2026): a frase e literal de uma ferramenta, e ele a reproduziu de
-- cabeca. Como nada rodou, a visita nao existia -- e a proxima frase inventada
-- poderia ser "Visita confirmada". Cada ferramenta de visita carimba o turno
-- aqui, e a saida so deixa passar frase de visita com o carimbo.
ALTER TABLE nai_turno ADD COLUMN IF NOT EXISTS ferramentas text[] NOT NULL DEFAULT '{}';
