# pendencia_interessado  (tabela, ~109 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('pendencia_interessado_id_seq'::regclass)
pendencia_id  integer  NOT NULL
telefone  text  NOT NULL
nome  text
perguntou_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX interessado_um_por_pendencia ON public.pendencia_interessado USING btree (pendencia_id, "right"(regexp_replace(telefone, '[^0-9]'::text, ''::text, 'g'::text), 8))
CREATE UNIQUE INDEX pendencia_interessado_pkey ON public.pendencia_interessado USING btree (id)

## restrições
pendencia_interessado_pendencia_id_fkey: FOREIGN KEY (pendencia_id) REFERENCES pendencias(id) ON DELETE CASCADE
pendencia_interessado_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
nay_anotar_interessado

## funções que citam
nay_anotar_interessado, nay_escalar, nay_pendencias_esquecidas, nay_responder_pendencia
