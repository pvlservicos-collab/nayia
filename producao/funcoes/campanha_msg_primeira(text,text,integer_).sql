CREATE OR REPLACE FUNCTION public.campanha_msg_primeira(p_lista text, p_voc text, p_codigos integer[])
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  v_oi   text := 'Olá' || coalesce(', ' || p_voc, '') || '! Tudo bem? Aqui é a Nay, da Imob Easy. ';
  v_n    int := cardinality(p_codigos);
  v_um   text;
  v_cods text := campanha_lista_texto(p_codigos::text[]);
  v_fin  text;
  v_nomes text[];
BEGIN
  IF v_n = 1 THEN
    v_um := campanha_imovel_nome(p_codigos[1], p_lista <> 'parceiros_disponivel');
  END IF;
  IF p_lista = 'donos_parados' THEN
    RETURN v_oi || CASE WHEN v_n = 1 THEN upper(left(v_um, 1)) || substr(v_um, 2) || ' (cód. ' || p_codigos[1] || ') ainda está disponível?'
                        ELSE 'Os seus imóveis cadastrados conosco (' || v_cods || ') ainda estão disponíveis?' END;
  ELSIF p_lista = 'feedback_disponiveis' THEN
    SELECT CASE WHEN bool_or(coalesce(valor_aluguel, 0) > 0) AND bool_or(coalesce(valor_venda, 0) > 0) THEN 'alugado ou vendido'
                WHEN bool_or(coalesce(valor_aluguel, 0) > 0) THEN 'alugado' ELSE 'vendido' END
      INTO v_fin FROM imoveis WHERE codigo = ANY (p_codigos);
    RETURN v_oi || 'Estou atualizando o nosso cadastro: '
           || CASE WHEN v_n = 1 THEN v_um || ' (cód. ' || p_codigos[1] || ') continua disponível ou já foi ' || v_fin || '?'
                   ELSE 'os seus imóveis (' || v_cods || ') continuam disponíveis, ou algum já foi ' || v_fin || '?' END;
  END IF;
  -- parceiros_disponivel: até 3 pelo nome, o resto pelo código
  IF v_n = 1 THEN
    RETURN v_oi || upper(left(v_um, 1)) || substr(v_um, 2) || ' (cód. ' || p_codigos[1]
           || ') que você tem em parceria conosco ainda está disponível? Se já saiu, tem outra opção parecida para me mandar?';
  END IF;
  SELECT array_agg(campanha_imovel_nome(c, false) || ' (cód. ' || c || ')' ORDER BY o) INTO v_nomes
    FROM unnest(p_codigos[1:3]) WITH ORDINALITY AS u(c, o);
  RETURN v_oi || 'Estou conferindo os imóveis que você tem em parceria conosco: ' || campanha_lista_texto(v_nomes)
         || CASE WHEN v_n > 3 THEN ', e mais ' || (v_n - 3) || ' (cód. '
                                   || campanha_lista_texto((p_codigos[4:least(v_n, 18)])::text[])
                                   || CASE WHEN v_n > 18 THEN '…' ELSE '' END || ')' ELSE '' END
         || '. Ainda estão disponíveis? Se algum já saiu, tem outras opções parecidas para me mandar?';
END;
$function$;
