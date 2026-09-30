CREATE OR REPLACE FUNCTION public.nay_sincronizar_nome(p_telefone text, p_nome text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_tel  text := regexp_replace(coalesce(p_telefone,''),'[^0-9]','','g');
  v_nome text := btrim(coalesce(p_nome,''));
  v_conta text := btrim(coalesce(
    (SELECT valor FROM config WHERE chave = 'nome_da_conta_whatsapp'), ''));
BEGIN
  -- Nome vazio, ou que é só o próprio número (a Z-API manda assim quando
  -- não tem contato salvo), não serve para nada.
  IF v_nome = '' OR v_nome ~ '^\+?[0-9@ .-]+$' OR length(v_nome) < 2 THEN
    RETURN;
  END IF;

  -- O nome da conta que ENVIOU: é a Nay falando, não o corretor.
  IF v_conta <> '' AND lower(v_nome) = lower(v_conta) THEN
    RETURN;
  END IF;

  UPDATE corretores c
     SET nome = v_nome,
         nome_origem = 'whatsapp',
         nome_visto_em = now()
   WHERE right(regexp_replace(c.telefone,'[^0-9]','','g'),8) = right(v_tel,8)
     AND coalesce(c.nome_origem,'whatsapp') <> 'manual'   -- não pisa no do Tel
     AND coalesce(c.nome,'') IS DISTINCT FROM v_nome;     -- só quando mudou
END;
$function$;
