CREATE OR REPLACE FUNCTION public.nai_contexto(p_papel text, p_contato bigint, p_visita bigint, p_teste boolean)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE v nai_visita; r text; linhas text;
BEGIN
  IF p_papel = 'corretor' THEN
    RETURN nai_contexto_corretor(p_contato);
  END IF;

  IF p_papel = 'proprietario' THEN
    IF p_visita IS NULL THEN
      SELECT string_agg('visita #' || x.id || ' · ' || nai_ref_imovel_prop(x.codigo) || ' · ' ||
                        coalesce(nai_quando_humano(x.quando), 'sem horário'), E'\n' ORDER BY x.id)
        INTO linhas FROM nai_visita x
       WHERE nai_visita_aberta(x.estado)
         AND (x.proprietario_id = p_contato OR (p_teste AND x.proprietario_id IS NOT NULL));
      RETURN CASE WHEN linhas IS NULL
        THEN 'NAO HA VISITA EM ANDAMENTO com este proprietario. Agradeca e diga que vai passar ao Tel, chamando resposta_do_proprietario com decisao duvida.'
        ELSE E'NAO DA PARA SABER DE QUAL VISITA ele fala. Pergunte, com educacao, qual destas:\n' || linhas END;
    END IF;
    SELECT * INTO v FROM nai_visita WHERE id = p_visita;
    RETURN 'visita #' || v.id || ' ' || nai_ref_imovel_prop(v.codigo) ||
      '. proprietario: ' || coalesce(nai_vocativo(v.proprietario_nome), 'nome nao informado') ||
      '. horario em discussao: ' || coalesce(nai_quando_humano(v.quando), 'nenhum') ||
      CASE WHEN v.quando_sugerido IS NOT NULL THEN '. horario que ELE sugeriu: ' || nai_quando_humano(v.quando_sugerido) ELSE '' END ||
      '. situacao: ' || nai_status_humano(v) ||
      CASE v.estado
        WHEN 'aguardando_proprietario' THEN '. ESPERANDO DELE: se tem como receber a visita nesse horario.'
        WHEN 'negociando' THEN CASE WHEN v.aguardando = 'proprietario' THEN '. ESPERANDO DELE: outro horario.' ELSE '. ele ja sugeriu outro horario; estamos vendo com o corretor.' END
        WHEN 'aguardando_acesso' THEN '. ESPERANDO DELE: como fica o acesso' ||
             CASE WHEN v.acesso = 'fechadura' THEN ' (a senha da fechadura)'
                  WHEN v.acesso = 'buscar_chave' THEN ' (onde e a partir de que horas pegar a chave)' ELSE '' END || '.'
        ELSE '' END;
  END IF;

  IF p_papel = 'motoboy' THEN
    SELECT string_agg('visita #' || x.id || ' · ' || nai_ref_imovel(x.codigo) || ' · ' || nai_hora_exata(x.quando) ||
                      ' · ' || CASE WHEN x.moto_ok_em IS NULL THEN 'ESPERANDO ELE CONFIRMAR' ELSE 'ele ja confirmou' END,
                      E'\n' ORDER BY x.quando)
      INTO linhas FROM nai_visita x
     WHERE nai_visita_aberta(x.estado) AND x.estado IN ('aguardando_motoboy', 'confirmada')
       AND (x.motoboy_id = p_contato OR p_teste);
    RETURN coalesce(E'visitas do ' || nai_acompanhante() || ':\n' || linhas, 'o ' || nai_acompanhante() || ' nao tem visita pendente.') ||
           CASE WHEN p_visita IS NOT NULL THEN E'\nele esta respondendo sobre a visita #' || p_visita || '.' ELSE '' END;
  END IF;
  RETURN NULL;
END;
$function$;
