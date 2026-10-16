# pendencias  (tabela, ~197 linhas)

## colunas
id  integer  NOT NULL  padrão nextval('pendencias_id_seq'::regclass)
codigo  text
o_que_falta  text
de_quem  text
avisar  text
resposta  text
status  text  padrão 'aberta'::text
criada_em  timestamp with time zone  padrão now()
respondida_em  timestamp with time zone

## índices
CREATE INDEX pendencias_status_idx ON public.pendencias USING btree (status)
CREATE INDEX pendencias_trgm_idx ON public.pendencias USING gin (o_que_falta gin_trgm_ops)
CREATE UNIQUE INDEX pendencias_pkey ON public.pendencias USING btree (id)

## restrições
pendencias_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
nai_escalar_link_de_catalogo, nai_sec_perguntar_ao_tel, nay_comando, nay_escalar, nay_responder_pendencia, pergunta_fila_responder

## funções que citam
nai_escalar_link_de_catalogo, nai_sec_perguntar_ao_tel, nay_comando, nay_escalar, nay_lembretes_devidos, nay_pendencias_esquecidas, nay_responder_conversando, nay_responder_pendencia, pergunta_fila_responder, pergunta_fila_resposta_valida
