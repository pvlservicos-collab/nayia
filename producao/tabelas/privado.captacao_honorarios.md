# privado.captacao_honorarios  (tabela, ~0 linhas)
324: o que o proprietário respondeu sobre os 6% de honorários de corretagem no valor de venda (a última pergunta da captação)

## colunas
id  bigint  NOT NULL  padrão nextval('privado.captacao_honorarios_id_seq'::regclass)
lead_id  bigint
telefone  text  NOT NULL
valor  text
resposta  text  NOT NULL
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX captacao_honorarios_lead ON privado.captacao_honorarios USING btree (lead_id, criado_em DESC)
CREATE UNIQUE INDEX captacao_honorarios_pkey ON privado.captacao_honorarios USING btree (id)

## restrições
captacao_honorarios_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
captacao_honorarios_guardar

## funções que citam
captacao_honorarios_depois_de, captacao_honorarios_guardar, captacao_honorarios_tipo
