# privado.cnm_envio_selecao  (tabela, ~0 linhas)
538: a escolha de imóveis publicada na URL do Chaves na Mão (uma linha); escrita só por cnm_envio_publicar

## colunas
id  integer  NOT NULL
ids  integer[]  NOT NULL  padrão '{}'::integer[]
destaques  integer[]  NOT NULL  padrão '{}'::integer[]
atualizado_em  timestamp with time zone  NOT NULL  padrão now()
atualizado_por  text

## índices
CREATE UNIQUE INDEX cnm_envio_selecao_pkey ON privado.cnm_envio_selecao USING btree (id)

## restrições
cnm_envio_selecao_id_check: CHECK ((id = 1))
cnm_envio_selecao_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
