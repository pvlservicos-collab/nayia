-- =====================================================================
-- NAI -- 83: CRECI, CPF e telefone nao sao codigo de imovel (22/09/2026)
--
-- Achado no treino, rodada 8, conversa 01 (visita inteira), passo 5. O
-- corretor mandou os dados da visita: "O cliente e Joao Pereira, CPF
-- 529.982.247-25. Meu CRECI e 4321". O extrator leu 4321 como codigo -- o
-- 4321 EXISTE no catalogo --, trocou o imovel da conversa para ele e mandou
-- 6 fotos de um imovel que ninguem pediu, no meio da confirmacao da visita.
--
-- Mesma familia do ano (arquivo 78) e o mesmo lugar do conserto: o
-- `nay_tirar_valores`, que ja limpa valor, area e data antes de o extrator
-- procurar codigo. Saem tambem:
--   * o numero depois de CRECI, CPF, RG, CNPJ, CNH, matricula, protocolo;
--   * telefone: "(92) 98144-5964", "92 98144-5964", "98144-5964", "9 8144-5964"
--     -- o sistema manda o telefone do acompanhante na confirmacao, e o
--     corretor costuma responder citando um telefone.
-- Codigo de imovel continua: "me manda o 4321" segue sendo o 4321.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
  v_def  text;
  v_novo text;
  a      text := $a$lower(coalesce(p_texto,''))$a$;
BEGIN
  SELECT pg_get_functiondef('nay_tirar_valores'::regproc) INTO v_def;
  IF position('DOCUMENTO NAO E CODIGO' IN v_def) > 0 THEN
    RAISE NOTICE 'ja aplicado'; RETURN;
  END IF;
  IF (length(v_def) - length(replace(v_def, a, ''))) / length(a) <> 1 THEN
    RAISE EXCEPTION 'o ponto de troca mudou -- confira nay_tirar_valores';
  END IF;
  v_novo := replace(v_def, a,
$b$regexp_replace(regexp_replace(
    lower(coalesce(p_texto,'')),
    -- DOCUMENTO NAO E CODIGO (83): "CRECI 4321", "creci: 4321", "CPF 529.982.247-25".
    '\m(creci|cpf|rg|cnpj|cnh|matricula|matrícula|protocolo)\M[^0-9]{0,15}[0-9][0-9./-]*', ' ', 'g'),
    -- e TELEFONE: "(92) 98144-5964", "92 98144-5964", "98144-5964", "9 8144-5964"
    '(\(?[0-9]{2}\)?[ \t]*)?9?[ \t]?[0-9]{4}[ \t]?-[ \t]?[0-9]{4}\M', ' ', 'g')$b$);
  EXECUTE v_novo;
END $$;

CREATE TEMP TABLE prova(texto text, esperado text[]);
INSERT INTO prova VALUES
  ('O cliente é João Pereira, CPF 529.982.247-25. Meu CRECI é 4321', '{}'),
  ('creci: 4321',                                                    '{}'),
  ('meu CRECI-J 749',                                                '{}'),
  ('o André, (92) 98144-5964',                                       '{}'),
  ('liga no 98144-5964',                                             '{}'),
  ('me manda o 4321',                                                '{4321}'),
  ('me manda o card do 5727',                                        '{5727}'),
  ('o 5733 e o 2024',                                                '{2024,5733}'),
  ('Código: 2014',                                                   '{2014}'),
  ('até maio 2028',                                                  '{}'),
  ('me manda o 3500, 3210 e 2943',                                   '{2943,3210,3500}');

DO $$
DECLARE r record; v text[]; n int := 0;
BEGIN
  FOR r IN SELECT * FROM prova LOOP
    SELECT coalesce(array_agg(x ORDER BY x), '{}') INTO v FROM unnest(nay_codigos_citados(r.texto)) x;
    IF v IS DISTINCT FROM r.esperado THEN
      RAISE EXCEPTION 'falhou: "%" deu % e devia dar %', r.texto, v, r.esperado;
    END IF;
    n := n + 1;
  END LOOP;
  RAISE NOTICE 'prova: % de % casos certos', n, n;
END $$;

COMMIT;
