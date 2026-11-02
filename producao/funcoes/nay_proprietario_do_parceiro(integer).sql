CREATE OR REPLACE FUNCTION public.nay_proprietario_do_parceiro(p_codigo integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_im    record;
  v_dig   text;
  v_nome  text;
  v_tel   text;
  v_pid   integer;
BEGIN
  SELECT codigo, e_parceiro, proprietario_id, extras INTO v_im FROM imoveis WHERE codigo = p_codigo;
  IF NOT FOUND OR NOT v_im.e_parceiro OR v_im.proprietario_id IS NOT NULL THEN RETURN NULL; END IF;
  IF EXISTS (SELECT 1 FROM imovel_privado WHERE codigo = p_codigo AND proprietario_id IS NOT NULL) THEN RETURN NULL; END IF;
  v_dig := regexp_replace(coalesce(v_im.extras->>'corretor_telefone', ''), '\D', '', 'g');
  IF length(v_dig) < 10 THEN RETURN NULL; END IF;
  -- só corretor conhecido
  SELECT btrim(c.nome) INTO v_nome FROM corretores c WHERE nai_chave(c.telefone) = nai_chave(v_dig) LIMIT 1;
  IF NOT FOUND THEN RETURN NULL; END IF;

  SELECT max(id) INTO v_pid FROM proprietarios
   WHERE right(regexp_replace(coalesce(telefone, ''), '\D', '', 'g'), 8) = right(v_dig, 8);
  IF v_pid IS NULL THEN
    -- o nome do anúncio sem o "| Corretor de Imóveis" e sem o CRECI; senão o nome que o corretor tem aqui
    v_nome := coalesce(nullif(btrim(regexp_replace(split_part(coalesce(v_im.extras->>'corretor_parceiro', ''), '|', 1),
                                                    '\s*(-\s*)?(creci|corretora? de im[oó]veis).*$', '', 'i')), ''), v_nome);
    IF v_nome !~ '[[:alpha:]]{2}' THEN v_nome := NULL; END IF;
    -- o formato do cadastro: [telefone …9999] (o número de 8 dígitos ganha o 9)
    v_dig := regexp_replace(v_dig, '^55', '');
    v_tel := substr(v_dig, 3);
    IF length(v_tel) = 8 THEN v_tel := '9' || v_tel; END IF;
    v_tel := '(' || substr(v_dig, 1, 2) || ') ' || substr(v_tel, 1, 5) || '-' || substr(v_tel, 6);
    v_pid := nextval('proprietarios_site_id_seq');
    INSERT INTO proprietarios (id, nome, telefone) VALUES (v_pid, v_nome, v_tel);
  END IF;

  UPDATE imoveis SET proprietario_id = v_pid WHERE codigo = p_codigo;
  INSERT INTO imovel_privado (codigo, proprietario_id) VALUES (p_codigo, v_pid)
  ON CONFLICT (codigo) DO UPDATE SET proprietario_id = EXCLUDED.proprietario_id;
  RETURN v_pid;
END $function$;
