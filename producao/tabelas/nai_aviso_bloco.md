# nai_aviso_bloco  (tabela, ~0 linhas)
266: cada visita que o Tel já recebeu no resumo do bloco (manhã/tarde/noite). Uma vez por bloco.

## colunas
visita_id  bigint  NOT NULL
dia  date  NOT NULL
bloco  text  NOT NULL
situacao  text  NOT NULL
avisado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX nai_aviso_bloco_pkey ON public.nai_aviso_bloco USING btree (visita_id, dia, bloco)

## restrições
nai_aviso_bloco_bloco_check: CHECK ((bloco = ANY (ARRAY['manha'::text, 'tarde'::text, 'noite'::text])))
nai_aviso_bloco_pkey: PRIMARY KEY (visita_id, dia, bloco)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
nai_visitas_do_bloco_avisar

## funções que citam
nai_visitas_do_bloco_avisar
