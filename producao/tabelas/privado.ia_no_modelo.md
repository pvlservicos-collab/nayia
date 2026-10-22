# privado.ia_no_modelo  (tabela, ~0 linhas)
470: o modelo escolhido para cada nó trocável (a página admin › Modelos); o serviço lê antes de chamar.

## colunas
no  text  NOT NULL
modelo  text  NOT NULL
trocado_por  text
trocado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX ia_no_modelo_pkey ON privado.ia_no_modelo USING btree (no)

## restrições
ia_no_modelo_pkey: PRIMARY KEY (no)

## permissões
(só o dono)

## funções que escrevem aqui
site_ia_modelo_trocar

## funções que citam
ia_modelo_do_no, site_ia_modelo_trocar, site_ia_modelos
