CREATE OR REPLACE FUNCTION public.nai_tel_com_a_conversa(p_contato bigint)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_em     timestamptz;
  v_motivo text;
  v_gap    int;
BEGIN
  IF p_contato IS NULL THEN RETURN false; END IF;

  -- EQUIPE NÃO TEM JANELA (Tel, 27/09/2026). Ver o cabeçalho da 130.
  IF nai_e_da_equipe_contato(p_contato) THEN RETURN false; END IF;

  -- QUEM TEM A VOZ DO TEL NÃO TEM O PRÓPRIO CHAT ASSUMIDO (28/09).
  --
  -- O CASO: o Tel deu a voz dele ao número da Imob Easy às 12h35. Às 08h40
  -- esse número escreveu, a Nay entendeu "o Tel escreveu pelo celular" e
  -- carimbou o chat; às 08h41 o comando `92 8464-8446 envia o 5739` chegou
  -- DESSE MESMO número e morreu em "Com o Tel". A marca que ele acabara de
  -- criar bloqueou o comando dele.
  --
  -- "O Tel assumiu este chat" só quer dizer alguma coisa no chat de OUTRA
  -- pessoa. No dele mesmo é uma frase sem sentido -- não se toma de si
  -- próprio uma conversa.
  --
  -- OLHA OS IRMÃOS, e é aí que estava o veneno: a marca ficou no contato
  -- `@lid` (`lid:5124097359973`), irmão do número. O `escala_sem_parar`, que
  -- deveria impedir o carimbo, compara por TELEFONE -- e um `@lid` nunca
  -- casa um telefone. Por isso a parede tem de estar na LEITURA, que enxerga
  -- os dois lados da identidade, e não só na escrita.
  -- `nai_chave` de novo na chave GUARDADA: ela é idempotente (conferido), e
  -- linha inserida à mão pode ter escapado da normalização. Custa nada e
  -- fecha a porta de um portão que, errando, deixa comando morrer calado.
  IF EXISTS (SELECT 1 FROM nai_contato c
              WHERE c.id = ANY (nai_contato_irmaos(p_contato))
                AND nai_e_voz_do_tel(nai_chave(c.chave))) THEN
    RETURN false;
  END IF;

  -- A linha carimbada MAIS RECENTE entre as da mesma pessoa.
  SELECT c.humano_assumiu_em, c.humano_motivo
    INTO v_em, v_motivo
    FROM nai_contato c
   WHERE c.id = ANY (nai_contato_irmaos(p_contato))
     AND c.humano_assumiu_em IS NOT NULL
   ORDER BY c.humano_assumiu_em DESC
   LIMIT 1;

  IF v_em IS NULL THEN RETURN false; END IF;

  IF v_motivo = 'o Tel escreveu pelo celular' THEN
    v_gap := greatest(nai_cfg_int('gap_tel_min', 30), 0);
    RETURN v_em > now() - make_interval(mins => v_gap);
  END IF;

  RETURN true;
END;
$function$


