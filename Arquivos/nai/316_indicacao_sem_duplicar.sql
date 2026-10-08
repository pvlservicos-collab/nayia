-- 316 (08/10/2026): A MESMA INDICAÇÃO NÃO VIRA DUAS LINHAS.
-- No ensaio da Nay de captação em Python, o dono indicou o cunhado em duas mensagens: primeiro o nome ("meu
-- cunhado Carlos está vendendo uma casa no Tarumã"), depois o telefone. Ela chamou guardar_indicacao nas duas, e
-- ficaram duas linhas para a mesma pessoa. Agora a segunda chamada COMPLETA a primeira: se este proprietário
-- deixou, nas últimas 6 horas, uma indicação ainda sem telefone, o que vier preenche aquela linha.
BEGIN;
CREATE OR REPLACE FUNCTION public.captacao_indicacao_guardar(p_telefone text, p_nome text, p_contato text, p_detalhe text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_lead   bigint;
  v_aberta bigint;
  v_nome    text := left(nullif(btrim(coalesce(p_nome, '')), ''), 160);
  v_contato text := left(nullif(btrim(coalesce(p_contato, '')), ''), 80);
  v_detalhe text := left(nullif(btrim(coalesce(p_detalhe, '')), ''), 600);
  v_tem_fone boolean;
BEGIN
  SELECT l.id INTO v_lead FROM captacao_leads l WHERE l.telefone_chave = nay_fone_chave(p_telefone);
  IF v_nome IS NULL AND v_contato IS NULL AND v_detalhe IS NULL THEN
    RETURN 'Nao gravei: faltou dizer quem e o indicado. Pergunte o nome e o telefone dele.';
  END IF;
  -- a indicação que ficou sem telefone agora há pouco: é a mesma pessoa chegando em duas mensagens
  SELECT i.id INTO v_aberta FROM privado.captacao_indicacao i
   WHERE nay_fone_chave(i.telefone) = nay_fone_chave(p_telefone) AND i.criado_em > now() - interval '6 hours'
     AND length(regexp_replace(coalesce(i.contato, ''), '\D', '', 'g')) < 8
   ORDER BY i.id DESC LIMIT 1;
  IF v_aberta IS NOT NULL THEN
    UPDATE privado.captacao_indicacao i
       SET nome = coalesce(v_nome, i.nome), contato = coalesce(v_contato, i.contato), detalhe = coalesce(i.detalhe, v_detalhe)
     WHERE i.id = v_aberta;
  ELSE
    INSERT INTO privado.captacao_indicacao (lead_id, telefone, nome, contato, detalhe)
    VALUES (v_lead, p_telefone, v_nome, v_contato, v_detalhe);
  END IF;
  SELECT length(regexp_replace(coalesce(i.contato, ''), '\D', '', 'g')) >= 8 INTO v_tem_fone
    FROM privado.captacao_indicacao i
   WHERE nay_fone_chave(i.telefone) = nay_fone_chave(p_telefone) ORDER BY i.id DESC LIMIT 1;
  IF NOT coalesce(v_tem_fone, false) THEN
    RETURN 'Indicacao anotada, mas SEM telefone. Peca, em uma linha, o telefone do indicado. Se ele nao tiver ou nao quiser passar, agradeca e encerre.';
  END IF;
  RETURN 'Indicacao gravada. Agradeca em uma linha e encerre a conversa (encerrar_conversa, motivo concluido).';
END
$function$;
REVOKE ALL ON FUNCTION captacao_indicacao_guardar(text, text, text, text) FROM PUBLIC;
COMMIT;
