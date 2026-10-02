UPDATE mensagens SET status = 'Processando' WHERE telefone = $1 AND status = 'Recebido' AND fluxo = 'nai' RETURNING id, telefone, nome, origem, texto, citado, citado_id, criada_em,
  -- Calculados AQUI, e nao no `Gravar na fila`: e deste no que o
  -- `Juntar mensagens` le. Ficando so la, chegavam como undefined e
  -- a segunda camada inteira era letra morta.
  -- O primeiro nome da pessoa, ou NULL quando o nome e de empresa.
  -- Calculado aqui pelo mesmo motivo dos de baixo: e deste no que o
  -- `Juntar mensagens` le.
  nay_nome_de_pessoa(nome) AS nome_pessoa,
  nay_pede_localizacao_da_unidade(texto) AS pede_unidade,
  -- O que ele pediu neste turno, por mensagem. O `Juntar mensagens`
  -- combina: locacao numa linha + venda na outra vira "ambos".
  nay_pede_visita(texto) AS pede_visita,
  -- De qual imovel esta conversa vem falando. Sai do DADO (envios,
  -- mensagens, mensagem_saida), nao da memoria do modelo -- o caminho
  -- do codigo puro nao passa pelo agente e nao entra em `nay_memoria`.
  nay_aviso_do_foco(telefone) AS foco_aviso,
  -- A MESMA funcao que o portao de fotos usa na hora de enviar.
  -- Sem isso ela anuncia album que nao sai.
  nay_deve_mandar_fotos(telefone, texto) AS manda_fotos,
  nay_negocio_pedido(texto) AS negocio_pedido,
  nay_codigos_citados(coalesce(texto,'')) AS codigos_citados,
  -- A citacao vira o codigo do imovel por IGUALDADE de messageId.
  -- NULL quando nao resolve, e nao resolver continua levando a
  -- perguntar -- nunca a chutar.
  nay_imovel_da_citacao(citado_id) AS codigo_citado,
  -- Quando a mensagem citada fala de mais de um imovel, a lista dela.
  nay_opcoes_da_citacao(citado_id) AS opcoes_citacao;
