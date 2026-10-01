-- 246 (01/10/2026): O CARD DA CAPTAÇÃO PASSA A FAZER O CADASTRO INTEIRO.
-- Pedro: "remontagem completa do card de corretor... o imóvel dele que temos
-- cadastrado no sistema, e uma opção de alterar os dados do imóvel dele lá pelo
-- card, e uma opção de cadastrar novo imóvel que abre um popup... posso puxar da
-- lista dos que estão em pré cadastro na OLX... quero uma lista de condomínios
-- detalhada com os endereços dos condomínios para selecionar, mas se o corretor
-- já disse eu clico em preencher automático... e esse popup vai ter ali encima
-- uma porcentagem que vai se preenchendo conforme eu vou adicionando informações".
--
-- Quatro LEITURAS para o CRM (o papel nay_disparo só executa função crm_*):
--
--   crm_captacao_cadastro_opcoes()   o que o popup oferece numa chamada:
--                                    condomínios com endereço, características
--                                    já em uso, tipos, bairros e o pré-cadastro
--                                    (status Rascunho) que dá para puxar.
--   crm_condominio_pelo_texto(t)     o "preencher automático": o condomínio que
--                                    o corretor disse na conversa, pelo núcleo
--                                    do nome (nai_condominio_nucleo), nunca por
--                                    palavra de 3 letras.
--   crm_imoveis_pontuacao(int[])     quanto cada imóvel está preenchido (244),
--                                    para o card mostrar a barra em cada um.
--   crm_imovel_para_cadastro(int)    os campos de hoje de um imóvel, para o
--                                    popup abrir já preenchido e editar.
--
-- DE ONDE SAI O ENDEREÇO DO CONDOMÍNIO: a tabela `condominios` tem só id, nome
-- e bairro. O endereço vem da `condominio_ficha` quando existe e, senão, da
-- moda do logradouro dos imóveis já ligados ao condomínio -- com `base` dizendo
-- de quantos imóveis veio, para quem preenche conferir em vez de confiar.
-- Nada aqui escreve: quem grava é a API do site, com a senha de máquina.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION public.crm_captacao_cadastro_opcoes()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
  WITH dos_imoveis AS (
    SELECT i.condo_id,
           count(*)                                                                   AS imoveis,
           count(*) FILTER (WHERE coalesce(i.logradouro, '') <> '')                    AS base,
           mode() WITHIN GROUP (ORDER BY i.logradouro) FILTER (WHERE coalesce(i.logradouro, '') <> '') AS logradouro,
           mode() WITHIN GROUP (ORDER BY i.bairro)     FILTER (WHERE coalesce(i.bairro, '') <> '')     AS bairro,
           mode() WITHIN GROUP (ORDER BY i.cidade)     FILTER (WHERE coalesce(i.cidade, '') <> '')     AS cidade,
           mode() WITHIN GROUP (ORDER BY i.estado)     FILTER (WHERE coalesce(i.estado, '') <> '')     AS estado
      FROM imoveis i
     WHERE i.condo_id IS NOT NULL
     GROUP BY i.condo_id
  ),
  conds AS (
    SELECT c.id, c.nome,
           coalesce(nullif(btrim(c.bairro), ''), d.bairro)                   AS bairro,
           coalesce(nullif(btrim(f.endereco), ''), d.logradouro)             AS endereco,
           CASE WHEN nullif(btrim(f.endereco), '') IS NOT NULL THEN 'ficha'
                WHEN d.logradouro IS NOT NULL THEN 'imoveis' END             AS endereco_de,
           coalesce(d.base, 0)                                               AS base,
           coalesce(d.cidade, 'Manaus')                                      AS cidade,
           coalesce(d.estado, 'AM')                                          AS estado,
           coalesce(d.imoveis, 0)                                            AS imoveis,
           nullif(btrim(f.andares), '')                                       AS andares,
           nullif(btrim(f.elevador), '')                                      AS elevador,
           nullif(btrim(f.torres), '')                                        AS torres,
           nullif(btrim(f.construtora), '')                                   AS construtora,
           coalesce(f.lazer, '{}'::text[])                                    AS lazer
      FROM condominios c
      LEFT JOIN dos_imoveis d ON d.condo_id = c.id
      LEFT JOIN condominio_ficha f ON f.condominio_id = c.id
  ),
  carac AS (
    SELECT x AS nome, count(*) AS usos
      FROM imoveis, unnest(caracteristicas) x
     WHERE btrim(x) <> ''
     GROUP BY x
  ),
  -- O PRÉ-CADASTRO: todo imóvel que está em Rascunho (o que entra pela OLX fica
  -- assim até alguém cadastrar). `origem` diz de onde veio: 'olx', 'site',
  -- 'captacao', a planilha do site antigo.
  rascunhos AS (
    SELECT i.codigo, coalesce(nullif(btrim(i.tipo), ''), '')           AS tipo,
           coalesce(nullif(btrim(i.bairro), ''), '')                    AS bairro,
           coalesce(nullif(btrim(i.condominio_nome), ''), '')           AS condominio,
           i.condo_id, coalesce(i.origem, '')                           AS origem,
           coalesce(i.valor_aluguel, 0)                                 AS aluguel,
           coalesce(i.valor_venda, 0)                                   AS venda,
           (SELECT count(*) FROM imovel_fotos f WHERE f.codigo = i.codigo) AS fotos,
           p.nome                                                       AS dono,
           i.criado_em
      FROM imoveis i
      LEFT JOIN proprietarios p ON p.id = i.proprietario_id
     WHERE i.status = 'Rascunho'
  )
  SELECT jsonb_build_object(
    'condominios', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'id', id, 'nome', nome, 'bairro', bairro, 'endereco', endereco, 'enderecoDe', endereco_de,
        'base', base, 'cidade', cidade, 'estado', estado, 'imoveis', imoveis,
        'andares', andares, 'elevador', elevador, 'torres', torres, 'construtora', construtora,
        'lazer', to_jsonb(lazer)) ORDER BY nome) FROM conds), '[]'::jsonb),
    'caracteristicas', coalesce((SELECT jsonb_agg(jsonb_build_object('nome', nome, 'usos', usos)
        ORDER BY usos DESC, nome) FROM carac), '[]'::jsonb),
    'tipos', coalesce((SELECT jsonb_agg(DISTINCT btrim(tipo)) FROM imoveis WHERE coalesce(btrim(tipo), '') <> ''), '[]'::jsonb),
    'bairros', coalesce((SELECT jsonb_agg(b ORDER BY b) FROM (
        SELECT DISTINCT btrim(bairro) AS b FROM imoveis WHERE coalesce(btrim(bairro), '') <> '') x), '[]'::jsonb),
    'rascunhos', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'codigo', codigo, 'tipo', tipo, 'bairro', bairro, 'condominio', condominio, 'condoId', condo_id,
        'origem', origem, 'aluguel', aluguel, 'venda', venda, 'fotos', fotos, 'dono', dono,
        'criado', criado_em) ORDER BY criado_em DESC NULLS LAST, codigo DESC) FROM rascunhos), '[]'::jsonb)
  )
