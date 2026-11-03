# privado.grupo_mensagem_lida  (tabela, ~11708 linhas)

## colunas
fonte  text  NOT NULL
ref  text  NOT NULL
lida_em  timestamp with time zone  NOT NULL  padrão now()
pedidos  integer  NOT NULL  padrão 0
motivo  text
erro  text
tentativas  integer  NOT NULL  padrão 1
modelo  text

## índices
CREATE UNIQUE INDEX grupo_mensagem_lida_pkey ON privado.grupo_mensagem_lida USING btree (fonte, ref)

## restrições
grupo_mensagem_lida_fonte_check: CHECK ((fonte = ANY (ARRAY['grupo'::text, 'teste'::text])))
grupo_mensagem_lida_pkey: PRIMARY KEY (fonte, ref)

## permissões
(só o dono)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
site_captacao_grupos, site_captacao_grupos_teste_lido
