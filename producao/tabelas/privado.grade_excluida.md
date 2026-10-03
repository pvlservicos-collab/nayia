# privado.grade_excluida  (tabela, ~0 linhas)
279: cópia de cada vaga da grade apagada pelo site (para desfazer à mão).

## colunas
id  bigint  NOT NULL  padrão nextval('privado.grade_excluida_id_seq'::regclass)
vaga  jsonb  NOT NULL
excluida_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX grade_excluida_pkey ON privado.grade_excluida USING btree (id)

## restrições
grade_excluida_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
site_grade_excluir

## funções que citam
site_grade_excluir
