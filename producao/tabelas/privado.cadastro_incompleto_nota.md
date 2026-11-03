# privado.cadastro_incompleto_nota  (tabela, ~0 linhas)
571: a nota do imóvel de cada cadastro incompleto (captacao_cadastro coletando) pela procura: pedidos dos grupos (30 dias, nota 90+ e 70+) e buscas de clientes nossos. Gravada por nay-grupos/scripts/nota_cadastros.py.

## colunas
cadastro_id  bigint  NOT NULL
nota  integer  NOT NULL
pedidos_90  integer  NOT NULL  padrão 0
pedidos_70  integer  NOT NULL  padrão 0
clientes  integer  NOT NULL  padrão 0
melhor  jsonb
calculada_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX cadastro_incompleto_nota_pkey ON privado.cadastro_incompleto_nota USING btree (cadastro_id)

## restrições
cadastro_incompleto_nota_nota_check: CHECK (((nota >= 0) AND (nota <= 100)))
cadastro_incompleto_nota_pkey: PRIMARY KEY (cadastro_id)

## permissões
(só o dono)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
crm_cadastros_incompletos
