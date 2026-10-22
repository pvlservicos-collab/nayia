# privado.visita_lembrete_grupo  (tabela, ~0 linhas)
466: a visita que já teve o lembrete de 1 hora antes no grupo Altarquia.

## colunas
visita_id  bigint  NOT NULL
em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX visita_lembrete_grupo_pkey ON privado.visita_lembrete_grupo USING btree (visita_id)

## restrições
visita_lembrete_grupo_pkey: PRIMARY KEY (visita_id)

## permissões
(só o dono)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
