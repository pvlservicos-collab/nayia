# privado.cnm_area  (tabela, ~852 linhas)
458: as listas oficiais do Chaves na Mão (chavesnamao.com.br/imoveis/integracao/areas_comuns e /areas_privativas, lidas em 21/10/2026).

## colunas
lista  text  NOT NULL
nome  text  NOT NULL
chave  text  NOT NULL

## índices
CREATE INDEX cnm_area_chave ON privado.cnm_area USING btree (lista, chave)
CREATE UNIQUE INDEX cnm_area_pkey ON privado.cnm_area USING btree (lista, nome)

## restrições
cnm_area_lista_check: CHECK ((lista = ANY (ARRAY['comum'::text, 'privativa'::text])))
cnm_area_pkey: PRIMARY KEY (lista, nome)

## permissões
(só o dono)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
cnm_areas
