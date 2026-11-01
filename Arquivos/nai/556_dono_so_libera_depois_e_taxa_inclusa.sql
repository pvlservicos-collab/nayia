-- 556 (Pedro, 01/11/2026: "aplica as correções", da revisão das conversas de 30/10 a 01/11):
--   1. A dona do Park Golf (9030) escreveu em 30/10 "Só vai estar liberado em janeiro" e o 9030 continuou sendo
--      oferecido como disponível (31/10 a quatro corretores). A 548 só lia "aluguei/vendi/não está mais disponível";
--      agora "só ... liberado/livre/disponível ... <mês/data>" é 'ocupado': sai da oferta (bloqueado, até 3 imóveis do
--      dono) e a equipe é avisada para desbloquear quando liberar.
--   2. O card do Weekend Club (9058) dizia "Locação R$ 3.500 fora taxa de CD"; a descrição e o dono (30/10 15:43) dizem
--      "com condomínio incluso". O card lê o campo "incluso no aluguel", vazio nele e em mais dois imóveis cuja descrição
--      diz o mesmo (4804, 9087): o campo passa a dizer, como a descrição.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION public.nai_dono_disse_que_saiu(p_texto text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
-- 'alugado' | 'vendido' | 'indisponivel' | 'ocupado' (556) | NULL. Negação perto derruba ("ainda não aluguei", "não foi vendido").
DECLARE s text := lower(unaccent(coalesce(p_texto, '')));
BEGIN
  IF s ~ '\m(nao|n)\M\s+(esta|ta|estah|tah|fica)\s+mais\s+disponivel' OR s ~ '\mja\s+(nao\s+)?(esta|ta)\s+indisponivel' THEN
    RETURN 'indisponivel';
  END IF;
  -- 556 (a dona do 9030, 30/10: "Só vai estar liberado em janeiro"): ocupado até uma data, fora da oferta até lá
  IF s ~ '\mso\M' AND s ~ '\m(liberad|livre|disponivel|desocupad|libera|desocupa|vag[ao])'
     AND s ~ ('\m(janeiro|fevereiro|marco|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro'
              || '|ano que vem|mes que vem|semana que vem)\M|\m\d{1,2}/\d{1,2}\M|\mdia \d{1,2}\M') THEN
    RETURN 'ocupado';
  END IF;
  IF s ~ '\m(nao|ainda nao|nunca|ninguem|se)\M[^.!?]{0,24}\m(vend|alug|loc|loque)' THEN
    RETURN NULL;
  END IF;
  IF s ~ '\m(vendi|vendeu|vendemos|vendid[oa]s?)\M' THEN
    RETURN 'vendido';
  END IF;
  IF s ~ '\m(aluguei|alugou|alugamos|alugad[oa]s?|loquei|locou|locamos|locad[oa]s?)\M' THEN
    RETURN 'alugado';
  END IF;
  RETURN NULL;
END
$function$;

CREATE OR REPLACE FUNCTION public.nai_turno_dono_saiu()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  v_sit   text := nai_dono_disse_que_saiu(NEW.texto);
  v_tel   text;
  v_nome  text;
  v_cods  integer[];
  v_dito  integer[];
  v_bloq  integer[] := '{}';
BEGIN
  IF v_sit IS NULL OR NEW.contato_id IS NULL OR nai_e_da_equipe_contato(NEW.contato_id) THEN
    RETURN NULL;
  END IF;
  SELECT right(regexp_replace(telefone, '\D', '', 'g'), 8), coalesce(nullif(btrim(nome_completo), ''), nullif(btrim(nome_whatsapp), ''))
    INTO v_tel, v_nome FROM nai_contato WHERE id = NEW.contato_id;
  IF coalesce(v_tel, '') = '' THEN RETURN NULL; END IF;
  -- os Disponíveis de que ele é o dono (core_imovel_dono: imóvel, privado e admin antigo)
  SELECT array_agg(DISTINCT d.codigo ORDER BY d.codigo) INTO v_cods
    FROM core_imovel_dono d JOIN imoveis i ON i.codigo = d.codigo
   WHERE right(d.telefone_digitos, 8) = v_tel AND i.status = 'Disponível';
  IF v_cods IS NULL THEN RETURN NULL; END IF;
  -- citou um código dele: só esse
  SELECT array_agg(DISTINCT x::int) INTO v_dito
    FROM regexp_matches(coalesce(NEW.texto, ''), '\m(\d{3,5})\M', 'g') m(a), unnest(m.a) x
   WHERE x::int = ANY (v_cods);
  IF v_dito IS NOT NULL THEN v_cods := v_dito; END IF;
  IF cardinality(v_cods) <= 3 THEN
    WITH b AS (
      UPDATE imoveis SET bloqueado = true,
             motivo_bloqueio = left('548: o dono disse que ' || CASE v_sit WHEN 'indisponivel' THEN 'não está mais disponível' WHEN 'ocupado' THEN 'só fica livre mais tarde' ELSE 'foi ' || v_sit END
                                    || ' (' || to_char(now() AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI') || '): "'
                                    || left(btrim(NEW.texto), 200) || '". Conferir e mudar a situação, ou desbloquear.', 500)
       WHERE codigo = ANY (v_cods) AND NOT bloqueado
      RETURNING codigo)
    SELECT coalesce(array_agg(codigo ORDER BY codigo), '{}') INTO v_bloq FROM b;
  END IF;
  PERFORM nay_aviso_equipe('porta', 'escalada',
    coalesce(v_nome, 'Proprietário') || ' disse que o imóvel ' || CASE v_sit WHEN 'indisponivel' THEN 'saiu' WHEN 'ocupado' THEN 'só fica livre mais tarde' ELSE 'foi ' || v_sit END,
    'O proprietário ' || coalesce(v_nome, '') || ' escreveu: "' || left(btrim(NEW.texto), 500) || '"' || E'\n'
    || CASE WHEN cardinality(v_bloq) > 0
            THEN 'Tirei da oferta (bloqueado): ' || array_to_string(v_bloq, ', ') || '. '
                 || CASE WHEN v_sit = 'ocupado' THEN 'Desbloqueie quando liberar (ou se não for isso).'
                         ELSE 'Confira e mude a situação para ' || CASE v_sit WHEN 'vendido' THEN 'Vendido' ELSE 'Alugado' END
                              || ', ou desbloqueie se não for isso.' END
            ELSE 'Ele tem ' || cardinality(v_cods) || ' imóveis Disponíveis (' || array_to_string(v_cods[1:10], ', ')
                 || '): não tirei nenhum da oferta. Confira qual foi.' END,
    v_tel);
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'nai_turno_dono_saiu: %', SQLERRM;    -- o turno nunca cai por causa disto
  RETURN NULL;
END
$function$;

UPDATE imoveis SET extras = coalesce(extras, '{}'::jsonb) || jsonb_build_object('incluso no aluguel', 'Taxa de Condomínio')
 WHERE codigo IN (9058, 4804, 9087) AND coalesce(extras->>'incluso no aluguel', '') = '';

-- o aviso de 30/10 que já tinha passado: a dona do 9030 (o único imóvel dela) disse que só libera em janeiro
UPDATE imoveis SET bloqueado = true,
       motivo_bloqueio = '556: a dona disse em 30/10 16:15 "Não. Só vai estar liberado em janeiro". Desbloquear quando liberar.'
 WHERE codigo = 9030 AND status = 'Disponível' AND NOT bloqueado;
SELECT nay_aviso_equipe('porta', 'escalada', 'Park Golf (9030) fora da oferta até janeiro',
  'A dona do 9030 escreveu em 30/10: "Não. Só vai estar liberado em janeiro". Tirei da oferta (bloqueado). '
  || 'Desbloqueie quando liberar.', NULL);

COMMIT;
