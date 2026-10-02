# nai_jev_rodada  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('nai_jev_rodada_id_seq'::regclass)
rodada  text  NOT NULL
turno_id  bigint
quem  text
texto  text
leitura_img  text
respostas  jsonb
jev_disse  text
aconteceu  text
bateu  boolean
custo  numeric(12,8)
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX nai_jev_rodada_r ON public.nai_jev_rodada USING btree (rodada, id)
CREATE UNIQUE INDEX nai_jev_rodada_pkey ON public.nai_jev_rodada USING btree (id)

## restrições
nai_jev_rodada_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_conteudo: INSERT, SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
