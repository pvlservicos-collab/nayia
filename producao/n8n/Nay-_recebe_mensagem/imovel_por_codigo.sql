SELECT
  CASE WHEN COALESCE(i.e_parceiro,false) THEN
    '📍 ' || COALESCE(NULLIF(CASE WHEN i.condominio_nome ILIKE '%identificado%' THEN NULL ELSE i.condominio_nome END,''), i.tipo)
    || E'\n• esse imovel e de parceria, nao da imob easy.'
  ELSE
    '📍 ' || COALESCE(NULLIF(CASE WHEN i.condominio_nome ILIKE '%identificado%' THEN NULL ELSE i.condominio_nome END,''), i.tipo)
    || CASE WHEN COALESCE(i.bairro,'') <> '' THEN E'\n• Bairro: ' || i.bairro ELSE '' END
    || CASE WHEN COALESCE(i.administrado,false) AND NOT i.tipo ~* 'apartamento|cobertura|flat' AND COALESCE(i.logradouro,'') <> '' THEN E'\n• Endereço: ' || nay_endereco_sem_numero(i.logradouro) ELSE '' END
    || CASE WHEN i.tipo ~* 'apartamento|cobertura|flat' AND COALESCE(i.sol,'') <> '' THEN E'\n• apto ' || lower(i.sol) ELSE '' END
    || CASE WHEN COALESCE(i.area_util,0) > 0 THEN E'\n• ' || trim(to_char(i.area_util,'FM999990')) || 'm2' ELSE '' END
    || CASE WHEN COALESCE(i.quartos,0) > 0 THEN E'\n• ' || i.quartos || CASE WHEN i.quartos = 1 THEN ' quarto' ELSE ' quartos' END || CASE WHEN COALESCE(i.suites,0) > 0 THEN ' sendo ' || i.suites || CASE WHEN i.suites = 1 THEN ' suíte' ELSE ' suítes' END ELSE '' END ELSE '' END
    || CASE WHEN COALESCE(i.vagas_cobertas,0) > 0 THEN E'\n• ' || i.vagas_cobertas || CASE WHEN i.vagas_cobertas = 1 THEN ' vaga coberta' ELSE ' vagas cobertas' END WHEN COALESCE(i.vagas,0) > 0 THEN E'\n• ' || i.vagas || CASE WHEN i.vagas = 1 THEN ' vaga' ELSE ' vagas' END ELSE '' END
    || CASE WHEN i.tipo ~* 'apartamento|cobertura|flat' AND COALESCE(i.mobilia,'') <> '' THEN E'\n• ' || replace(replace(i.mobilia,'moveis','móveis'),'so ar-condicionado','só ar-condicionado') ELSE '' END
    || CASE WHEN COALESCE(i.taxa_condominio,0) > 0 AND COALESCE(i.extras->>'incluso no aluguel','') !~* 'condom' THEN E'\n• taxa de condomínio: ' || replace(to_char(i.taxa_condominio,'FM999,999,990'),',','.') ELSE '' END
    || CASE WHEN COALESCE(i.valor_venda,0) > 0 THEN E'\nvalor: ' || replace(to_char(i.valor_venda,'FM999,999,990'),',','.') ELSE '' END
    || CASE WHEN COALESCE(i.valor_aluguel,0) > 0 THEN E'\nlocação: ' || replace(to_char(i.valor_aluguel,'FM999,999,990'),',','.') || CASE WHEN COALESCE(i.extras->>'incluso no aluguel','') ~* 'condom' THEN ' (incluso a TX)' ELSE '' END ELSE '' END
    || E'\nCódigo: ' || i.codigo
  END AS texto_pronto,
  i.disponivel,
  COALESCE(i.e_parceiro,false) AS e_parceiro,
  COALESCE(i.extras->>'aceita financiamento','') AS aceita_financiamento,
  CASE WHEN COALESCE(i.e_parceiro,false) THEN 0 ELSE (SELECT count(*) FROM imovel_fotos f WHERE f.codigo = i.codigo) END AS qtd_fotos,
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
WHERE i.codigo = $1;
