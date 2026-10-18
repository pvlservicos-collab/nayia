# whats_modelo_nota  (tabela, ~0 linhas)

## colunas
nome  text  NOT NULL
idioma  text  NOT NULL  padrão 'pt_BR'::text
etiquetas  text[]  NOT NULL  padrão '{}'::text[]
observacao  text
atualizado_por  text
atualizado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX whats_modelo_nota_pkey ON public.whats_modelo_nota USING btree (nome, idioma)

## restrições
whats_modelo_nota_pkey: PRIMARY KEY (nome, idioma)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
site_whats_modelo_nota_salvar

## funções que citam
site_whats_modelo_nota_salvar, site_whats_modelos_notas
