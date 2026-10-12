CREATE OR REPLACE FUNCTION public.nai_resposta_do_condominio(p_codigo integer, p_campo text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_tipo  text := nai_tipo_preciso(p_codigo);
  -- 'outro' (galpão, depósito...) não tem frase pronta: cai no próprio `tipo`
  -- do cadastro, que é melhor do que ela dizer "esse é " e engolir o resto
  v_fala  text := coalesce(nai_tipo_falado(v_tipo),
                           (SELECT 'um ' || lower(btrim(tipo)) FROM imoveis WHERE codigo = p_codigo));
  v_f     jsonb;
  v_v     text;
  v_n     text;
  v_nome  text;
BEGIN
  IF v_tipo IS NULL THEN RETURN NULL; END IF;

  -- o campo não é deste tipo: resposta fechada, com o motivo
  IF NOT nai_campo_do_tipo(v_tipo, p_campo) THEN
    RETURN CASE p_campo
      WHEN 'andar'           THEN 'é ' || v_fala || ', não tem andar'
      WHEN 'andares_predio'  THEN 'é ' || v_fala || ', não é prédio'
      WHEN 'aptos_por_andar' THEN 'é ' || v_fala || ', não tem apartamento por andar'
      WHEN 'elevador'        THEN 'é ' || v_fala || ', não tem elevador'
      WHEN 'torres'          THEN 'é ' || v_fala || ', não é em condomínio'
      ELSE 'é ' || v_fala END;
  END IF;

  v_f := nai_condominio_do_imovel(p_codigo);
  v_nome := nullif(btrim(coalesce(v_f->>'nome', '')), '');

  -- o campo vale, e o valor existe
  IF v_f IS NOT NULL THEN
    v_v := nullif(btrim(coalesce(v_f ->> CASE p_campo
             WHEN 'andares_predio'  THEN 'andares'
             WHEN 'aptos_por_andar' THEN 'aptos_por_andar'
             WHEN 'torres'          THEN 'torres'
             WHEN 'elevador'        THEN 'elevador' END, '')), '');
    IF v_v IS NOT NULL THEN
      -- só os dígitos: a ficha às vezes guarda "6 torres", "8 andares (térreo + 7)"
      v_n := nullif(regexp_replace(v_v, '\D', '', 'g'), '');
      RETURN CASE p_campo
        WHEN 'andares_predio'  THEN CASE WHEN v_n IS NULL THEN 'o prédio ' || v_v
                                         WHEN v_n = '1' THEN 'o prédio tem 1 andar'
                                         ELSE 'o prédio tem ' || v_n || ' andares' END
        WHEN 'torres'          THEN CASE WHEN v_n IS NULL THEN 'o condomínio ' || v_v
                                         WHEN v_n = '1' THEN 'o condomínio tem 1 torre'
                                         ELSE 'o condomínio tem ' || v_n || ' torres' END
        WHEN 'aptos_por_andar' THEN CASE WHEN v_n IS NULL THEN v_v
                                         WHEN v_n = '1' THEN 'é 1 apartamento por andar'
                                         ELSE 'são ' || v_n || ' apartamentos por andar' END
        WHEN 'elevador'        THEN CASE WHEN lower(unaccent(v_v)) ~ '^(sim|possui|tem|[1-9])'
                                         THEN 'tem elevador' ELSE 'não tem elevador' END
        END;
    END IF;
  END IF;

  -- o campo vale para o tipo, mas ninguém preencheu: diz o tipo e assume
  RETURN 'é ' || v_fala
         || coalesce(' (' || v_nome || ')', '')
         || ', mas '
         || CASE p_campo
              WHEN 'andar'           THEN 'não tenho o andar dele'
              WHEN 'andares_predio'  THEN 'não tenho quantos andares o prédio tem'
              WHEN 'torres'          THEN 'não tenho quantas torres o condomínio tem'
              WHEN 'aptos_por_andar' THEN 'não tenho quantos apartamentos por andar'
              WHEN 'elevador'        THEN 'não tenho se tem elevador'
              ELSE 'não tenho esse dado' END
         || ' aqui';
END;
$function$;
