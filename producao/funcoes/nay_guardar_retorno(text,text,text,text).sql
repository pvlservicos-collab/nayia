CREATE OR REPLACE FUNCTION public.nay_guardar_retorno(p_telefone text, p_codigo text, p_frase text, p_referencia text)
 RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_tel  text := regexp_replace(coalesce(p_telefone,''),'[^0-9]','','g');
  v_cod  text := NULLIF(regexp_replace(coalesce(p_codigo,''),'[^0-9]','','g'),'');
  v_ref  text := NULLIF(btrim(coalesce(p_referencia,'')),'');
  m      record;
BEGIN
  IF v_cod IS NULL THEN
    RETURN QUERY SELECT
      'de qual imóvel é esse cliente?'::text,
      ('sem o codigo do imovel o lembrete nao pode existir: a cobranca sairia '
       || 'generica demais. Pergunte de qual imovel antes de chamar de novo.')::text;
    RETURN;
  END IF;

  SELECT * INTO m FROM nay_quando_cobrar(p_frase);
  IF m.quando IS NULL THEN
    RETURN QUERY SELECT
      'quando ele te dá esse retorno?'::text,
      'nao deu para entender o prazo. peca algo concreto, como hoje a tarde ou amanha de manha.'::text;
    RETURN;
  END IF;

  -- Um lembrete vivo por corretor e imóvel: prazo novo SUBSTITUI o antigo,
  -- nunca soma (decisão 6 do Tel).
  UPDATE lembrete SET estado = 'morto', motivo_fim = 'substituido por prazo novo',
         atualizado_em = now()
   WHERE telefone = v_tel AND coalesce(codigo,'') = coalesce(v_cod,'')
     AND estado IN ('agendado','enviado','congelado');

  INSERT INTO lembrete (telefone, codigo, referencia, disparar_em,
                        expressao, regra_aplicada)
  VALUES (v_tel, v_cod, v_ref, m.quando, btrim(coalesce(p_frase,'')), m.regra);

  RETURN QUERY SELECT
    ''::text,
    ('anotado: vou cobrar esse retorno em '
     || to_char(m.quando AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI')
     || '. NAO diga a hora exata ao corretor nem que criou lembrete -- so '
     || 'confirme que ficou combinado, no seu tom.')::text;
END;
$function$;
