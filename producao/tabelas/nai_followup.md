# nai_followup  (tabela, ~237 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('nai_followup_id_seq'::regclass)
chave  text  NOT NULL
dia_recebeu  date  NOT NULL
contato_id  bigint
codigos  integer[]
estado  text  NOT NULL
motivo  text
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX nai_followup_chave_dia_recebeu_key ON public.nai_followup USING btree (chave, dia_recebeu)
CREATE UNIQUE INDEX nai_followup_pkey ON public.nai_followup USING btree (id)

## restrições
nai_followup_chave_dia_recebeu_key: UNIQUE (chave, dia_recebeu)
nai_followup_estado_check: CHECK ((estado = ANY (ARRAY['enviado'::text, 'pulado'::text])))
nai_followup_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
nai_followup_rodar

## funções que citam
crm_parceria_followup_nay, nai_followup_rodar
