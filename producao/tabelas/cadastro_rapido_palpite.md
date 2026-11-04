# cadastro_rapido_palpite  (tabela, ~192 linhas)
332: o palpite da IA para cada item da fila do Cadastro rápido (nay-captacao/captacao/palpite.py). Só triagem: a tela ordena e filtra por ele.

## colunas
fonte  text  NOT NULL
item  bigint  NOT NULL
categoria  text  NOT NULL
porque  text
base  text  NOT NULL
analisado_em  timestamp with time zone  NOT NULL  padrão now()
modelo  text

## índices
CREATE UNIQUE INDEX cadastro_rapido_palpite_pkey ON public.cadastro_rapido_palpite USING btree (fonte, item)

## restrições
cadastro_rapido_palpite_categoria_check: CHECK ((categoria = ANY (ARRAY['novo'::text, 'atualizacao'::text, 'completar'::text, 'indisponivel'::text, 'repetido'::text, 'nao_e'::text])))
cadastro_rapido_palpite_fonte_check: CHECK ((fonte = ANY (ARRAY['ficha'::text, 'imovel'::text])))
cadastro_rapido_palpite_pkey: PRIMARY KEY (fonte, item)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_escrita: SELECT
nay_site_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
site_aprovar_imoveis
