CREATE OR REPLACE FUNCTION public.nai_o_que_sei_do_imovel(p_codigo text, p_pergunta text)
 RETURNS TABLE(texto_pronto text, sabe boolean, instrucao_para_voce text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_cod  text := NULLIF(regexp_replace(coalesce(p_codigo, ''), '\D', '', 'g'), '');
  v_base text;
  v_velho record;  -- 191
  v_ass   text;
  v_ficha text;
BEGIN
  -- A SITUACAO DO IMOVEL (Tel, 28/09/2026): disponivel -> status + card +
  -- fotos; qualquer outro status -> diz a situacao e ja lista os disponiveis
  -- do mesmo condominio (ou oferece outras opcoes perto). Parceria fica fora:
  -- quem fala de parceria e o Tel.
  IF length(v_cod) BETWEEN 3 AND 5 AND nai_pergunta_status(p_pergunta)
     AND EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = v_cod::int AND NOT coalesce(i.e_parceiro, false)) THEN
    RETURN QUERY SELECT s.texto_pronto, true, s.instrucao_para_voce FROM nai_status_do_imovel(v_cod::int) s;
    RETURN;
  END IF;
  IF length(v_cod) BETWEEN 3 AND 5 THEN
    v_base := nai_resposta_da_base(v_cod::int, p_pergunta);
  END IF;
  IF v_base IS NOT NULL THEN
    RETURN QUERY SELECT v_base, true,
      ('isto esta na ficha do imovel: mande o texto_pronto EXATAMENTE como veio, com as quebras de linha, ' ||
       'sem resumir, sem juntar numa frase so e sem emoji. NAO escale. NAO emende convite de visita: o sistema manda isso sozinho.')::text;
    RETURN;
  END IF;
  -- 191: o que o Tel ja respondeu deste imovel (a busca antiga) vem primeiro.
  SELECT x.texto_pronto, x.sabe, x.instrucao_para_voce INTO v_velho
    FROM nay_o_que_sei_do_imovel(p_codigo, p_pergunta) x LIMIT 1;
  IF coalesce(v_velho.sabe, false) THEN
    RETURN QUERY SELECT v_velho.texto_pronto, v_velho.sabe, v_velho.instrucao_para_voce;
    RETURN;
  END IF;
  -- ASSUNTO SENSIVEL QUE A FICHA NAO RESPONDE -> O TEL (Pedro, 29/09: "se nao
  -- tiver la claro, ela vai perguntar ao Tel e nao informar algo assim de forma
  -- errada"). Forma de pagamento, FGTS, permuta, garantia, documentacao, pet.
  v_ass := nai_assunto_sensivel(p_pergunta);
  IF v_ass IS NOT NULL AND length(v_cod) BETWEEN 3 AND 5 THEN
    RETURN QUERY SELECT NULL::text, false,
      ('ASSUNTO SENSIVEL (' || v_ass || ') QUE A FICHA DO ' || v_cod || ' NAO RESPONDE. NAO responda, NAO suponha, '
       || 'NAO diga "acho", "normalmente" nem "somente a vista": chame escalar_ao_tel com a pergunta dele e responda '
       || 'SILENCIO. O Tel responde e a resposta chega a ele.')::text;
    RETURN;
  END IF;
  -- O RESTO: A FICHA INTEIRA PARA LER (o "rag" do Pedro). Responder so com o
  -- que esta escrito; o que nao esta, sobe ao Tel.
  v_ficha := CASE WHEN length(v_cod) BETWEEN 3 AND 5 THEN nai_ficha_completa(v_cod::int) END;
  RETURN QUERY SELECT v_velho.texto_pronto, v_velho.sabe,
    (coalesce(v_velho.instrucao_para_voce, '')
     || CASE WHEN v_ficha IS NOT NULL
             THEN E'\n\nA FICHA INTEIRA DO IMOVEL -- leia antes de responder e responda SO com o que esta escrito nela. '
                  || E'O que nao esta escrito: chame escalar_ao_tel e responda SILENCIO.\n' || v_ficha
             ELSE '' END)::text;
END;
$function$
;
