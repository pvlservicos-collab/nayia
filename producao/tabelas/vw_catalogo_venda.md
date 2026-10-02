# vw_catalogo_venda  (view, ~0 linhas)
190: os imóveis de VENDA (valor_venda > 0). Conversa de venda só recebe daqui; o gatilho nai_saida_validar barra o resto.

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
administrado  boolean
proprietario_id  integer
fotos_conferidas_em  timestamp with time zone

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 SELECT codigo,
    tipo,
    status,
    condo_id,
    condominio_nome,
    bairro,
    cidade,
    estado,
    logradouro,
    numero,
    complemento,
    cep,
    area_util,
    area_total,
    quartos,
    suites,
    banheiros,
    vagas,
    vagas_cobertas,
    sol,
    andar,
    valor_venda,
    valor_aluguel,
    taxa_condominio,
    iptu,
    mobilia,
    descricao,
    caracteristicas,
    origem,
    publicado_no_site,
    disponivel,
    bloqueado,
    motivo_bloqueio,
    sincronizado_em,
    criado_em,
    e_parceiro,
    travado,
    travado_motivo,
    travado_em,
    extras,
    captado_por,
    captado_em,
    precisa_confirmacao,
    administrado,
    proprietario_id,
    fotos_conferidas_em
   FROM imoveis i
  WHERE COALESCE(valor_venda, 0::numeric) > 0::numeric;
