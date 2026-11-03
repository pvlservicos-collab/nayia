# imovel_fotos_manual  (tabela, ~80 linhas)
Imóvel cujas fotos foram mexidas à mão na biblioteca do cadastro (283, 03/10/2026). A varredura de fotos do site antigo não mexe nele.

## colunas
codigo  integer  NOT NULL
editado_em  timestamp with time zone  NOT NULL  padrão now()
acoes  integer  NOT NULL  padrão 0

## índices
CREATE UNIQUE INDEX imovel_fotos_manual_pkey ON public.imovel_fotos_manual USING btree (codigo)

## restrições
imovel_fotos_manual_pkey: PRIMARY KEY (codigo)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
site_fotos_marcar_manual

## funções que citam
nai_gravar_fotos_do_site, site_fotos_lista, site_fotos_marcar_manual
