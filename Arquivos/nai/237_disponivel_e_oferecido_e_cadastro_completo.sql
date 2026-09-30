-- 237 (30/09/2026): DISPONÍVEL É OFERECIDO, E O CADASTRO RECEBE O QUE JÁ ESTAVA GUARDADO.
-- Pedro: "uns imóveis novos dizem 'A Nay não oferece esse imóvel' sendo que ele tá
-- marcado como disponível quando eu clico em editar ... corrija isso para a Nay
-- oferecer" e "revise todos os imóveis ... tá faltando informação ... quero o banco 100%".
--
-- 1. DISPONÍVEL ESCONDIDO. 17 imóveis nossos com situação "Disponível" estavam com
--    publicado_no_site = false: a leitura diária do site antigo despublica o que não
--    acha no .com, e a Nay só oferece o que está publicado. A regra do Tel (27/09) é
--    "nosso e Disponível fica no site e na Nay". Eles voltam, TRAVADOS (a leitura
--    diária não desfaz). O 5747 continua bloqueado: é um cadastro da secretária que
--    saiu torto (o corretor descrevia a carteira dele), bloqueado de propósito em 23/09.
--
-- 2. CONFERÊNCIA COM A PLANILHA DO SITE ANTIGO (5.647 imóveis): para os 277 que a Nay
--    oferece, a planilha não tem NADA que o banco não tenha (tipo, endereço, quartos,
--    banheiros, suítes, vagas, áreas, valores, condomínio, proprietário). A coluna
--    "Vagas" da planilha é a de vagas COBERTAS; o banco tem o total, do anúncio.
--
-- 3. O QUE ESTAVA GUARDADO E NÃO TINHA IDO PARA O CADASTRO (ficha do anúncio,
--    imovel_ficha, e os campos extras da raspagem) entra agora, só onde está vazio:
--    características, mobília (pelas etiquetas do anúncio: Mobiliado, Semi-Mobiliado,
--    Climatizado), sol, taxa de condomínio, IPTU e vagas. A "descrição" da ficha é um
--    texto automático ("Apartamento localizado no condomínio X - 3 quartos...") e NÃO
--    entra: encheria o campo sem dizer nada novo.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TEMP TABLE alvo ON COMMIT DROP AS
SELECT i.codigo FROM imoveis i
 WHERE NOT coalesce(i.e_parceiro, false)
   AND (nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
        OR (i.status = 'Disponível' AND NOT coalesce(i.bloqueado, false)));

-- 1 ---------------------------------------------------------------- disponível = oferecido
UPDATE imoveis i
   SET publicado_no_site = true, disponivel = true,
       travado = true, travado_em = now(),
       travado_motivo = coalesce(nullif(i.travado_motivo, '') || ' · ', '') || 'Disponível no admin: o Pedro mandou a Nay oferecer (30/09)'
 WHERE i.status = 'Disponível' AND NOT coalesce(i.e_parceiro, false) AND NOT coalesce(i.bloqueado, false)
   AND NOT nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site);

-- 2 ---------------------------------------------------------------- o que estava guardado
CREATE OR REPLACE FUNCTION pg_temp.reais(p text) RETURNS numeric LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN x ~ '^[0-9]+([.,][0-9]+)?$' THEN replace(x, ',', '.')::numeric END
    FROM (SELECT replace(regexp_replace(regexp_replace(coalesce(p, ''), '[^0-9.,]', '', 'g'), '\.(?=[0-9]{3}(\D|$))', '', 'g'), ',', '.') AS x) t
$$;

-- características: as do imóvel e as do condomínio, do anúncio
UPDATE imoveis i
   SET caracteristicas = (SELECT array_agg(DISTINCT btrim(c) ORDER BY btrim(c))
                            FROM unnest(coalesce(f.caracteristicas_imovel, '{}') || coalesce(f.caracteristicas_condominio, '{}')) c
                           WHERE btrim(c) <> ''),
       extras = CASE WHEN coalesce(cardinality(f.caracteristicas_condominio), 0) > 0
                          AND NOT (coalesce(i.extras, '{}'::jsonb) ? 'caracteristicas do condominio')
                     THEN coalesce(i.extras, '{}'::jsonb) || jsonb_build_object('caracteristicas do condominio', array_to_string(f.caracteristicas_condominio, ', '))
                     ELSE i.extras END
  FROM public.imovel_ficha f, alvo a
 WHERE a.codigo = i.codigo AND f.codigo = i.codigo
   AND coalesce(cardinality(i.caracteristicas), 0) = 0
   AND coalesce(cardinality(f.caracteristicas_imovel), 0) + coalesce(cardinality(f.caracteristicas_condominio), 0) > 0;

