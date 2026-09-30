CREATE OR REPLACE FUNCTION public.nai_escalar_cadastro(p_turno bigint, p_escreveu text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE t nai_turno; k nai_contato; v_nome text;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  IF k.id IS NULL THEN RETURN; END IF;
  v_nome := coalesce(k.nome_completo, k.nome_whatsapp, k.telefone);
  PERFORM nai_avisar_tel(p_turno, NULL,
    'Tel, ' || v_nome || ' (' || nai_fone_fmt(k.telefone) || ') está oferecendo imóvel: "' ||
    left(coalesce(p_escreveu, ''), 300) || '".' ||
    E'\nEu não faço cadastro, então não falei nada e parei de responder esse chat: quem responde é você. Para eu voltar: DEVOLVER '
    || nai_fone_fmt(k.telefone) || '.',
    'oferta_de_imovel');
  PERFORM nai_usou_ferramenta(p_turno, 'escalar');
  PERFORM nai_parar_chat(k.id, 'ofereceu imóvel (ela não faz cadastro)');
END;
$function$
;
