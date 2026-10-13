# privado.imovel_mudanca  (tabela, ~196 linhas)
361: o que a resposta do proprietário mudou (ou confirmou) no cadastro do imóvel, com a conversa e o de/para. Voltar atrás é marca na linha (desfeito_em), nada se apaga. Tela: Imóveis › Mudanças recentes e "Última atualização" no editar.

## colunas
id  bigint  NOT NULL  padrão nextval('privado.imovel_mudanca_id_seq'::regclass)
codigo  integer  NOT NULL
tipo  text  NOT NULL
origem  text  NOT NULL  padrão 'captacao'::text
lead_id  bigint
aplicado_id  bigint
dono  text
dito_em  timestamp with time zone
mensagens  jsonb  NOT NULL  padrão '[]'::jsonb
campos  jsonb  NOT NULL  padrão '{}'::jsonb   -- {campo: {de, para}} -- status, valor_aluguel, valor_venda, vencimento, publicado_no_site
antes  jsonb  NOT NULL  padrão '{}'::jsonb   -- o retrato do imóvel antes da mudança (situação, no site, trava, valores, vencimento): é o que o voltar atrás devolve
notas  text[]  NOT NULL  padrão '{}'::text[]
criado_em  timestamp with time zone  NOT NULL  padrão now()
revisado_em  timestamp with time zone
revisado_por  text
desfeito_em  timestamp with time zone
desfeito_por  text
desfeito_campos  text[]

## índices
CREATE INDEX imovel_mudanca_a_revisar ON privado.imovel_mudanca USING btree (id DESC) WHERE (revisado_em IS NULL)
CREATE INDEX imovel_mudanca_codigo ON privado.imovel_mudanca USING btree (codigo, id DESC)
CREATE UNIQUE INDEX imovel_mudanca_pkey ON privado.imovel_mudanca USING btree (id)

## restrições
imovel_mudanca_pkey: PRIMARY KEY (id)
imovel_mudanca_tipo_check: CHECK ((tipo = ANY (ARRAY['mudanca'::text, 'confirmacao'::text, 'nao_aplicado'::text])))

## permissões
(só o dono)

## funções que escrevem aqui
imovel_mudanca_registrar, imovel_mudanca_trocar, site_mudanca_revisar

## funções que citam
imovel_mudanca_registrar, imovel_mudanca_trocar, site_mudanca_revisar, site_mudancas