-- mobília: só pelo que o anúncio diz com todas as letras (os 3 textos do banco)
UPDATE imoveis i
   SET mobilia = CASE WHEN t ~ '\msemi[- ]?mobiliad' THEN 'semi-mobiliado (moveis planejados + ar)'
                      WHEN t ~ '\mmobiliad' THEN 'mobiliado (moveis + cama + tudo)'
                      ELSE 'so ar-condicionado' END
  FROM (SELECT a.codigo, lower(unaccent(array_to_string(coalesce(f.caracteristicas_imovel, '{}') || coalesce(i2.caracteristicas, '{}'), ' | '))) AS t
          FROM alvo a JOIN imoveis i2 ON i2.codigo = a.codigo LEFT JOIN public.imovel_ficha f ON f.codigo = a.codigo) x
 WHERE x.codigo = i.codigo AND coalesce(btrim(i.mobilia), '') = ''
   AND (x.t ~ '\m(semi[- ]?)?mobiliad' OR x.t ~ '\m(climatizad|ar[- ]condicionado)')
   AND x.t !~ '\m(sem|nao)\s+mobili';

-- sol, taxa de condomínio, IPTU e vagas: dos extras da raspagem ou da ficha do anúncio
UPDATE imoveis i
   SET sol = initcap(btrim(v.sol))
  FROM (SELECT a.codigo, coalesce(nullif(btrim(i2.extras->>'sol'), ''), nullif(btrim(f.campos->>'sol'), '')) AS sol
          FROM alvo a JOIN imoveis i2 ON i2.codigo = a.codigo LEFT JOIN public.imovel_ficha f ON f.codigo = a.codigo) v
 WHERE v.codigo = i.codigo AND coalesce(btrim(i.sol), '') = '' AND v.sol IS NOT NULL;

UPDATE imoveis i
   SET taxa_condominio = v.tx
  FROM (SELECT a.codigo, coalesce(pg_temp.reais(i2.extras->>'taxa de condominio'), pg_temp.reais(f.campos->>'taxa de condominio')) AS tx
          FROM alvo a JOIN imoveis i2 ON i2.codigo = a.codigo LEFT JOIN public.imovel_ficha f ON f.codigo = a.codigo) v
 WHERE v.codigo = i.codigo AND i.taxa_condominio IS NULL AND v.tx > 0;

UPDATE imoveis i
   SET iptu = v.iptu
  FROM (SELECT a.codigo, coalesce(pg_temp.reais(i2.extras->>'iptu'), pg_temp.reais(f.campos->>'iptu')) AS iptu
          FROM alvo a JOIN imoveis i2 ON i2.codigo = a.codigo LEFT JOIN public.imovel_ficha f ON f.codigo = a.codigo) v
 WHERE v.codigo = i.codigo AND i.iptu IS NULL AND v.iptu > 0;

UPDATE imoveis i
   SET vagas = v.vagas
  FROM (SELECT a.codigo, coalesce(nullif(btrim(i2.extras->>'vagas'), ''), nullif(btrim(f.campos->>'vagas'), '')) AS txt
          FROM alvo a JOIN imoveis i2 ON i2.codigo = a.codigo LEFT JOIN public.imovel_ficha f ON f.codigo = a.codigo) x,
       LATERAL (SELECT CASE WHEN x.txt ~ '^[0-9]{1,2}$' THEN x.txt::int END AS vagas) v
 WHERE x.codigo = i.codigo AND i.vagas IS NULL AND v.vagas IS NOT NULL;
-- a bateria acompanha o catálogo: o 5326 (outra unidade do Conquista Tarumã) voltou a ser oferecido
UPDATE nai_caso SET esperado = '{5718,5326,5722}'
 WHERE regra = 'pediu dois, recebe os dois' AND esperado = '{5718,5722}';
COMMIT;
