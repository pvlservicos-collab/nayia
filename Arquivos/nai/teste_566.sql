-- 566: ninguém ficou com o campo antigo; o 9097 tem o card "Somente à vista." e o link da OLX no interno; nada de link no card
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM imoveis WHERE extras ? 'observacao_do_corretor' AND status <> 'Excluído') THEN
    RAISE EXCEPTION 'sobrou observacao_do_corretor';
  END IF;
  IF (SELECT observacao FROM imoveis WHERE codigo = 9097) IS DISTINCT FROM 'Somente à vista.' THEN RAISE EXCEPTION '9097 card'; END IF;
  IF coalesce((SELECT observacoes FROM privado.imovel_ficha WHERE codigo = 9097), '') !~ 'olx\.com\.br/.*1493683146' THEN RAISE EXCEPTION '9097 interno'; END IF;
  IF EXISTS (SELECT 1 FROM imoveis WHERE observacao ~* 'olx\.com\.br|comiss|saldo devedor') THEN RAISE EXCEPTION 'interno no card'; END IF;
  RAISE NOTICE '566 ok';
END $$;
