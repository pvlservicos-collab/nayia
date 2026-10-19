# aviso_de_saida_pergunta  (tabela, ~86 linhas)
334: a pergunta que a Nay faz ao Tel antes de avisar no grupo Easy que o imóvel saiu. Só resposta = sim libera o aviso.

## colunas
id  bigint  NOT NULL  padrão nextval('aviso_de_saida_pergunta_id_seq'::regclass)
codigo  text  NOT NULL
motivo  text
marcado_em  timestamp with time zone  NOT NULL
contato_id  bigint  NOT NULL
saida_id  bigint
perguntado_em  timestamp with time zone  NOT NULL  padrão now()
resposta  text
respondido_em  timestamp with time zone
turno_id  bigint

## índices
CREATE INDEX aviso_de_saida_pergunta_aberta ON public.aviso_de_saida_pergunta USING btree (contato_id, perguntado_em) WHERE (resposta IS NULL)
CREATE UNIQUE INDEX aviso_de_saida_pergunta_codigo_marcado_em_key ON public.aviso_de_saida_pergunta USING btree (codigo, marcado_em)
CREATE UNIQUE INDEX aviso_de_saida_pergunta_pkey ON public.aviso_de_saida_pergunta USING btree (id)

## restrições
aviso_de_saida_pergunta_codigo_marcado_em_key: UNIQUE (codigo, marcado_em)
aviso_de_saida_pergunta_pkey: PRIMARY KEY (id)
aviso_de_saida_pergunta_resposta_check: CHECK ((resposta = ANY (ARRAY['sim'::text, 'nao'::text, 'vencida'::text])))

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
nay_saida_responder, nay_saidas_perguntar

## funções que citam
nay_saida_responder, nay_saida_resposta_ler, nay_saidas_a_avisar, nay_saidas_perguntar
