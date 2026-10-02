# nai_treino_ciclo  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('nai_treino_ciclo_id_seq'::regclass)
rotulo  text
tamanho  integer  NOT NULL
criado_em  timestamp with time zone  NOT NULL  padrão now()
fechado_em  timestamp with time zone

## índices
CREATE UNIQUE INDEX nai_treino_ciclo_pkey ON public.nai_treino_ciclo USING btree (id)

## restrições
nai_treino_ciclo_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_conteudo: SELECT
nay_site_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
nai_treino_montar_ciclo

## funções que citam
nai_treino_montar_ciclo
