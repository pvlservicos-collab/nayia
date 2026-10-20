# privado.visita_parceria_grupo  (tabela, ~0 linhas)

## colunas
visita_id  bigint  NOT NULL
assinatura  text
checklist_em  timestamp with time zone
alerta_dono_em  timestamp with time zone
alerta_sem_resposta_em  timestamp with time zone
atualizado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX visita_parceria_grupo_pkey ON privado.visita_parceria_grupo USING btree (visita_id)

## restrições
visita_parceria_grupo_pkey: PRIMARY KEY (visita_id)

## permissões
(só o dono)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
