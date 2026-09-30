CREATE OR REPLACE FUNCTION public.nai_enfileirar_cortesia(p_turno bigint, p_texto text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE t nai_turno; k nai_contato;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno',
    'oi! aqui é a Nay, da Imob Easy. por aqui eu atendo os corretores parceiros. se você é corretor e quer se cadastrar, me manda seu nome e CRECI que eu passo pro Tel.',
    'cortesia', 1);
  PERFORM nai_avisar_tel(p_turno, NULL,
    'número fora do cadastro escreveu: ' || coalesce(k.nome_whatsapp || ' ', '') || '(' || k.telefone || ')' ||
    E'\n\n"' || left(coalesce(p_texto, ''), 300) || '"', 'cortesia');
  RETURN jsonb_build_object('ok', true);
END;
$function$;
