-- =====================================================================
-- NAI -- 89: o nome dito de ouvido continua sendo o nosso imovel
-- (Tel, 22/09/2026)
--
-- Ele: "deixa ela entendida que quando o corretor mandar audio ou ate
-- escrever talvez ele erre o nome, mas como ele ja viu o nome no grupo ele
-- esta falando de um imovel nosso sim, entao ela faz uma assimilacao... mas
-- saindo o mesmo tom".
--
-- O que ja existia: nome inteiro (16/09), nucleo sem "Condominio" (86) e
-- chave de som exata (88). Ainda ficava de fora o nome PARECIDO, que e o que
-- sai de um audio ou de quem digita rapido:
--     "aquarele"        -> Acquarelle      (88 ja pegava)
--     "mirante da flor" -> Mirante das Flores
--     "park golfe"      -> Park Golf
--     "conquista rio"   -> Conquista Rio Negro
--
-- COMO: a frase e cortada em pedacos de 1 a 4 palavras, cada pedaco vira
-- chave de som, e cada chave e comparada com a dos 163 condominios do
-- catalogo. Vale por semelhanca (pg_trgm), com piso em 0,50 de 1 -- medido:
-- os acertos ficam bem acima do ruido ("mirante da flor" 0,55; "conquista
-- rio" 0,61; "park golfe" 0,73; "aquarele" 1,00 contra "casa do cliente"
-- 0,03 e "contrato assinado" 0,10). Vale tambem o nome dito pela METADE,
-- quando o pedaco (>= 9 letras) esta dentro do nome do cadastro.
--
-- O TOM NAO MUDA: isto so IDENTIFICA o imovel. Quem responde continua sendo
-- a mesma ferramenta de sempre -- card, lista ou "e venda ou locacao?" --,
-- entao ela fala igual, sem "voce quis dizer...".
--
-- SEGURANCA: pedaco com menos de 7 letras na chave nao entra (nome curto
-- casa com qualquer coisa), nome que e tipo de imovel continua fora, e
-- imovel de parceiro nunca aparece.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE VIEW vw_condominio_som AS
  SELECT nai_condominio_ok(i.condominio_nome) AS nome,
         nai_condominio_nucleo(nai_condominio_ok(i.condominio_nome)) AS nucleo,
         nai_chave_som(nai_condominio_nucleo(nai_condominio_ok(i.condominio_nome))) AS chave,
         array_agg(DISTINCT i.codigo) AS codigos
    FROM imoveis i
   WHERE nai_condominio_ok(i.condominio_nome) IS NOT NULL
     AND nai_condominio_ok(i.condominio_nome) !~ '/'
     AND lower(unaccent(nai_condominio_ok(i.condominio_nome))) NOT IN (
           SELECT lower(unaccent(x.tipo)) FROM imoveis x WHERE x.tipo IS NOT NULL)
     AND nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
     AND NOT coalesce(i.e_parceiro, false)
   GROUP BY 1, 2, 3;

-- os pedacos de 1 a 4 palavras da frase, ja em chave de som
CREATE OR REPLACE FUNCTION public.nai_pedacos_de_nome(p_texto text)
 RETURNS TABLE(chave text)
 LANGUAGE sql
 IMMUTABLE
AS $function$
  WITH palavras AS (
    SELECT regexp_split_to_array(
             btrim(regexp_replace(lower(unaccent(coalesce(p_texto, ''))), '[^a-z0-9]+', ' ', 'g')), ' ') AS p
  ), n AS (SELECT p, coalesce(array_length(p, 1), 0) AS q FROM palavras)
  SELECT DISTINCT nai_chave_som(array_to_string(p[i:i + j - 1], ' '))
    FROM n, generate_series(1, greatest(q, 1)) i, generate_series(1, 4) j
   WHERE i + j - 1 <= q;
$function$;

CREATE OR REPLACE FUNCTION public.nai_imovel_pelo_condominio(p_texto text, p_telefone text)
 RETURNS integer[]
 LANGUAGE sql
 STABLE
AS $function$
  -- O NOME ESCRITO CERTO MANDA. A parecenca e ULTIMO RECURSO: so entra quando
  -- nenhum nome bateu pela escrita. Sem isso, "Mirante das Flores" (2 imoveis)
  -- vinha com 5, porque condominio de nome parecido entrava junto -- e imovel
  -- a mais na resposta e imovel errado na mao do corretor.
  WITH certo AS (
    -- 1. nome inteiro, como esta no cadastro (16/09)
    SELECT v.codigos FROM vw_condominio_som v
     WHERE length(v.nome) >= 8
       AND position(lower(unaccent(v.nome)) IN lower(unaccent(coalesce(p_texto, '')))) > 0
    UNION ALL
    -- 2. o nucleo, sem Condominio/Residencial/Edificio (86)
    SELECT v.codigos FROM vw_condominio_som v
     WHERE length(coalesce(v.nucleo, '')) >= 8
       AND lower(unaccent(coalesce(p_texto, ''))) ~
           ('\m' || regexp_replace(v.nucleo, '([.^$*+?()\[\]{}|\-])', '\', 'g') || '\M')
    UNION ALL
    -- 3. a chave de som IGUAL (88): "aquarele" = Acquarelle
    SELECT v.codigos FROM vw_condominio_som v, nai_pedacos_de_nome(p_texto) g
     WHERE length(v.chave) >= 7 AND length(g.chave) >= 7
       AND (position(v.chave IN g.chave) > 0
            -- nome dito pela METADE vale quando e o COMECO do nome
            -- ("conquista rio" -> Conquista Rio Negro). Pedaco solto do meio
            -- nao vale: "das flores" esta dentro de meia duzia de condominios.
            OR (length(g.chave) >= 9 AND v.chave LIKE g.chave || '%'))
  ),
  -- 4. PARECIDO (89), so se nada acima bateu: fica com o(s) mais parecido(s)
  parecido AS (
    SELECT v.codigos, similarity(v.chave, g.chave) AS s
      FROM vw_condominio_som v, nai_pedacos_de_nome(p_texto) g
     WHERE NOT EXISTS (SELECT 1 FROM certo)
       AND length(v.chave) >= 7 AND length(g.chave) >= 7
       AND similarity(v.chave, g.chave) >= 0.50
  ),
  melhor AS (
    SELECT codigos FROM parecido
     WHERE s >= (SELECT max(s) - 0.05 FROM parecido)
  )
  SELECT coalesce((SELECT array_agg(DISTINCT c)
                     FROM (SELECT unnest(codigos) AS c FROM certo
                           UNION ALL
                           SELECT unnest(codigos) FROM melhor) x), '{}');
$function$;

COMMIT;

-- O QUE TEM QUE ACHAR                                        e o que NAO pode.
SELECT t AS frase, nai_imovel_pelo_condominio(t, '') AS imoveis
  FROM unnest(ARRAY[
    'O teu aquarele para locação ainda está disponível? O de uma suíte?',
    'o mirante da flor ainda ta disponivel?',
    'tem no park golfe?',
    'e no conquista rio, tem alguma coisa?',
    'Nay. Àquele Acquarelle de 2 qts ! 3.500 ainda tá disponível?',
    'bom dia, tudo bem?',
    'Mobiliada',
    'vou passar na casa do meu cliente hoje',
    'o cliente quer 3 quartos ate 4 mil',
    'obrigado, boa noite',
    'ja mandei o contrato para o proprietario assinar'
  ]) t;
