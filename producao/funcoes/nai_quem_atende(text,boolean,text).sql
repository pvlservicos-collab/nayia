CREATE OR REPLACE FUNCTION public.nai_quem_atende(p_phone text, p_grupo boolean, p_texto text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE v_chave text := nai_chave(p_phone);
BEGIN
  -- 0. MENSAGEM DE GRUPO (282): vai ao fluxo da NAI só para passar pelo "Espelhar no CRM". O "Filtrar e
  --    normalizar" de lá descarta grupo, como o daqui. Ninguém responde grupo.
  -- 338: os DOIS formatos de id de grupo: "1203...-group" e o antigo "5592...-1600000000" (13 dos 28 grupos)
  IF coalesce(p_grupo, false) AND coalesce(p_phone, '') ~ '(-group$|^[0-9]{10,15}-[0-9]{8,12}$)' THEN
    RETURN 'nai';
  END IF;

  -- 1. comando do publicador e da Nay antiga: nada muda.
  IF v_chave IS NOT NULL AND v_chave = nai_chave(nai_cfg('tel_telefone'))
     AND NOT coalesce(p_grupo, true) AND nai_e_comando_publicador(p_texto) THEN
    RETURN 'nay';
  END IF;

  -- 2. COMANDO DA NAI de quem pode comandar: vem para ca mesmo em modo teste,
  --    e mesmo que o numero nao esteja na lista de teste. Sem isto o comando
  --    do Tel cai na Nay antiga, que esta pausada, e morre calado.
  IF v_chave IS NOT NULL AND NOT coalesce(p_grupo, true)
     AND nai_pode_comandar(v_chave)
     AND (nai_e_comando_tel(p_texto) OR nai_e_comando_extra(p_texto)) THEN
    RETURN 'nai';
  END IF;

  -- 3. o resto, como sempre foi.
  RETURN nai_quem_atende(p_phone, p_grupo);
EXCEPTION WHEN others THEN
  RETURN 'nay';
END;
$function$;
