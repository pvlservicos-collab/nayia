CREATE OR REPLACE FUNCTION public.nai_texto_visita_completa(p_visita bigint, p_titulo text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v     nai_visita;
  c     nai_contato;
  d     record;
  dono  record;
  m     record;
  i     imoveis;
  v_prop text;
BEGIN
  SELECT * INTO v FROM nai_visita WHERE id = p_visita;
  SELECT * INTO c FROM nai_contato WHERE id = v.corretor_id;
  SELECT * INTO i FROM imoveis WHERE codigo = v.codigo;
  SELECT * INTO d FROM nai_dados_corretor(c.id);
  SELECT * INTO dono FROM nai_proprietario_do_imovel(v.codigo);
  SELECT * INTO m FROM nai_motoboy();
  v_prop := CASE WHEN v.prop_telefone_manual IS NOT NULL
                 THEN coalesce(dono.nome, 'proprietário') || ' ' || nai_fone_fmt(v.prop_telefone_manual)
                 WHEN dono.motivo IS NULL THEN coalesce(dono.nome, '') || ' ' || nai_fone_fmt(dono.telefone)
                 ELSE '⚠ ' || CASE dono.motivo WHEN 'sem_telefone' THEN 'sem telefone no cadastro'
                                                WHEN 'tratar_com_outra_pessoa' THEN 'o cadastro diz: ' || coalesce(dono.nome, '')
                                                WHEN 'dois_donos' THEN 'dois proprietários no cadastro'
                                                ELSE 'sem proprietário cadastrado' END END;
  RETURN p_titulo || ' #' || v.id || ':' || E'\n\n'
      || coalesce(nai_ficha_imovel(v.codigo), '#' || v.codigo) || E'\n'
      || '📅 ' || to_char(v.quando AT TIME ZONE 'America/Manaus', 'DD/MM') || ' (' || nai_dia_da_semana(v.quando) || ') '
      || '🕐 ' || to_char(v.quando AT TIME ZONE 'America/Manaus', 'HH24"h"MI') || E'\n'
      || 'Corretor: ' || coalesce(d.nome_completo, c.nome_completo, c.nome_whatsapp, '') || ' ' || nai_fone_fmt(c.telefone)
      || coalesce(' · CRECI ' || d.creci, '') || E'\n'
      || 'Proprietário: ' || btrim(v_prop) || E'\n'
      || 'Acesso: ' || coalesce(CASE v.acesso WHEN 'chave_conosco' THEN 'chave conosco' WHEN 'buscar_chave' THEN 'buscar a chave'
                                              WHEN 'fechadura' THEN 'fechadura eletrônica' WHEN 'proprietario_acompanha' THEN 'o proprietário abre' END,
                                   'ainda não cadastrado (vou perguntar ao proprietário)')
      || CASE WHEN m.contato_id IS NOT NULL THEN E'\nAcompanhante: ' || coalesce(m.nome, '') || ' ' || nai_fone_fmt(m.telefone) ELSE '' END
      || CASE WHEN v.visitante_nome IS NOT NULL THEN E'\nVisitante: ' || v.visitante_nome || coalesce(', CPF ' || v.visitante_cpf, '') ELSE '' END
      || CASE WHEN v.aprovada_por IS NOT NULL THEN E'\nAprovada por: ' || v.aprovada_por ELSE '' END;
END;
$function$
;
