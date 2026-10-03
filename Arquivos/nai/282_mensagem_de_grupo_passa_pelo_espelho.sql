-- 282 (03/10/2026): A MENSAGEM DE GRUPO PASSA PELO ESPELHO DO CRM.
--
-- O painel dos grupos da Parceria (CRM › Grupos, 277/278) só mostra o que for guardado: a Z-API não entrega
-- histórico. A guarda mora no webhook do CRM, e quem chama o webhook é o nó "Espelhar no CRM" do fluxo
-- "NAI atendimento locação". Mas a mensagem chega primeiro no fluxo "Nay- recebe mensagem", e este função
-- mandava TODA mensagem de grupo para a Nay de sempre, cujo "Filtrar e normalizar" a descarta: o espelho nunca
-- a via. Resultado medido em 03/10 de manhã: `privado.grupo_conversa` vazia, 0 de 152 webhooks da NAI com
-- isGroup, enquanto o fluxo de entrada recebia mensagem de grupo.
--
-- Agora a mensagem de GRUPO (telefone terminado em "-group") vai para o fluxo da NAI: lá o "Espelhar no CRM"
-- a guarda e o "Filtrar e normalizar" a descarta, como já fazia (`if (b.isGroup ...) return []`). Nada
-- responde mensagem de grupo, nos dois fluxos. Newsletter e transmissão continuam como estavam.
-- Sem import de fluxo: só esta função (a de três argumentos, que é a que o n8n chama).
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION public.nai_quem_atende(p_phone text, p_grupo boolean, p_texto text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE v_chave text := nai_chave(p_phone);
BEGIN
  -- 0. MENSAGEM DE GRUPO (282): vai ao fluxo da NAI só para passar pelo "Espelhar no CRM". O "Filtrar e
  --    normalizar" de lá descarta grupo, como o daqui. Ninguém responde grupo.
  IF coalesce(p_grupo, false) AND coalesce(p_phone, '') ~ '-group$' THEN
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

COMMIT;
