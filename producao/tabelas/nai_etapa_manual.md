# nai_etapa_manual  (tabela, ~136 linhas)

## colunas
contato_id  bigint  NOT NULL
etapa  text  NOT NULL
definido_por  text
definido_em  timestamp with time zone  NOT NULL  padrão now()
valido_ate  timestamp with time zone

## índices
CREATE UNIQUE INDEX nai_etapa_manual_pkey ON public.nai_etapa_manual USING btree (contato_id)

## restrições
nai_etapa_manual_contato_id_fkey: FOREIGN KEY (contato_id) REFERENCES nai_contato(id)
nai_etapa_manual_etapa_check: CHECK ((etapa = ANY (ARRAY['todos'::text, 'visitas'::text, 'proprietarios'::text, 'fechamento'::text])))
nai_etapa_manual_pkey: PRIMARY KEY (contato_id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
crm_etapa_manual, crm_nay_voltar

## funções que citam
crm_etapa_da_nay, crm_etapa_manual, crm_nay_voltar, nai_com_a_rayssa