$function$;
COMMENT ON FUNCTION crm_captacao_cadastro_opcoes() IS '246: o que o popup de cadastro do card da captação oferece (condomínios com endereço, características, pré-cadastro)';
REVOKE ALL ON FUNCTION crm_captacao_cadastro_opcoes() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm_captacao_cadastro_opcoes() TO nay_disparo;

-- O "PREENCHER AUTOMÁTICO": o condomínio que o corretor disse na conversa.
-- Só pelo NÚCLEO do nome (sem "condomínio", "residencial", "edifício"), com 4
-- letras ou mais -- senão "Sol" e "Vip" casariam com meia Manaus.
CREATE OR REPLACE FUNCTION public.crm_condominio_pelo_texto(p_texto text)
 RETURNS TABLE(id integer, nome text, bairro text, forca numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH t AS (SELECT ' ' || nay_sem_acento(lower(coalesce(p_texto, ''))) || ' ' AS s),
  n AS (
    SELECT c.id, c.nome, c.bairro,
           nay_sem_acento(lower(nai_condominio_nucleo(c.nome))) AS nucleo
      FROM condominios c
  )
  SELECT n.id, n.nome, n.bairro, (length(n.nucleo))::numeric AS forca
    FROM n, t
   WHERE length(n.nucleo) >= 4
     AND t.s ~ ('(^|[^a-z0-9])' || regexp_replace(n.nucleo, '([.^$*+?()\[\]{}|\\])', '\\\1', 'g') || '([^a-z0-9]|$)')
   ORDER BY 4 DESC, n.nome
   LIMIT 5
$function$;
COMMENT ON FUNCTION crm_condominio_pelo_texto(text) IS '246: o condomínio citado num texto, pelo núcleo do nome (botão Preencher automático)';
REVOKE ALL ON FUNCTION crm_condominio_pelo_texto(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm_condominio_pelo_texto(text) TO nay_disparo;

-- A BARRA DE CADA IMÓVEL NO CARD: a mesma régua da aba Imóveis (244).
CREATE OR REPLACE FUNCTION public.crm_imoveis_pontuacao(p_codigos integer[])
 RETURNS TABLE(codigo integer, pct integer, falta text[], falta_essencial text[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT v.codigo, v.pct, v.falta, v.falta_essencial
    FROM vw_imovel_pontuacao v
   WHERE v.codigo = ANY (coalesce(p_codigos, '{}'::integer[]))
$function$;
REVOKE ALL ON FUNCTION crm_imoveis_pontuacao(integer[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm_imoveis_pontuacao(integer[]) TO nay_disparo;

-- OS CAMPOS DE HOJE, para o popup abrir preenchido quando é "alterar os dados".
CREATE OR REPLACE FUNCTION public.crm_imovel_para_cadastro(p_codigo integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT jsonb_build_object(
    'codigo', i.codigo, 'status', i.status, 'origem', i.origem,
    'tipo', i.tipo, 'bairro', i.bairro, 'condominio', i.condominio_nome, 'condoId', i.condo_id,
    'logradouro', i.logradouro, 'numero', i.numero, 'complemento', i.complemento,
    'cidade', i.cidade, 'estado', i.estado,
    'quartos', i.quartos, 'suites', i.suites, 'banheiros', i.banheiros,
    'vagas', i.vagas, 'vagasCobertas', i.vagas_cobertas,
    'areaUtil', i.area_util, 'areaTotal', i.area_total,
    'andar', i.andar, 'sol', i.sol, 'mobilia', i.mobilia,
    'taxaCondominio', i.taxa_condominio, 'iptu', i.iptu,
    'aluguel', i.valor_aluguel, 'venda', i.valor_venda,
    'caracteristicas', to_jsonb(coalesce(i.caracteristicas, '{}'::text[])),
    'descricao', i.descricao,
    'inclusoNoAluguel', i.extras->>'incluso no aluguel',
    'temDono', i.proprietario_id IS NOT NULL,
    'dono', (SELECT p.nome FROM proprietarios p WHERE p.id = i.proprietario_id),
    'fotos', (SELECT count(*) FROM imovel_fotos f WHERE f.codigo = i.codigo),
    'pontuacao', nai_imovel_pontos(i.codigo))
    FROM imoveis i
   WHERE i.codigo = p_codigo
$function$;
COMMENT ON FUNCTION crm_imovel_para_cadastro(integer) IS '246: os campos de um imóvel para o popup do card da captação editar';
REVOKE ALL ON FUNCTION crm_imovel_para_cadastro(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm_imovel_para_cadastro(integer) TO nay_disparo;
COMMIT;
