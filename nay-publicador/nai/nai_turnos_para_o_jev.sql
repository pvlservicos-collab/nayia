CREATE OR REPLACE FUNCTION public.nai_turnos_para_o_jev(p_quantos integer DEFAULT 20, p_so_erros boolean DEFAULT false)
 RETURNS TABLE(turno_id bigint, quem text, texto text, atendente text, porta text)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT t.id,
         coalesce(k.nome_completo, k.nome_whatsapp, nai_fone_fmt(k.telefone)),
         t.texto, t.atendente, coalesce(t.porta, '-')
    FROM nai_turno t JOIN nai_contato k ON k.id = t.contato_id
   WHERE t.papel = 'corretor'
     AND coalesce(btrim(t.texto), '') <> ''
     AND t.contato_id <> 9707                    -- o espelho de treino fica fora
     AND t.criado_em > now() - interval '7 days'
     AND (NOT p_so_erros
          -- "as que ela errou": onde a saida foi barrada, ou onde ela nao
          -- respondeu nada, ou onde o assunto era imovel e foi para a
          -- secretaria
          OR EXISTS (SELECT 1 FROM nai_saida s
                      WHERE s.turno_id = t.id AND s.estado = 'bloqueado')
          OR NOT EXISTS (SELECT 1 FROM nai_saida s WHERE s.turno_id = t.id)
          OR (t.atendente = 'secretaria' AND nai_e_assunto_de_locacao(t.texto)))
   ORDER BY t.id DESC
   LIMIT p_quantos;
$function$
;
