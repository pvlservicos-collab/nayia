# bairro_normal  (tabela, ~53 linhas)
241: os bairros do catálogo normalizados, para a identificação não varrer imoveis a cada chamada

## colunas
bairro  text  NOT NULL
normal  text  NOT NULL
dois  text
imoveis  integer  NOT NULL  padrão 0

## índices
CREATE INDEX bairro_normal_normal ON public.bairro_normal USING btree (normal)
CREATE UNIQUE INDEX bairro_normal_pkey ON public.bairro_normal USING btree (bairro)

## restrições
bairro_normal_pkey: PRIMARY KEY (bairro)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_leitura: SELECT

## funções que escrevem aqui
nai_bairro_normal_refazer

## funções que citam
crm_anuncio_mensagem, crm_imovel_candidatos, nai_bairro_normal_gatilho, nai_bairro_normal_refazer, nai_condominio_da_pergunta, nai_imovel_pela_descricao, nai_pedido_de_perfil
