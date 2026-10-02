# nai_treino_painel_v2  (view, ~0 linhas)

## colunas
bloco_id  bigint
conversa_id  bigint
rodada_id  bigint
nome  text
motivo  text
estado_conversa  text
ordem  integer
quando_original  timestamp with time zone
ele_disse  text
ela_antes  text
fotos_antes  integer
ela_agora  text
fotos_agora  integer
ferramentas  text[]
intencao  text
confianca  real
atendente  text
cortes  text
estado  text
erro  text
mudou  boolean
parou_de_mandar_foto  boolean
veredito  text
julgamento_erro  text
julgamento_solucao  text
julgado_em  timestamp with time zone

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_conteudo: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 SELECT b.id AS bloco_id,
    c.id AS conversa_id,
    c.rodada_id,
    c.nome,
    c.motivo,
    c.estado AS estado_conversa,
    b.ordem,
    b.quando_original,
    b.ele_disse,
    b.ela_antes,
    b.fotos_antes,
    b.ela_agora,
    b.fotos_agora,
    b.ferramentas,
    b.intencao,
    b.confianca,
    b.atendente,
    b.cortes,
    b.estado,
    b.erro,
    b.estado = 'rodado'::text AND btrim(COALESCE(b.ela_agora, ''::text)) IS DISTINCT FROM btrim(COALESCE(b.ela_antes, ''::text)) AS mudou,
    b.fotos_antes > 0 AND b.fotos_agora = 0 AS parou_de_mandar_foto,
    j.veredito,
    j.erro AS julgamento_erro,
    j.solucao AS julgamento_solucao,
    j.julgado_em
   FROM nai_treino_bloco b
     JOIN nai_treino_conversa c ON c.id = b.conversa_id
     LEFT JOIN nai_treino_bloco_julgamento j ON j.bloco_id = b.id;
