-- 310 (08/10/2026): OUTRO CONDOMÍNIO NA MESMA RUA NÃO É "JÁ TEMOS".
-- Apareceu nas primeiras consultas de verdade do bot da OLX (08/10, 00:11): dois
-- anúncios na MESMA rua e no MESMO CEP (Rua Heisei, Novo Aleixo), um do Vista do
-- Oriente e outro do Condomínio Realize. A 309 tratava "rua ou CEP igual" como o
-- mesmo lugar; numa rua com vários condomínios de planta parecida, um imóvel
-- nosso no mercado com a mesma área e o mesmo preço fecharia o anúncio de OUTRO
-- prédio como "já temos" -- e o proprietário novo ficaria sem abordagem.
--
-- A REGRA: quando o anúncio diz o condomínio e o nosso imóvel tem OUTRO
-- condomínio (nome próprio dos dois lados, e diferentes -- é o
-- `campos_divergentes: condominio_nome` da 258), rua e CEP não valem como lugar e
-- o caminho por bairro também não fecha. Continua fechando por link e por
-- condomínio igual. Nenhuma das 8 consultas já gravadas muda de resposta.
--
-- Patch na função viva (pg_get_functiondef), cada troca conferida uma vez.
BEGIN;
SET LOCAL lock_timeout = '3s';

DO $do$
DECLARE
  v_def text := pg_get_functiondef('public.crm_anuncio_mesma_unidade(jsonb,jsonb)'::regprocedure);
  v_par text[];
  PARES CONSTANT text[] := ARRAY[
    -- 1. o candidato traz se o condomínio DIVERGE do anúncio
    $a$coalesce(x -> 'campos_que_bateram', '[]'::jsonb) AS bateu,$a$,
    $b$coalesce(x -> 'campos_que_bateram', '[]'::jsonb) AS bateu,
           (coalesce(x -> 'campos_divergentes', '[]'::jsonb) @> '[{"campo": "condominio_nome"}]'::jsonb) AS x_condo,$b$,
    -- 2. rua e CEP só são o mesmo lugar se o condomínio não diverge
    $a$OR c.bateu ? 'endereco' OR c.bateu ? 'cep') AS m_lugar,$a$,
    $b$OR ((c.bateu ? 'endereco' OR c.bateu ? 'cep') AND NOT c.x_condo)) AS m_lugar,
           c.x_condo,$b$,
    -- 3. o caminho por bairro também não fecha outro condomínio
    $a$WHEN s.no_mercado AND s.m_bairro AND s.m_tipo AND s.m_area AND s.m_preco AND s.m_quartos THEN 'unidade'$a$,
    $b$WHEN s.no_mercado AND s.m_bairro AND NOT s.x_condo AND s.m_tipo AND s.m_area AND s.m_preco AND s.m_quartos THEN 'unidade'$b$
  ];
BEGIN
  FOR i IN 1 .. array_length(PARES, 1) / 2 LOOP
    v_par := ARRAY[PARES[2 * i - 1], PARES[2 * i]];
    IF (length(v_def) - length(replace(v_def, v_par[1], ''))) / length(v_par[1]) <> 1 THEN
      RAISE EXCEPTION '310: o trecho % não aparece exatamente uma vez na função viva', i;
    END IF;
    v_def := replace(v_def, v_par[1], v_par[2]);
  END LOOP;
  EXECUTE v_def;
END
$do$;
COMMIT;
