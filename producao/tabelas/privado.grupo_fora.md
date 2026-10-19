# privado.grupo_fora  (tabela, ~0 linhas)
418: grupos que não são o mercado (os nossos): o leitor da captação ativa não lê, o radar/demanda/painel não contam.

## colunas
grupo_id  text
grupo_nome  text
motivo  text  NOT NULL
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX grupo_fora_id ON privado.grupo_fora USING btree (grupo_id) WHERE (grupo_id IS NOT NULL)

## restrições
grupo_fora_check: CHECK (((grupo_id IS NOT NULL) OR (grupo_nome IS NOT NULL)))

## permissões
(só o dono)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
