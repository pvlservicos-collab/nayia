# nai_treino_pedido  (tabela, ~129 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('nai_treino_pedido_id_seq'::regclass)
turno_id  bigint  NOT NULL
contato_id  bigint  NOT NULL
quem  text
criado_em  timestamp with time zone  NOT NULL
texto  text  NOT NULL
resposta  text
motivos  text[]  NOT NULL  padrão '{}'::text[]
explicacao  text
explicado_por  text
explicado_em  timestamp with time zone
estado  text  NOT NULL  padrão 'novo'::text
coletado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX nai_treino_pedido_estado ON public.nai_treino_pedido USING btree (estado, criado_em DESC)
CREATE UNIQUE INDEX nai_treino_pedido_pkey ON public.nai_treino_pedido USING btree (id)
CREATE UNIQUE INDEX nai_treino_pedido_turno_id_key ON public.nai_treino_pedido USING btree (turno_id)

## restrições
nai_treino_pedido_estado_check: CHECK ((estado = ANY (ARRAY['novo'::text, 'explicado'::text, 'implementado'::text, 'ignorado'::text])))
nai_treino_pedido_pkey: PRIMARY KEY (id)
nai_treino_pedido_turno_id_key: UNIQUE (turno_id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_conteudo: SELECT
nay_site_leitura: SELECT
nay_site_conteudo, só nestas colunas: UPDATE(explicacao, explicado_por, explicado_em, estado)

## funções que escrevem aqui
nai_treino_coletar

## funções que citam
nai_treino_coletar
