# privado.visita_ponte_aviso  (tabela, ~0 linhas)

## colunas
core_saida_id  bigint  NOT NULL
avisado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX visita_ponte_aviso_pkey ON privado.visita_ponte_aviso USING btree (core_saida_id)

## restrições
visita_ponte_aviso_pkey: PRIMARY KEY (core_saida_id)

## permissões
(só o dono)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
