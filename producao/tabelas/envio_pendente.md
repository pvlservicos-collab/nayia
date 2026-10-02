# envio_pendente  (tabela, ~0 linhas)

## colunas
id  integer  NOT NULL  padrão nextval('envio_pendente_id_seq'::regclass)
destino_telefone  text  NOT NULL
destino_nome  text  NOT NULL
codigos  text[]  NOT NULL  padrão '{}'::text[]
ambiguas  jsonb  NOT NULL  padrão '[]'::jsonb
sem_casar  text[]  NOT NULL  padrão '{}'::text[]
fora_do_site  text[]  NOT NULL  padrão '{}'::text[]
criado_em  timestamp with time zone  NOT NULL  padrão now()
fechado_em  timestamp with time zone
fechado_motivo  text

## índices
CREATE UNIQUE INDEX envio_pendente_pkey ON public.envio_pendente USING btree (id)
CREATE UNIQUE INDEX envio_pendente_um_aberto ON public.envio_pendente USING btree ((true)) WHERE (fechado_em IS NULL)

## restrições
envio_pendente_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
