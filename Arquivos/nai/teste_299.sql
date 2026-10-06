-- testes da 299, rodam DENTRO da transação do ensaio (antes do ROLLBACK)

-- a marca: o 3647 marcado; o 3210 (nosso) e o 5180 ("indicado por", não captador) intactos
SELECT 'marca' AS teste, codigo, e_parceiro, captado_por FROM imoveis WHERE codigo IN (3647, 3210, 5180) ORDER BY codigo;

-- o sincronizador tentando desligar a marca: o gatilho religa
UPDATE imoveis SET e_parceiro = false WHERE codigo = 3647;
SELECT 'sync nao desliga' AS teste, codigo, e_parceiro FROM imoveis WHERE codigo = 3647;

-- a função reconhece só a marca entre parênteses
SELECT 'regex' AS teste, nai_captador_e_parceiro('Imob corretor parceiro (Parceiro)') AS deve_ser_t,
       nai_captador_e_parceiro('Vitória Andrya') AS deve_ser_f, nai_captador_e_parceiro('corretor parceiro em geral') AS sem_parenteses_f;

-- a parede na Nay nova: card do 3647 para corretor -> bloqueado
INSERT INTO core_saida (turno_id, chave_destino, ordem, tipo, texto, codigo, estado, papel_destino)
SELECT id, 'ensaio', 901, 'texto', '🏠 Apartamento para venda' || chr(10) || '📍 Solar da Praia, Ponta Negra' || chr(10) || 'Código: 3647', 3647, 'pendente', 'turno'
  FROM core_turno ORDER BY id DESC LIMIT 1
RETURNING 'card parceiro' AS teste, estado, bloqueio;

-- foto do 3647 -> bloqueado
INSERT INTO core_saida (turno_id, chave_destino, ordem, tipo, imagem_url, codigo, estado, papel_destino)
SELECT id, 'ensaio', 902, 'imagem', 'https://x/foto.jpg', 3647, 'pendente', 'turno'
  FROM core_turno ORDER BY id DESC LIMIT 1
RETURNING 'foto parceiro' AS teste, estado, bloqueio;

-- lista com um parceiro no meio -> bloqueado
INSERT INTO core_saida (turno_id, chave_destino, ordem, tipo, texto, estado, papel_destino)
SELECT id, 'ensaio', 903, 'texto', 'Qual deles?' || chr(10) || '🏠 Ilhas Gregas' || chr(10) || '#3210' || chr(10) || chr(10) || '🏠 Solar da Praia' || chr(10) || '#3647', 'pendente', 'turno'
  FROM core_turno ORDER BY id DESC LIMIT 1
RETURNING 'lista com parceiro' AS teste, estado, bloqueio;

-- card do 3210 (nosso) -> passa
INSERT INTO core_saida (turno_id, chave_destino, ordem, tipo, texto, codigo, estado, papel_destino)
SELECT id, 'ensaio', 904, 'texto', '🏠 Casa de condomínio' || chr(10) || 'Código: 3210', 3210, 'pendente', 'turno'
  FROM core_turno ORDER BY id DESC LIMIT 1
RETURNING 'card nosso' AS teste, estado, bloqueio;

-- texto que só cita o número sem ser card nem lista -> passa
INSERT INTO core_saida (turno_id, chave_destino, ordem, tipo, texto, estado, papel_destino)
SELECT id, 'ensaio', 905, 'texto', 'O 3647 não está mais disponível. Quer que eu procure outro parecido?', 'pendente', 'turno'
  FROM core_turno ORDER BY id DESC LIMIT 1
RETURNING 'fala solta' AS teste, estado, bloqueio;

-- aviso ao Tel sobre o 3647 -> passa
INSERT INTO core_saida (turno_id, chave_destino, ordem, tipo, texto, codigo, estado, papel_destino)
SELECT id, 'ensaio', 906, 'texto', 'Tel, o corretor perguntou sobre o 3647. Código: 3647', 3647, 'pendente', 'tel'
  FROM core_turno ORDER BY id DESC LIMIT 1
RETURNING 'aviso ao tel' AS teste, estado, bloqueio;

-- ninguém desbloqueia o que foi barrado
UPDATE core_saida SET estado = 'pendente', bloqueio = NULL WHERE chave_destino = 'ensaio' AND ordem = 901
RETURNING 'desbloquear' AS teste, estado, bloqueio;
