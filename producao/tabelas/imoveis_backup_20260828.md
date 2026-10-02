# imoveis_backup_20260828  (tabela, ~1201 linhas)

## colunas
codigo  integer
tipo  text
status  text
condo_id  integer
condominio_nome  text
bairro  text
cidade  text
estado  text
logradouro  text
numero  text
complemento  text
cep  text
area_util  numeric
area_total  numeric
quartos  integer
suites  integer
banheiros  integer
vagas  integer
vagas_cobertas  integer
sol  text
andar  text
valor_venda  numeric
valor_aluguel  numeric
taxa_condominio  numeric
iptu  numeric
mobilia  text
descricao  text
caracteristicas  text[]
origem  text
publicado_no_site  boolean
disponivel  boolean
bloqueado  boolean
motivo_bloqueio  text
sincronizado_em  timestamp with time zone
criado_em  timestamp with time zone
e_parceiro  boolean
travado  boolean
travado_motivo  text
travado_em  timestamp with time zone
extras  jsonb
captado_por  text
captado_em  text
precisa_confirmacao  boolean

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
