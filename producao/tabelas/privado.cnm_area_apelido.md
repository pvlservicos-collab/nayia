# privado.cnm_area_apelido  (tabela, ~54 linhas)

## colunas
lista  text  NOT NULL
chave  text  NOT NULL
nome  text  NOT NULL

## índices
CREATE UNIQUE INDEX cnm_area_apelido_pkey ON privado.cnm_area_apelido USING btree (lista, chave, nome)

## restrições
cnm_area_apelido_lista_check: CHECK ((lista = ANY (ARRAY['comum'::text, 'privativa'::text])))
cnm_area_apelido_pkey: PRIMARY KEY (lista, chave, nome)

## permissões
(só o dono)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
cnm_areas
