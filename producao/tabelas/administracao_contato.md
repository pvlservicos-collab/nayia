# administracao_contato  (tabela, ~0 linhas)
Locadores e locatários da administração da Imob Easy (Tel, 21/10/2026). Não recebem captação nem aviso de lead/proprietário.

## colunas
telefone_chave  text  NOT NULL
telefone  text  NOT NULL
nome  text
papel  text  NOT NULL
imovel  text
relacionado_a  text
criado_em  timestamp with time zone  NOT NULL  padrão now()
criado_por  text
funcao  text

## índices
CREATE UNIQUE INDEX administracao_contato_pkey ON public.administracao_contato USING btree (telefone_chave)

## restrições
administracao_contato_papel_check: CHECK ((papel = ANY (ARRAY['locador'::text, 'locatario'::text, 'prestador'::text])))
administracao_contato_pkey: PRIMARY KEY (telefone_chave)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
