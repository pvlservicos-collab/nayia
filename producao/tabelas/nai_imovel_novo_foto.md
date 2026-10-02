# nai_imovel_novo_foto  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('nai_imovel_novo_foto_id_seq'::regclass)
novo_id  bigint  NOT NULL
url  text  NOT NULL
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX nai_imovel_novo_foto_pkey ON public.nai_imovel_novo_foto USING btree (id)

## restrições
nai_imovel_novo_foto_novo_id_fkey: FOREIGN KEY (novo_id) REFERENCES nai_imovel_novo(id) ON DELETE CASCADE
nai_imovel_novo_foto_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
nai_sec_guardar_foto, nai_sec_guardar_fotos_do_turno

## funções que citam
nai_imovel_novo_falta, nai_imovel_novo_subir, nai_sec_guardar_foto, nai_sec_guardar_fotos_do_turno
