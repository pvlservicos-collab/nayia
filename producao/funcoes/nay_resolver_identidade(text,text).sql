CREATE OR REPLACE FUNCTION public.nay_resolver_identidade(p_id text, p_nome text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_id   text := btrim(coalesce(p_id,''));
  v_nome text := btrim(coalesce(p_nome,''));
  v_tel  text;
  v_n    int;
BEGIN
  -- Já é telefone: nada a fazer.
  IF v_id NOT LIKE '%@lid' THEN
    RETURN v_id;
  END IF;

  SELECT telefone INTO v_tel FROM identidade_lid WHERE lid = v_id;
  IF v_tel IS NOT NULL THEN
    RETURN v_tel;
  END IF;

  IF v_nome = '' THEN
    RETURN v_id;
  END IF;

  -- O NOSSO nome (a conta da Nay / da Imob Easy) vem em toda mensagem que o
  -- Tel digita no celular: nunca identifica a outra pessoa (11/09).
  IF lower(v_nome) ~ '^\s*(nay( mendes| ia)?|imob ?easy( ia)?)\s*$' THEN
    RETURN v_id;
  END IF;

  -- Só resolve se o nome apontar para EXATAMENTE um telefone. Dois
  -- telefones com o mesmo nome viram "não sei", nunca um chute. Só conta
  -- mensagem RECEBIDA: na enviada o nome é o nosso.
  SELECT count(*), min(telefone) INTO v_n, v_tel
    FROM (SELECT DISTINCT telefone FROM mensagens
           WHERE nome = v_nome AND direcao = 'recebida' AND telefone NOT LIKE '%@lid') y;

  IF v_n = 1 AND v_tel IS NOT NULL THEN
    INSERT INTO identidade_lid (lid, telefone, nome, origem)
         VALUES (v_id, v_tel, v_nome, 'nome')
    ON CONFLICT (lid) DO NOTHING;
    RETURN v_tel;
  END IF;

  RETURN v_id;
END;
$function$;
