CREATE OR REPLACE FUNCTION public.nai_status_humano(v nai_visita)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE v.estado
    WHEN 'coletando' THEN 'esperando os dados (nome completo e CPF) para pedir ao proprietário'
    WHEN 'aguardando_proprietario' THEN 'pedido feito ao proprietário, esperando ele confirmar'
    WHEN 'negociando' THEN CASE WHEN v.aguardando = 'corretor'
                             THEN 'o proprietário sugeriu ' || coalesce(nai_quando_humano(v.quando_sugerido), 'outro horário') || ' e estamos esperando o corretor responder'
                             ELSE 'esperando o proprietário dizer outro horário' END
    WHEN 'aguardando_acesso' THEN 'proprietário aceitou, acertando o acesso ao imóvel'
    WHEN 'aguardando_motoboy' THEN 'proprietário confirmou, confirmando com o ' || nai_acompanhante() || ''
    WHEN 'confirmada' THEN CASE WHEN v.visitante_nome IS NULL OR v.visitante_cpf IS NULL
                              THEN 'CONFIRMADA, mas os dados que o sistema pediu ainda nao chegaram'
                              ELSE 'CONFIRMADA' END
    WHEN 'com_tel' THEN 'o Tel está resolvendo'
    WHEN 'realizada' THEN 'a visita já aconteceu, esperando o retorno do corretor'
    ELSE v.estado END;
$function$;
