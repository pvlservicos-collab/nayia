# captacao_ficha_campos  (tabela, ~0 linhas)
327: a ficha da conversa analisada pelo modelo (nay-captacao/captacao/preparar.py): os campos do cadastro prontos para a tela de Cadastro rápido.

## colunas
ficha_id  bigint  NOT NULL
campos  jsonb  NOT NULL  padrão '{}'::jsonb
observacao  text
pronto  boolean
duplicado_de  bigint
ficha_atualizada_em  timestamp with time zone
analisado_em  timestamp with time zone  NOT NULL  padrão now()
modelo  text

## índices
CREATE UNIQUE INDEX captacao_ficha_campos_pkey ON public.captacao_ficha_campos USING btree (ficha_id)

## restrições
captacao_ficha_campos_ficha_id_fkey: FOREIGN KEY (ficha_id) REFERENCES captacao_cadastro(id) ON DELETE CASCADE
captacao_ficha_campos_pkey: PRIMARY KEY (ficha_id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
site_ficha_preparada
