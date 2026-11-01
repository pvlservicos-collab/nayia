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
