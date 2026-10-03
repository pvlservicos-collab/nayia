# envios_lista_grupo  (tabela, ~0 linhas)
Cada imóvel de cada pedaço de lista que o publicador postou nos grupos, com o id da mensagem (281, 03/10/2026). Só a Nay nova lê: a citação de uma lista vira os códigos dela, na ordem.

## colunas
id  bigint  NOT NULL  padrão nextval('envios_lista_grupo_id_seq'::regclass)
message_id  text  NOT NULL
codigo  integer  NOT NULL
posicao  integer  NOT NULL
grupo_id  text
grupo_nome  text
categoria  text
negocio  text
enviado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX envios_lista_grupo_msg ON public.envios_lista_grupo USING btree (message_id)
CREATE INDEX envios_lista_grupo_quando ON public.envios_lista_grupo USING btree (enviado_em)
CREATE UNIQUE INDEX envios_lista_grupo_pkey ON public.envios_lista_grupo USING btree (id)

## restrições
envios_lista_grupo_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
