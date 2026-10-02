# nai_treino_julgamento  (tabela, ~22 linhas)

## colunas
caso_id  bigint  NOT NULL
veredito  text  NOT NULL
erro  text
solucao  text
aplicada_em  timestamp with time zone
aplicada_como  text
julgado_por  text
julgado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX nai_treino_julgamento_pkey ON public.nai_treino_julgamento USING btree (caso_id)

## restrições
nai_treino_julgamento_caso_id_fkey: FOREIGN KEY (caso_id) REFERENCES nai_treino_caso(id) ON DELETE CASCADE
nai_treino_julgamento_check: CHECK (((veredito = 'correto'::text) OR (NULLIF(btrim(COALESCE(erro, ''::text)), ''::text) IS NOT NULL) OR (NULLIF(btrim(COALESCE(solucao, ''::text)), ''::text) IS NOT NULL)))
nai_treino_julgamento_pkey: PRIMARY KEY (caso_id)
nai_treino_julgamento_veredito_check: CHECK ((veredito = ANY (ARRAY['correto'::text, 'errado'::text])))

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_conteudo: DELETE, INSERT, SELECT, UPDATE
nay_site_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
