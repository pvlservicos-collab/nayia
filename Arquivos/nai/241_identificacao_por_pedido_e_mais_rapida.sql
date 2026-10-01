-- 241 (30/09/2026): A IDENTIFICAÇÃO É DE CADA PEDIDO, E FICA RÁPIDA.
-- Pedro: "revisa toda parte de identificação a cada solicitação diferente para deixar
-- tudo ok, e seguindo as regras; otimiza... pode estar algo que tá demorando".
--
-- Medido antes (ensaio com três pedidos seguidos do mesmo corretor):
--   P1 "quero alugar apartamento na Ponta Negra até 3 mil"  -> locação, apartamento ✔
--   P2 "outro cliente: comprar casa no Flores até 700 mil"  -> venda, casa ✔
--   P3 "e para alugar, 2 quartos mobiliado no Adrianópolis" -> locação, CASA ✘
-- No P3 ele não disse o tipo, e a Nay herdou "casa" do pedido ANTERIOR (que era de
-- venda, de outro cliente): respondeu "não tenho nenhuma casa nesse perfil" em vez de
-- perguntar casa ou apartamento. O tipo atravessava a fronteira do pedido.
--
--   1. bairro_normal: os bairros do catálogo já normalizados, por gatilho.
--      `nai_pedido_de_perfil` e `nai_imovel_pela_descricao` liam 5.674 imóveis e
--      normalizavam cada bairro A CADA CHAMADA: 222 ms cada, várias vezes por turno.
--      Agora é uma tabela de 53 linhas com índice: ~1 ms.
--   2. nai_tipo_da_conversa: a herança do tipo para na fronteira do PEDIDO (o perfil
--      do cliente, 223). Sem perfil aberto, segue a janela de 3 dias (224).
--   3. nai_buscar_por_perfil: pedido novo também quando o NEGÓCIO muda (venda ->
--      locação), e em pedido novo o tipo só vale se foi dito NESTE pedido.
--   4. nai_pedido_de_perfil reconhece como pedido o jeito que eles escrevem de
--      verdade: "tu tem", "ela quer um", "tô com um cliente", "tem Vieira Alves",
--      "alguma locação", "você teria". Medido no corpus (12 dias) antes e depois.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION pg_temp.trocar(p_fn regprocedure, p_de text, p_para text, p_vezes int DEFAULT 1)
 RETURNS void LANGUAGE plpgsql AS $$
DECLARE d text := pg_get_functiondef(p_fn); n int := (length(d) - length(replace(d, p_de, ''))) / length(p_de);
BEGIN
  IF n <> p_vezes THEN RAISE EXCEPTION 'trocar em %: esperava % vez(es), achei % -- %', p_fn, p_vezes, n, left(p_de, 50); END IF;
  EXECUTE replace(d, p_de, p_para);
END $$;

