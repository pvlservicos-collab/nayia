# privado.captacao_indicacao  (tabela, ~0 linhas)
315: quem o proprietário indicou na captação (alguém que está vendendo um imóvel)

## colunas
id  bigint  NOT NULL  padrão nextval('privado.captacao_indicacao_id_seq'::regclass)
lead_id  bigint
telefone  text  NOT NULL
nome  text
contato  text
detalhe  text
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX captacao_indicacao_lead ON privado.captacao_indicacao USING btree (lead_id, criado_em DESC)
CREATE UNIQUE INDEX captacao_indicacao_pkey ON privado.captacao_indicacao USING btree (id)

## restrições
captacao_indicacao_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
captacao_indicacao_guardar

## funções que citam
captacao_indicacao_guardar
