# pendencia_rascunho  (tabela, ~0 linhas)

## colunas
pendencia_id  integer  NOT NULL
texto  text  NOT NULL
criado_msg_id  bigint  NOT NULL
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX pendencia_rascunho_pkey ON public.pendencia_rascunho USING btree (pendencia_id)

## restrições
pendencia_rascunho_pendencia_id_fkey: FOREIGN KEY (pendencia_id) REFERENCES pendencias(id)
pendencia_rascunho_pkey: PRIMARY KEY (pendencia_id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
nay_responder_conversando

## funções que citam
nay_pergunta_aberta_do_tel, nay_responder_conversando
