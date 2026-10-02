# bairro_area  (tabela, ~0 linhas)

## colunas
area  text  NOT NULL
bairro  text  NOT NULL
nota  text
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX bairro_area_pkey ON public.bairro_area USING btree (area)

## restrições
bairro_area_pkey: PRIMARY KEY (area)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
nai_area_citada, nai_imovel_pelo_condominio, nay_normalizar_lugar
