# core_porta_sombra  (tabela, ~0 linhas)
551: no modo sombra, o que a porta gravaria; comparar com mensagens / captacao_mensagens

## colunas
id  bigint  NOT NULL  padrão nextval('core_porta_sombra_id_seq'::regclass)
linha  text  NOT NULL
evento_id  bigint
message_id  text
telefone  text
direcao  text
origem  text
texto  text
acao  text  NOT NULL
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX core_porta_sombra_quando ON public.core_porta_sombra USING btree (linha, criado_em)
CREATE UNIQUE INDEX core_porta_sombra_pkey ON public.core_porta_sombra USING btree (id)

## restrições
core_porta_sombra_evento_id_fkey: FOREIGN KEY (evento_id) REFERENCES core_porta_evento(id) ON DELETE CASCADE
core_porta_sombra_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
