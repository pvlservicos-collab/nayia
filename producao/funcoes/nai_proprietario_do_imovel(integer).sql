CREATE OR REPLACE FUNCTION public.nai_proprietario_do_imovel(p_codigo integer)
 RETURNS TABLE(cadastro_id integer, nome text, telefone text, motivo text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_id   int;
  v_nome text;
  v_tel  text;
  v_n    int;
  m      text[];
BEGIN
  SELECT pr.id, pr.nome, pr.telefone INTO v_id, v_nome, v_tel
    FROM imovel_privado p JOIN proprietarios pr ON pr.id = p.proprietario_id
   WHERE p.codigo = p_codigo;

  IF v_id IS NULL THEN
    -- Segunda fonte: o que foi coletado do admin. So vale se o imovel tiver
    -- UM proprietario so -- dois donos e perguntar ao errado nao tem volta.
    SELECT count(DISTINCT a.proprietario_id), min(pa.id) INTO v_n, v_id
      FROM proprietarios_admin_imoveis a JOIN proprietarios_admin pa ON pa.id = a.proprietario_id
     WHERE a.codigo = p_codigo::text;
    IF coalesce(v_n, 0) > 1 THEN
      RETURN QUERY SELECT NULL::int, NULL::text, NULL::text, 'dois_donos'::text; RETURN;
    END IF;
    IF v_id IS NOT NULL THEN
      SELECT pa.nome, pa.telefone INTO v_nome, v_tel FROM proprietarios_admin pa WHERE pa.id = v_id;
    END IF;
  END IF;

  IF v_id IS NULL THEN
    -- Terceira fonte (192, 30/09): o vinculo do proprio imovel, o mesmo que o
    -- site e o CRM leem. So entra quando as duas de cima nao acharam ninguem,
    -- entao quem ja tinha dono continua com o mesmo.
    SELECT pr.id, pr.nome, pr.telefone INTO v_id, v_nome, v_tel
      FROM imoveis i JOIN proprietarios pr ON pr.id = i.proprietario_id
     WHERE i.codigo = p_codigo;
  END IF;

  IF v_id IS NULL THEN
    RETURN QUERY SELECT NULL::int, NULL::text, NULL::text, 'sem_cadastro'::text; RETURN;
  END IF;

  -- "Neide (Tratar com a Imob Easy)": o cadastro manda falar com outra pessoa.
  IF coalesce(v_nome, '') ~* '(tratar|falar|contato)\s+com' THEN
    RETURN QUERY SELECT v_id, v_nome, NULL::text, 'tratar_com_outra_pessoa'::text; RETURN;
  END IF;

  -- O primeiro telefone que aparecer no campo ("[telefone …8888] / ...").
  m := regexp_match(coalesce(v_tel, ''), '\(?\d{2}\)?[\s.-]*9?\s*\d{4}[\s.-]?\d{4}');
  IF m IS NULL OR nai_chave(m[1]) IS NULL THEN
    RETURN QUERY SELECT v_id, v_nome, NULL::text, 'sem_telefone'::text; RETURN;
  END IF;

  RETURN QUERY SELECT v_id, NULLIF(btrim(regexp_replace(v_nome, '\(.*?\)', '', 'g')), ''), nai_fone_br(m[1]), NULL::text;
END;
$function$;
