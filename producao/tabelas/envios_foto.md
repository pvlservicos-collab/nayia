# envios_foto  (tabela, ~925 linhas)
O id de cada FOTO de imóvel que o publicador mandou (grupo ou corretor), com o código (287, 03/10/2026). Existe para a marcação da foto virar o imóvel; não é contagem de posts (essa é `envios`).

## colunas
id  bigint  NOT NULL  padrão nextval('envios_foto_id_seq'::regclass)
message_id  text  NOT NULL
codigo  integer  NOT NULL
destino  text  NOT NULL
telefone  text
grupo_nome  text
enviado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX envios_foto_msg ON public.envios_foto USING btree (message_id)
CREATE INDEX envios_foto_quando ON public.envios_foto USING btree (enviado_em)
CREATE UNIQUE INDEX envios_foto_pkey ON public.envios_foto USING btree (id)

## restrições
envios_foto_destino_check: CHECK ((destino = ANY (ARRAY['grupo'::text, 'corretor'::text])))
envios_foto_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
crm_quem_mandou, nay_imovel_da_citacao
