CREATE OR REPLACE FUNCTION public.nai_tel_com_a_conversa(p_contato bigint)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_em     timestamptz;
  v_motivo text;
  v_gap    int;
  v_horas  int;
BEGIN
  IF p_contato IS NULL THEN RETURN false; END IF;

  -- EQUIPE NÃO TEM JANELA (Tel, 27/09/2026). Ver o cabeçalho da 130.
  IF nai_e_da_equipe_contato(p_contato) THEN RETURN false; END IF;

  -- QUEM TEM A VOZ DO TEL NÃO TEM O PRÓPRIO CHAT ASSUMIDO (28/09).
  --
  -- O CASO: o Tel deu a voz dele ao número da Imob Easy às 12h35. Às 08h40
  -- esse número escreveu, a Nay entendeu "o Tel escreveu pelo celular" e
  -- carimbou o chat; às 08h41 o comando `[telefone …8446] envia o 5739` chegou
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
  -- 215: QUALQUER linha da pessoa com marca valendo cala. Antes valia só a mais
  -- recente: o eco de 30 min ("o Tel escreveu pelo celular") numa linha vencia a
  -- marca do CRM (Tel/Rayssa) na outra, e 30 min depois a Nay falava por cima.
  -- Cada marca expira pela regra dela; tudo o que solta limpa as duas linhas.
  v_gap := greatest(nai_cfg_int('gap_tel_min', 30), 0);
  v_horas := nai_cfg_int('escalacao_expira_horas', 0);
  RETURN EXISTS (
    SELECT 1 FROM nai_contato c
     WHERE c.id = ANY (nai_contato_irmaos(p_contato)) AND c.humano_assumiu_em IS NOT NULL
       AND CASE WHEN c.humano_motivo = 'o Tel escreveu pelo celular'
                  THEN c.humano_assumiu_em > now() - make_interval(mins => v_gap)
                WHEN c.humano_motivo ~ '^(duvida fora da base|midia)' AND v_horas > 0
                  THEN c.humano_assumiu_em > now() - make_interval(hours => v_horas)
                ELSE true END);

  -- 195 (30/09): ESCALACAO TEM PRAZO. "duvida fora da base" e "midia" paravam
  -- o chat ate alguem mandar DEVOLVER -- em 29/09, 34 de 42 corretores
  -- escalados continuavam calados, alguns desde 15/09. Agora expiram depois
  -- de `escalacao_expira_horas`, contadas do ultimo carimbo (que renova a
  -- cada mensagem que o Tel digita na conversa). 0 ou chave ausente = nao
  -- expira, que e o comportamento de antes. Visita, ASSUMIR e CRM nao mudam.
  IF v_motivo ~ '^(duvida fora da base|midia)' THEN
    v_horas := nai_cfg_int('escalacao_expira_horas', 0);
    IF v_horas > 0 THEN
      RETURN v_em > now() - make_interval(hours => v_horas);
    END IF;
  END IF;

  RETURN true;
END;
$function$;