-- 1 ------------------------------------------- os bairros já normalizados
CREATE TABLE IF NOT EXISTS bairro_normal (
  bairro  text PRIMARY KEY,
  normal  text NOT NULL,
  dois    text,                -- as duas primeiras palavras, para nome comprido
  imoveis integer NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS bairro_normal_normal ON bairro_normal (normal);
COMMENT ON TABLE bairro_normal IS '241: os bairros do catálogo normalizados, para a identificação não varrer imoveis a cada chamada';

CREATE OR REPLACE FUNCTION public.nai_bairro_normal_refazer()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE n int;
BEGIN
  WITH b AS (
    SELECT btrim(i.bairro) AS bairro, nay_normalizar_lugar(i.bairro, true) AS normal, count(*) AS imoveis
      FROM imoveis i WHERE nullif(btrim(i.bairro), '') IS NOT NULL GROUP BY 1, 2
  ), ins AS (
    INSERT INTO bairro_normal (bairro, normal, dois, imoveis)
    SELECT b.bairro, b.normal,
           CASE WHEN array_length(string_to_array(b.normal, ' '), 1) >= 3
                THEN array_to_string((string_to_array(b.normal, ' '))[1:2], ' ') END,
           b.imoveis
      FROM b
    ON CONFLICT (bairro) DO UPDATE SET normal = EXCLUDED.normal, dois = EXCLUDED.dois, imoveis = EXCLUDED.imoveis
    RETURNING 1
  )
  SELECT count(*) INTO n FROM ins;
  DELETE FROM bairro_normal x WHERE NOT EXISTS (SELECT 1 FROM imoveis i WHERE btrim(i.bairro) = x.bairro);
  RETURN n;
END;
$function$;
REVOKE ALL ON FUNCTION nai_bairro_normal_refazer() FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.nai_bairro_normal_gatilho()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  BEGIN
    PERFORM nai_bairro_normal_refazer();   -- 53 linhas: refazer tudo é mais simples que diferenciar
  EXCEPTION WHEN others THEN
    RAISE WARNING 'bairro_normal: %', SQLERRM;   -- nunca derruba a gravação do imóvel
  END;
  RETURN NULL;
END;
$function$;
DROP TRIGGER IF EXISTS bairro_normal_do_imovel ON imoveis;
CREATE TRIGGER bairro_normal_do_imovel AFTER INSERT OR UPDATE OF bairro OR DELETE ON imoveis
  FOR EACH STATEMENT EXECUTE FUNCTION nai_bairro_normal_gatilho();
SELECT nai_bairro_normal_refazer() AS bairros;
GRANT SELECT ON bairro_normal TO nay_site_leitura;

-- as duas funções passam a ler a tabela
SELECT pg_temp.trocar('nai_pedido_de_perfil(text)',
$a$  SELECT b.bairro INTO v_bairro FROM (
    SELECT DISTINCT i.bairro FROM imoveis i WHERE nullif(btrim(i.bairro), '') IS NOT NULL) b
   WHERE s_lugar LIKE '%' || nay_normalizar_lugar(b.bairro, true) || '%'
      OR (array_length(string_to_array(nay_normalizar_lugar(b.bairro, true), ' '), 1) >= 3
          AND s_lugar LIKE '%' ||
              array_to_string((string_to_array(nay_normalizar_lugar(b.bairro, true), ' '))[1:2], ' ') || '%')
   ORDER BY length(b.bairro) DESC LIMIT 1;$a$,
$b$  -- 241: a tabela bairro_normal no lugar da varredura (222 ms -> 1 ms)
  SELECT b.bairro INTO v_bairro FROM bairro_normal b
   WHERE s_lugar LIKE '%' || b.normal || '%'
      OR (b.dois IS NOT NULL AND s_lugar LIKE '%' || b.dois || '%')
   ORDER BY length(b.bairro) DESC LIMIT 1;$b$);

SELECT pg_temp.trocar('nai_imovel_pela_descricao(text,text)',
$a$  SELECT b.bairro INTO v_bairro FROM (
    SELECT DISTINCT i.bairro FROM imoveis i WHERE nullif(btrim(i.bairro), '') IS NOT NULL) b
   WHERE s_lugar LIKE '%' || nay_normalizar_lugar(b.bairro, true) || '%'
      OR (array_length(string_to_array(nay_normalizar_lugar(b.bairro, true), ' '), 1) >= 3
          AND s_lugar LIKE '%' ||
              array_to_string((string_to_array(nay_normalizar_lugar(b.bairro, true), ' '))[1:2], ' ') || '%')
   ORDER BY length(b.bairro) DESC LIMIT 1;$a$,
$b$  -- 241: a tabela bairro_normal no lugar da varredura
  SELECT b.bairro INTO v_bairro FROM bairro_normal b
   WHERE s_lugar LIKE '%' || b.normal || '%'
      OR (b.dois IS NOT NULL AND s_lugar LIKE '%' || b.dois || '%')
   ORDER BY length(b.bairro) DESC LIMIT 1;$b$);

-- 2 ------------------------------- o tipo não atravessa a fronteira do pedido
CREATE OR REPLACE FUNCTION public.nai_tipo_da_conversa(p_contato bigint, p_texto text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  -- 224: o tipo é o do pedido de AGORA (3 dias, não 60).
  -- 241: e para na fronteira do PEDIDO: com um perfil de cliente aberto (223), só
  -- valem as falas desde que ele começou. Sem isso, "e para alugar, 2 quartos no
  -- Adrianópolis" herdava o "casa" do pedido anterior, de venda e de outro cliente.
  SELECT nai_tipo_das_falas(array[coalesce(p_texto, '')] || coalesce((
    SELECT array_agg(x.texto ORDER BY x.id DESC) FROM (
      SELECT t.id, t.texto FROM nai_turno t
       WHERE t.contato_id = ANY (nai_contato_irmaos(p_contato))
         AND t.criado_em > greatest(
               now() - interval '3 days',
               coalesce((SELECT k.zerado_em FROM nai_contato k WHERE k.id = p_contato), '-infinity'),
               coalesce((SELECT p.criado_em FROM nai_perfil_ativo(p_contato) p), '-infinity'))
       ORDER BY t.id DESC LIMIT 40) x), '{}'::text[]));
$function$;

-- 3 ------------------------- pedido novo também quando o negócio muda
SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$      OR (v_teto IS NOT NULL AND v_perfil.teto IS NOT NULL AND abs(v_teto - v_perfil.teto) > 0.1 * v_perfil.teto);$a$,
$b$      OR (v_teto IS NOT NULL AND v_perfil.teto IS NOT NULL AND abs(v_teto - v_perfil.teto) > 0.1 * v_perfil.teto)
      -- 241: trocou de locação para venda (ou o contrário) = outro cliente, outro pedido
      OR (v_perfil.negocio IS NOT NULL
          AND nai_negocio_das_falas(array[concat_ws(' ', t.texto, p_teto)]) IS NOT NULL
          AND nai_negocio_das_falas(array[concat_ws(' ', t.texto, p_teto)]) <> v_perfil.negocio);$b$);

SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$  v_tipo    := nai_tipo_da_conversa(k.id, concat_ws(' ', t.texto, p_bairro));$a$,
$b$  -- 241: PEDIDO NOVO, TIPO NOVO. Só vale o tipo dito NESTE pedido -- senão a casa do
  -- pedido anterior responde pelo apartamento deste. Sem tipo, a busca pergunta
  -- "casa ou apartamento?" (152), que é o certo.
  v_tipo    := CASE WHEN v_pedido_novo
                    THEN nai_tipo_pedido(concat_ws(' ', t.texto, p_bairro))
                    ELSE nai_tipo_da_conversa(k.id, concat_ws(' ', t.texto, p_bairro)) END;$b$);

-- 4 ------------------------------ o jeito que eles pedem de verdade
SELECT pg_temp.trocar('nai_pedido_de_perfil(text)',
$a$                 || 'voce tem|vc tem|vcs tem|voces tem|tens|quero um|quero uma|queria um|queria uma|'$a$,
$b$                 || 'voce tem|vc tem|vcs tem|voces tem|tens|tu tem|tu tens|quero um|quero uma|queria um|queria uma|'
                 -- 241: medido no corpus de 12 dias -- o jeito que eles escrevem
                 || 'quer um|quer uma|teria algum|teria alguma|voce teria|vc teria|'
                 || 'alguma locacao|alguma venda|algum para alugar|algo para alugar|algo para comprar|'
                 || 'com um cliente|com uma cliente|para alugar|pra alugar|para comprar|pra comprar|'$b$);
COMMIT;
