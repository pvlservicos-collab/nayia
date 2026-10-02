SELECT c.texto_pronto,
  i.disponivel,
  COALESCE(i.e_parceiro,false) AS e_parceiro,
  COALESCE(i.extras->>'aceita financiamento','') AS aceita_financiamento,
  c.qtd_fotos,
  COALESCE(i.administrado,false) AS administrado,
  CASE WHEN COALESCE(i.administrado,false) THEN
    'Este imóvel é ADMINISTRADO pela Imob Easy. Pode passar ao corretor todas as informações que vieram, incluindo o endereço. Se o corretor perguntar quanto precisa para entrar no imóvel, responda que vai verificar e escale ao Tel — o valor de caução varia.'
  ELSE '' END
  || CASE
       -- FORMA DE PAGAMENTO: é derivável, e ela não pode dizer que vai
       -- verificar. Em 30/08 ela respondeu ao Gustavo "aceita
       -- financiamento" e emendou "sobre a forma de pagamento, vou
       -- verificar e retorno" -- tendo o dado na mão.
       WHEN COALESCE(i.valor_venda,0) > 0 AND COALESCE(i.extras->>'aceita financiamento','') ~* '^s' THEN
         ' Se perguntarem a forma de pagamento: este imovel aceita financiamento, entao e A VISTA OU FINANCIADO. Responda direto, NUNCA diga que vai verificar.'
       WHEN COALESCE(i.valor_venda,0) > 0 THEN
         ' Se perguntarem a forma de pagamento: este imovel NAO aceita financiamento, entao e SO A VISTA. Responda direto, NUNCA diga que vai verificar.'
       ELSE ''
     END
  || CASE
       -- A DESCRIÇÃO do anúncio, capturada em 31/08. É onde o Tel escreve
       -- o que a ficha não cabe: o que falta para ficar 100% mobiliado, se
       -- aceita pet, se tem ponto comercial. Vai na INSTRUÇÃO, não no
       -- texto_pronto: serve para RESPONDER pergunta, não para despejar no
       -- card. Sem isto ela ofereceu ao Ênio um mobiliado quando ele pediu
       -- sem mobília, tendo no banco um cuja descrição diz "sem mobília".
       -- PARCEIRO NAO TEM DESCRICAO AQUI. O card ja esconde tudo; sem
       -- este gate a instrucao entregava endereco, CEP, valor e ate o
       -- saldo devedor do proprietario. Falha fechada: so passa quando
       -- e_parceiro prova ser falso.
       WHEN COALESCE(i.e_parceiro, true) THEN ''
       WHEN COALESCE(i.descricao,'') <> '' THEN
         ' O anuncio deste imovel diz: "' ||
         -- `nay_descricao_segura` tira o numero da unidade do texto do
         -- anuncio. Tres anuncios publicam "apto 801", "apart. 601" -- que
         -- o site publique nao autoriza a Nay a entregar de mao beijada.
         replace(nay_descricao_segura(i.descricao), chr(10), ' ')
         || '". Use para responder o que a ficha nao responde, e so o que ele'
         || ' perguntar. NAO repita a descricao inteira sem ele pedir.'
       ELSE ''
     END AS instrucao_para_voce
FROM imoveis i
CROSS JOIN LATERAL nai_card_do_imovel(i.codigo) c
WHERE i.codigo = $1;
