-- =====================================================================
-- NAI -- 25: a QUARTA porta -- `nai_quem_atende` (Tel, 15/09/2026)
--
-- Depois de abrir as tres portas do arquivo 24, o comando do Tel AINDA nao
-- chegava: a mensagem dele ficava em `mensagens` com status 'Processando' e
-- ninguem respondia.
--
-- O motivo: quem decide se a mensagem vai para a NAI ou para a Nay antiga e
-- `nai_quem_atende`, e em modo teste ela manda para a NAI so quem esta em
-- `numeros_teste`. O Tel nao esta -- entao a mensagem dele ia para a Nay
-- ANTIGA, que esta pausada desde agosto. Ela nao respondia, e nao havia erro
-- nenhum para ver: a mensagem simplesmente parava ali.
--
-- Licao, que vale alem deste caso: uma mensagem do Tel atravessa QUATRO
-- porteiros ate virar resposta -- `nai_quem_atende` (qual das duas Nays),
-- `nai_abrir_turno` (o modo teste), a pausa e o redirecionamento do teste em
-- `nai_liberar_saida`. Abrir tres nao adianta.
--
-- Aqui a ordem e de proposito: comando do PUBLICADOR (posta, vagas, VENDEU)
-- continua indo para a Nay antiga, que e quem sabe faze-lo; so o comando da
-- NAI passa a vir para ca.
-- =====================================================================

CREATE OR REPLACE FUNCTION nai_quem_atende(p_phone text, p_grupo boolean, p_texto text)
RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE v_chave text := nai_chave(p_phone);
BEGIN
  -- 1. comando do publicador e da Nay antiga: nada muda.
  IF v_chave IS NOT NULL AND v_chave = nai_chave(nai_cfg('tel_telefone'))
     AND NOT coalesce(p_grupo, true) AND nai_e_comando_publicador(p_texto) THEN
    RETURN 'nay';
  END IF;

  -- 2. COMANDO DA NAI de quem pode comandar: vem para ca mesmo em modo teste,
  --    e mesmo que o numero nao esteja na lista de teste. Sem isto o comando
  --    do Tel cai na Nay antiga, que esta pausada, e morre calado.
  IF v_chave IS NOT NULL AND NOT coalesce(p_grupo, true)
     AND nai_pode_comandar(v_chave)
     AND (nai_e_comando_tel(p_texto) OR nai_e_comando_extra(p_texto)) THEN
    RETURN 'nai';
  END IF;

  -- 3. o resto, como sempre foi.
  RETURN nai_quem_atende(p_phone, p_grupo);
EXCEPTION WHEN others THEN
  RETURN 'nay';
END;
$$;

COMMENT ON FUNCTION nai_quem_atende(text, boolean, text) IS
  'Qual das duas Nays atende. Comando do publicador vai para a antiga; comando da NAI de quem pode comandar vem para a NAI mesmo em modo teste. Tel, 15/09.';
