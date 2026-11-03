# privado.busca_grupo_membro  (tabela, ~1183 linhas)

## colunas
telefone8  text  NOT NULL
telefone  text  NOT NULL
grupos  text[]  NOT NULL  padrão '{}'::text[]
atualizado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX busca_grupo_membro_pkey ON privado.busca_grupo_membro USING btree (telefone8)

## restrições
busca_grupo_membro_pkey: PRIMARY KEY (telefone8)

## permissões
(só o dono)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
busca_corretor_e, olx_organicos_novos
