CREATE OR REPLACE FUNCTION public.nai_texto_motoboy_ok(v nai_visita)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT 'Fechado, ' || nai_acompanhante() || ', agendei aqui: ' || nai_ref_imovel(v.codigo) || ', ' || nai_hora_exata(v.quando) || '. ' ||
    CASE v.acesso
      WHEN 'chave_conosco' THEN 'A chave está com a gente: separa ela pra visita, por favor.'
      WHEN 'buscar_chave' THEN 'A chave fica com o proprietário' || coalesce(' (' || v.acesso_detalhe || ')', '') ||
                               ': pega antes da visita e devolve depois, tá?'
      WHEN 'fechadura' THEN 'É fechadura eletrônica: te mando a senha ' || nai_cfg_int('aviso_motoboy_min', 30) || ' minutos antes.'
      WHEN 'proprietario_acompanha' THEN 'Quem abre é o proprietário' || coalesce(', ' || nai_vocativo(v.proprietario_nome), '') ||
           coalesce(' (' || nai_fone_fmt((SELECT telefone FROM nai_contato WHERE id = v.proprietario_id)) || ')', '') ||
           ': combina com ele de se encontrarem lá no horário.'
      ELSE 'O acesso eu confirmo com o Tel e te aviso.' END;
$function$;
