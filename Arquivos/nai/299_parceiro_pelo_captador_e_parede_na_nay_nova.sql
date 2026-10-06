-- =====================================================================
-- NAI -- 299: parceiro pelo CAPTADOR, e a parede de parceria na Nay nova
-- (Tel, 06/10/2026: "soube que a nay esta enviando imovel marcado como
-- parceiro, os imoveis parceiros estao todos indisponiveis, nao e para usar")
--
-- O QUE MEDI: nas duas Nays, nenhuma saida dos ultimos 30 dias cita imovel com
-- `e_parceiro = true`. O que saiu foi o 3647 (Solar da Praia, Ponta Negra):
-- card + 13 fotos para um corretor em 05/10 as 19:08, pela Nay nova. Ele esta
-- com `captado_por = 'Imob corretor parceiro (Parceiro)'` e a marca
-- `e_parceiro = false`. Todo filtro de parceria (as onze funcoes da Nay velha,
-- a parede `nai_saida_validar`, o nay-core inteiro, o site e o publicador)
-- olha a MARCA -- e a marca estava errada.
--
-- POR QUE ESTAVA ERRADA: a 109 marcou parceiro pelo DONO ("FULANO (PARCEIRO)")
-- e o sincronizador diario le a marca da listagem do site antigo. O 3647 tem
-- dona "Mariza" e o site antigo nao o lista como parceria; a palavra esta no
-- CAPTADOR, que ninguem olhava. Sao 898 imoveis com "(Parceiro)" no captador e
-- a marca ligada -- e esse UM com a marca desligada, no mercado.
--
-- O CONSERTO, em tres paredes:
--   1. a marca: captador "(Parceiro)" => `e_parceiro = true`, por gatilho em
--      `imoveis`, para a leitura diaria do site antigo nao desligar de novo;
--   2. a marca nos que ja estao la (o 3647);
--   3. a parede na Nay nova: `core_saida` ganha o mesmo gatilho que `nai_saida`
--      tem desde a 60 -- card, foto ou lista com imovel de parceria para quem
--      nao e o Tel grava como 'bloqueado', sem estourar a resposta.
--
-- NAO MEXE em `disponivel` nem em `publicado_no_site` dos 898: a decisao de
-- 27/09 (127) era "parceiro e indisponivel ficam so no admin", e o
-- sincronizador republicou 562 deles no mesmo dia. Como o site e as Nays
-- filtram pela marca, isso nao vaza -- mas fica anotado para o Tel decidir.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

-- 1. A marca pelo captador. Estrito de proposito: so "(Parceiro)" / "(Parceira)"
--    entre parenteses, como o site antigo escreve. Nome de captador interno
--    ("Vitoria Andrya", "captador 04", "SECRETARIA 5") nao casa.
CREATE OR REPLACE FUNCTION public.nai_captador_e_parceiro(p_captador text)
 RETURNS boolean LANGUAGE sql IMMUTABLE
AS $function$
  SELECT coalesce(p_captador, '') ~* '\(\s*parceir[oa]s?\s*\)'
$function$;

CREATE OR REPLACE FUNCTION public.imoveis_parceiro_pelo_captador()
 RETURNS trigger LANGUAGE plpgsql
AS $function$
BEGIN
  -- `administrado` e parceiro ao mesmo tempo viola chk_parceiro_nao_administrado:
  -- nesse caso nao mexe (e o humano quem resolve).
  IF NOT coalesce(NEW.administrado, false)
     AND (nai_captador_e_parceiro(NEW.captado_por)
          OR nai_captador_e_parceiro(coalesce(NEW.extras, '{}'::jsonb)->>'captado por')) THEN
    NEW.e_parceiro := true;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS imoveis_parceiro_pelo_captador ON public.imoveis;
CREATE TRIGGER imoveis_parceiro_pelo_captador
  BEFORE INSERT OR UPDATE ON public.imoveis
  FOR EACH ROW EXECUTE FUNCTION public.imoveis_parceiro_pelo_captador();

-- 2. A marca nos que ja estao la.
UPDATE imoveis
   SET e_parceiro = true
 WHERE NOT coalesce(e_parceiro, false)
   AND NOT coalesce(administrado, false)
   AND (nai_captador_e_parceiro(captado_por)
        OR nai_captador_e_parceiro(coalesce(extras, '{}'::jsonb)->>'captado por'));

-- 3. A parede na Nay nova. Igual a da 60 em `nai_saida`: nao levanta excecao,
--    grava 'bloqueado' com o motivo, e o Tel continua recebendo. Olha o codigo
--    da linha e, no texto, todo "Codigo: NNNN" (card) e "#NNNN" (lista).
--    No UPDATE so garante que ninguem desbloqueia o que foi barrado aqui: o
--    enviador le 'pendente' e ja manda, entao barrar na mudanca de estado
--    seria tarde.
CREATE OR REPLACE FUNCTION public.core_saida_validar()
 RETURNS trigger LANGUAGE plpgsql
AS $function$
DECLARE
  v_cods int[];
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF OLD.estado = 'bloqueado' AND OLD.bloqueio LIKE 'imovel de parceria%' THEN
      NEW.estado   := 'bloqueado';
      NEW.bloqueio := OLD.bloqueio;
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.papel_destino = 'tel' THEN
    RETURN NEW;
  END IF;

  v_cods := ARRAY[]::int[];
  IF NEW.codigo IS NOT NULL THEN
    v_cods := v_cods || NEW.codigo;
  END IF;
  IF NEW.tipo = 'texto' AND NEW.texto IS NOT NULL THEN
    v_cods := v_cods || coalesce(
      (SELECT array_agg(m[1]::int)
         FROM regexp_matches(NEW.texto, '(?:C[óo]digo:\s*|#)(\d{3,5})\M', 'gi') AS m),
      ARRAY[]::int[]);
  END IF;

  IF cardinality(v_cods) > 0
     AND EXISTS (SELECT 1 FROM imoveis i
                  WHERE i.codigo = ANY (v_cods) AND coalesce(i.e_parceiro, false)) THEN
    NEW.estado   := 'bloqueado';
    NEW.bloqueio := 'imovel de parceria: nunca enviado (299; codigos '
                    || array_to_string(v_cods, ',') || ')';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS core_saida_validar ON public.core_saida;
CREATE TRIGGER core_saida_validar
  BEFORE INSERT OR UPDATE ON public.core_saida
  FOR EACH ROW EXECUTE FUNCTION public.core_saida_validar();

COMMIT;

SELECT 'parceiro pelo captador' AS o,
       count(*) FILTER (WHERE nai_captador_e_parceiro(captado_por))::text AS captador_parceiro,
       count(*) FILTER (WHERE nai_captador_e_parceiro(captado_por) AND NOT e_parceiro)::text AS ainda_sem_marca
  FROM imoveis;
SELECT 'o 3647 agora' AS o, codigo, e_parceiro, disponivel, publicado_no_site FROM imoveis WHERE codigo = 3647;
