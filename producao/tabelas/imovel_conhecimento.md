# imovel_conhecimento  (tabela, ~2 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('imovel_conhecimento_id_seq'::regclass)
codigo  text  NOT NULL
assunto  text  NOT NULL
texto  text  NOT NULL
quem_contou  text
criado_em  timestamp with time zone  NOT NULL  padrão now()
atualizado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX conhecimento_um_por_assunto ON public.imovel_conhecimento USING btree (codigo, assunto)
CREATE UNIQUE INDEX imovel_conhecimento_pkey ON public.imovel_conhecimento USING btree (id)

## restrições
imovel_conhecimento_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
nay_esquecer_imovel, nay_gravar_conhecimento, nay_guardar_do_imovel

## funções que citam
nai_ficha_completa, nay_escalar, nay_esquecer_imovel, nay_gravar_conhecimento, nay_guardar_do_imovel, nay_o_que_sei_do_imovel
