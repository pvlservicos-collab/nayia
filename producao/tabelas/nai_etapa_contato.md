# nai_etapa_contato  (tabela, ~110 linhas)

## colunas
contato_id  bigint  NOT NULL
etapa  text  NOT NULL
desde  timestamp with time zone  NOT NULL  padrão now()
motivo  text
atualizado_em  timestamp with time zone  NOT NULL  padrão now()
crm_em  timestamp with time zone

## índices
CREATE UNIQUE INDEX nai_etapa_contato_pkey ON public.nai_etapa_contato USING btree (contato_id)

## restrições
nai_etapa_contato_contato_id_fkey: FOREIGN KEY (contato_id) REFERENCES nai_contato(id)
nai_etapa_contato_etapa_check: CHECK ((etapa = ANY (ARRAY['identificacao'::text, 'recebeu_imovel'::text, 'agendamento_visita'::text])))
nai_etapa_contato_pkey: PRIMARY KEY (contato_id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT

## funções que escrevem aqui
nai_etapa_atualizar

## funções que citam
crm_parceria_funil, crm_parceria_marcas, nai_abrir_turno, nai_etapa_atualizar, nai_etapa_para_o_modelo
