# nai_regra_sugerida_caso  (tabela, ~52 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('nai_regra_sugerida_caso_id_seq'::regclass)
sugestao_id  bigint  NOT NULL
quem  text
chave  text
quando  timestamp with time zone
turno_id  bigint
ele_disse  text
ela_disse  text
o_ponto  text

## índices
CREATE INDEX nai_regra_sugerida_caso_da_sugestao ON public.nai_regra_sugerida_caso USING btree (sugestao_id, quando)
CREATE UNIQUE INDEX nai_regra_sugerida_caso_pkey ON public.nai_regra_sugerida_caso USING btree (id)

## restrições
nai_regra_sugerida_caso_pkey: PRIMARY KEY (id)
nai_regra_sugerida_caso_sugestao_id_fkey: FOREIGN KEY (sugestao_id) REFERENCES nai_regra_sugerida(id) ON DELETE CASCADE

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_conteudo: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
