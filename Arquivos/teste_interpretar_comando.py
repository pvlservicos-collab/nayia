"""
Testa interpretar_comando.py: os 5 exemplos reais do doc 28, variações
de escrita, casos-armadilha que não podem virar adivinhação, e as
variações novas aprovadas pelo Tel (verbo solta/publica/publicar,
VENDIDO/VENDIDA/ALUGADO/ALUGADA, horário por extenso, "todo santo
dia", dia da semana sem hífen).

Uso:
    .venv/bin/python teste_interpretar_comando.py
"""
import datetime

from interpretar_comando import interpretar_comando

CASOS_DOC28 = [
    ("posta o 5750",
     {"acao": "postar_agora", "codigos": ["5750"]}),
    ("posta o 5750 todo dia às 14h",
     {"acao": "criar_vaga", "tipo_recorrencia": "diaria",
      "horario": datetime.time(14, 0), "codigos": ["5750"]}),
    ("posta 5750, 5751 e 5752 terça e quinta às 9h",
     {"acao": "criar_vaga", "tipo_recorrencia": "semanal",
      "horario": datetime.time(9, 0), "dias_semana": [2, 4],
      "codigos": ["5750", "5751", "5752"]}),
    ("VENDEU 5750",
     {"acao": "liberar_vaga", "codigo": "5750"}),
    ("ALUGOU 5750",
     {"acao": "liberar_vaga", "codigo": "5750"}),
    ("VAGAS",
     {"acao": "listar_vagas"}),
]

CASOS_VARIACAO = [
    ("posta O 5750  ",  # maiuscula, espaço extra
     {"acao": "postar_agora", "codigos": ["5750"]}),
    ("vendeu 5750",  # minusculo
     {"acao": "liberar_vaga", "codigo": "5750"}),
    ("vagas",  # minusculo
     {"acao": "listar_vagas"}),
    ("posta o 5750 toda terca as 9h",  # sem acento, sem crase, um dia so
     {"acao": "criar_vaga", "tipo_recorrencia": "semanal",
      "horario": datetime.time(9, 0), "dias_semana": [2], "codigos": ["5750"]}),
    ("posta o 5750 todos os dias às 8:30",  # variação de "todo dia", hora com minuto
     {"acao": "criar_vaga", "tipo_recorrencia": "diaria",
      "horario": datetime.time(8, 30), "codigos": ["5750"]}),
    ("oi, tudo bem?",  # nada a ver -- não pode virar adivinhação
     {"acao": "nao_reconhecido", "texto": "oi, tudo bem?"}),
    ("posta o 5750 amanhã às 14h",  # dia que o parser não conhece -- não pode inventar
     {"acao": "nao_reconhecido", "texto": "posta o 5750 amanhã às 14h"}),
]

# --- variações novas aprovadas pelo Tel -------------------------------

CASOS_VERBO_POSTAR = [
    ("solta o 5750",
     {"acao": "postar_agora", "codigos": ["5750"]}),
    ("publica o 5750 todo dia às 14h",  # "publica" não funcionava antes deste commit
     {"acao": "criar_vaga", "tipo_recorrencia": "diaria",
      "horario": datetime.time(14, 0), "codigos": ["5750"]}),
    ("publicar o 5750",  # "publicar" idem
     {"acao": "postar_agora", "codigos": ["5750"]}),
    ("dispara o 5750",  # "dispara"/"disparar" adicionados depois do cron da grade
     {"acao": "postar_agora", "codigos": ["5750"]}),
    ("disparar o 5750 todo dia às 14h",
     {"acao": "criar_vaga", "tipo_recorrencia": "diaria",
      "horario": datetime.time(14, 0), "codigos": ["5750"]}),
]

CASOS_VERBO_LIBERAR = [
    ("VENDIDA 5750",
     {"acao": "liberar_vaga", "codigo": "5750"}),
    ("ALUGADA 5750",
     {"acao": "liberar_vaga", "codigo": "5750"}),
    ("vendido 5750",  # "vendido" não funcionava antes deste commit
     {"acao": "liberar_vaga", "codigo": "5750"}),
    ("alugado 5750",  # "alugado" idem
     {"acao": "liberar_vaga", "codigo": "5750"}),
]

CASOS_REMOVER_DA_GRADE = [
    # ação separada de liberar_vaga de propósito: tira da grade sem
    # dizer que o imóvel foi vendido/alugado
    ("tira o 5750",
     {"acao": "remover_da_grade", "codigo": "5750"}),
    ("tirar o 5750",
     {"acao": "remover_da_grade", "codigo": "5750"}),
    ("remove o 5750",
     {"acao": "remover_da_grade", "codigo": "5750"}),
    ("remover o 5750",
     {"acao": "remover_da_grade", "codigo": "5750"}),
    ("TIRA O 5750",  # maiúsculas
     {"acao": "remover_da_grade", "codigo": "5750"}),
    ("remove o 5750 da grade",  # texto extra depois do código
     {"acao": "remover_da_grade", "codigo": "5750"}),
    ("tira o 5750 do anunciar easy",  # NÃO pode virar postar_easy -- postar não tem desfazer
     {"acao": "remover_da_grade", "codigo": "5750"}),
    ("tira o 5750 e o 5751",  # 2 códigos -- só aceita 1, igual liberar_vaga
     {"acao": "nao_reconhecido", "texto": "tira o 5750 e o 5751"}),
    ("tira",  # sem código -- não pode inventar
     {"acao": "nao_reconhecido", "texto": "tira"}),
    ("vendeu 5750",  # regressão: liberar_vaga continua sendo liberar_vaga
     {"acao": "liberar_vaga", "codigo": "5750"}),
]

CASOS_HORARIO_EXTENSO = [
    ("posta o 5750 todo dia às 14 horas",
     {"acao": "criar_vaga", "tipo_recorrencia": "diaria",
      "horario": datetime.time(14, 0), "codigos": ["5750"]}),
    ("posta o 5750 terça às 9 e meia",
     {"acao": "criar_vaga", "tipo_recorrencia": "semanal",
      "horario": datetime.time(9, 30), "dias_semana": [2], "codigos": ["5750"]}),
    ("posta o 5750 todo dia ao meio-dia",
     {"acao": "criar_vaga", "tipo_recorrencia": "diaria",
      "horario": datetime.time(12, 0), "codigos": ["5750"]}),
    ("posta o 5750 todo dia à meia-noite",
     {"acao": "criar_vaga", "tipo_recorrencia": "diaria",
      "horario": datetime.time(0, 0), "codigos": ["5750"]}),
    ("posta o 5750 todo dia ao meio dia",  # sem hifen, bonus de robustez
     {"acao": "criar_vaga", "tipo_recorrencia": "diaria",
      "horario": datetime.time(12, 0), "codigos": ["5750"]}),
]

CASOS_SEM_TETO_DE_CODIGOS = [
    # decisão do Tel: sem cap artificial -- qualquer quantidade > 0 vale
    ("posta 45, 5751, 5752 e 5753 segunda às 10h",  # 4 codigos, com hora
     {"acao": "criar_vaga", "tipo_recorrencia": "semanal",
      "horario": datetime.time(10, 0), "dias_semana": [1],
      "codigos": ["45", "5751", "5752", "5753"]}),
    ("posta 1, 2, 3, 4, 5 e 6",  # 6 codigos, sem hora (postar_agora)
     {"acao": "postar_agora", "codigos": ["1", "2", "3", "4", "5", "6"]}),
]

CASOS_POSTAR_EASY = [
    ("publica no nosso grupo anunciar easy código 5750",
     {"acao": "postar_easy", "codigo": "5750"}),
    ("poste no anunciar easy o 5750",  # verbo "poste" nem está em VERBOS_POSTAR -- não importa aqui
     {"acao": "postar_easy", "codigo": "5750"}),
    ("EASY 5750 ANUNCIAR",  # ordem invertida, maiúsculas
     {"acao": "postar_easy", "codigo": "5750"}),
    ("manda pro grupo de anunciar da easy 5750",  # texto no meio
     {"acao": "postar_easy", "codigo": "5750"}),
    ("publica no anunciar easy",  # sem código -- não pode inventar
     {"acao": "nao_reconhecido", "texto": "publica no anunciar easy"}),
    ("publica no anunciar easy 5750 e 5751",  # 2 códigos -- só aceita 1
     {"acao": "nao_reconhecido", "texto": "publica no anunciar easy 5750 e 5751"}),
    ("publica o 5750",  # sem "anunciar"/"easy" -- continua postar_agora normal
     {"acao": "postar_agora", "codigos": ["5750"]}),
]

CASOS_TODO_SANTO_DIA = [
    ("posta o 5750 todo santo dia às 14h",
     {"acao": "criar_vaga", "tipo_recorrencia": "diaria",
      "horario": datetime.time(14, 0), "codigos": ["5750"]}),
]

CASOS_DIA_SEM_HIFEN = [
    ("posta o 5750 quarta feira às 9h",
     {"acao": "criar_vaga", "tipo_recorrencia": "semanal",
      "horario": datetime.time(9, 0), "dias_semana": [3], "codigos": ["5750"]}),
    ("posta o 5750 segunda feira e terca feira às 9h",
     {"acao": "criar_vaga", "tipo_recorrencia": "semanal",
      "horario": datetime.time(9, 0), "dias_semana": [1, 2], "codigos": ["5750"]}),
]

# --- vocativo: o Tel chama a Nay pelo nome antes do comando ----------

CASOS_VOCATIVO = [
    # o caso real de 27/08: o Tel mandou isto no WhatsApp e o comando
    # morreu em nao_reconhecido antes de chegar no publicador
    ("Nay posta o 2943",
     {"acao": "postar_agora", "codigos": ["2943"]}),
    ("Nay, posta o 2943",  # com vírgula
     {"acao": "postar_agora", "codigos": ["2943"]}),
    ("nay posta o 2943",  # minúsculo
     {"acao": "postar_agora", "codigos": ["2943"]}),
    ("NAY POSTA O 2943",  # tudo maiúsculo
     {"acao": "postar_agora", "codigos": ["2943"]}),
    ("@Nay posta o 2943",  # menção
     {"acao": "postar_agora", "codigos": ["2943"]}),
    ("Nay: posta o 2943",  # dois pontos
     {"acao": "postar_agora", "codigos": ["2943"]}),
    # o vocativo vale nos SEIS caminhos, não só no de postar -- era essa
    # a inconsistência: só o Easy funcionava, porque EASY_RE usa search
    ("Nay VAGAS",
     {"acao": "listar_vagas"}),
    ("Nay, vagas",
     {"acao": "listar_vagas"}),
    ("Nay vendeu 5750",
     {"acao": "liberar_vaga", "codigo": "5750"}),
    ("Nay tira o 5750",
     {"acao": "remover_da_grade", "codigo": "5750"}),
    ("Nay publica no anunciar easy o 5750",  # regressão: já funcionava antes
     {"acao": "postar_easy", "codigo": "5750"}),
    ("Nay posta o 5750 todo dia às 14h",
     {"acao": "criar_vaga", "tipo_recorrencia": "diaria",
      "horario": datetime.time(14, 0), "codigos": ["5750"]}),
    ("nay, posta 5750 e 5751 terca e quinta as 9h",
     {"acao": "criar_vaga", "tipo_recorrencia": "semanal",
      "horario": datetime.time(9, 0), "dias_semana": [2, 4],
      "codigos": ["5750", "5751"]}),
]

CASOS_VOCATIVO_NEGATIVOS = [
    # Esta é a parte que sustenta a mudança. Descartar o "Nay" tira uma
    # trava acidental: frases que hoje morrem só por começarem com o nome
    # dela passariam a virar envio real em 9 grupos, que não tem desfazer.
    # Cada caso aqui é um disparo que NÃO pode acontecer.

    # nome parecido não é vocativo -- o \b do VOCATIVO_RE é o que protege
    ("Nayara, posta o 5750",
     {"acao": "nao_reconhecido", "texto": "Nayara, posta o 5750"}),
    ("Naiara posta o 5750",
     {"acao": "nao_reconhecido", "texto": "Naiara posta o 5750"}),
    ("naysa posta o 5750",
     {"acao": "nao_reconhecido", "texto": "naysa posta o 5750"}),

    # prefixo de verbo sem fronteira de palavra: PERGUNTA sobre o
    # passado, não ordem de postar. Antes do POSTAR_RE, o startswith
    # aceitava todas estas como se fossem o verbo.
    ("Nay, publicamos o 5750 ontem?",
     {"acao": "nao_reconhecido", "texto": "Nay, publicamos o 5750 ontem?"}),
    ("Nay, postaram o 5750 no grupo?",
     {"acao": "nao_reconhecido", "texto": "Nay, postaram o 5750 no grupo?"}),
    ("Nay, postado o 5750?",
     {"acao": "nao_reconhecido", "texto": "Nay, postado o 5750?"}),
    ("Nay, a postagem de ontem tinha o 5750?",
     {"acao": "nao_reconhecido", "texto": "Nay, a postagem de ontem tinha o 5750?"}),
    ("Nay, soltaram o 5750?",
     {"acao": "nao_reconhecido", "texto": "Nay, soltaram o 5750?"}),
    ("Nay, o 5750 já foi publicado?",
     {"acao": "nao_reconhecido", "texto": "Nay, o 5750 já foi publicado?"}),

    # vocativo fora do começo: fica de fora de propósito. Cobrir isso
    # seria adivinhar; a resposta de nao_reconhecido ensina o formato.
    ("oi Nay posta o 5750",
     {"acao": "nao_reconhecido", "texto": "oi Nay posta o 5750"}),

    # sem comando nenhum depois do nome
    ("Nay",
     {"acao": "nao_reconhecido", "texto": "Nay"}),
    ("Nay bom dia",
     {"acao": "nao_reconhecido", "texto": "Nay bom dia"}),
    ("Nay, o 5750 já foi vendido?",  # pergunta, não é o comando VENDEU
     {"acao": "nao_reconhecido", "texto": "Nay, o 5750 já foi vendido?"}),

    # o texto devolvido é o que o Tel escreveu, COM o "Nay": a resposta do
    # publicador cita ele de volta, e citar frase que ele não escreveu
    # confunde. Por isso todos os esperados acima repetem o original.
    ("Nay posta o 5750 amanhã às 14h",  # dia que o parser não conhece
     {"acao": "nao_reconhecido", "texto": "Nay posta o 5750 amanhã às 14h"}),
]

# Comportamento conhecido e aceito, fixado aqui pra que qualquer mudança
# futura apareça no diff em vez de passar despercebida: "tira" é verbo de
# remover da grade, então "tira uma dúvida" com um código na frente vira
# remover_da_grade. É reorganização de horário -- reversível, ao
# contrário de postar. Não vale endurecer o parser por isso sem o Tel pedir.
CASOS_LIMITE_CONHECIDO = [
    ("Nay tira uma duvida: o 5750 ja foi vendido?",
     {"acao": "remover_da_grade", "codigo": "5750"}),
]

# --- alternância que o parser AINDA não sabe montar -------------------

# Medido em 27/08 contra o parser em produção, ANTES da guarda existir:
#   "posta o 5750 a cada 15 dias"  ->  postar_agora ['5750', '15']
# Ou seja: postava o 5750 E tentava o imóvel 15, na hora, em 14 grupos
# reais, sem desfazer. E "segunda sim segunda não" criava vaga SEMANAL em
# silêncio -- o Tel pediu para pular uma semana e o imóvel sairia em todas.
#
# Recusar é o comportamento certo enquanto a gramática não existir:
# adivinhar "toda semana" quando ele escreveu "semana sim, semana não" é
# adivinhação com custo irreversível. Quando a vaga alternante for
# implementada, ESTES casos mudam de expectativa -- e mudar este bloco é
# o sinal de que a mudança foi deliberada, não acidental.
CASOS_ALTERNANCIA_AINDA_NAO_SUPORTADA = [
    ('posta o 5750 a cada 15 dias',
     {"acao": "nao_reconhecido", "texto": 'posta o 5750 a cada 15 dias'}),
    ('posta o 5750 de 15 em 15 dias',
     {"acao": "nao_reconhecido", "texto": 'posta o 5750 de 15 em 15 dias'}),
    ('posta o 5750 a cada 2 semanas às 14h',
     {"acao": "nao_reconhecido", "texto": 'posta o 5750 a cada 2 semanas às 14h'}),
    ('posta o 5750 a cada duas semanas às 14h',
     {"acao": "nao_reconhecido", "texto": 'posta o 5750 a cada duas semanas às 14h'}),
    ('posta o 5750 segunda sim segunda nao as 13h30',
     {"acao": "nao_reconhecido", "texto": 'posta o 5750 segunda sim segunda nao as 13h30'}),
    ('posta o 5750 terça sim terça não às 8h',
     {"acao": "nao_reconhecido", "texto": 'posta o 5750 terça sim terça não às 8h'}),
    ('posta o 5750 semana sim semana não às 9h',
     {"acao": "nao_reconhecido", "texto": 'posta o 5750 semana sim semana não às 9h'}),
    ('posta o 5750 quinzenal',
     {"acao": "nao_reconhecido", "texto": 'posta o 5750 quinzenal'}),
    ('posta o 5750 toda segunda quinzenal às 13h30',
     {"acao": "nao_reconhecido", "texto": 'posta o 5750 toda segunda quinzenal às 13h30'}),
    ('posta o 5750 alternando as segundas',
     {"acao": "nao_reconhecido", "texto": 'posta o 5750 alternando as segundas'}),
    ('posta o 5750 alternado toda segunda às 9h',
     {"acao": "nao_reconhecido", "texto": 'posta o 5750 alternado toda segunda às 9h'}),
    ('posta o 5750 alternar segundas',
     {"acao": "nao_reconhecido", "texto": 'posta o 5750 alternar segundas'}),
    ('posta o 5750 em alternancia as segundas',
     {"acao": "nao_reconhecido", "texto": 'posta o 5750 em alternancia as segundas'}),
    ('posta o 5750 com alternância às segundas',
     {"acao": "nao_reconhecido", "texto": 'posta o 5750 com alternância às segundas'}),
    ('Nay posta o 5750 a cada 15 dias',
     {"acao": "nao_reconhecido", "texto": 'Nay posta o 5750 a cada 15 dias'}),
]

# O regex da guarda não pode ser guloso: estas frases NÃO são alternância
# e precisam continuar funcionando como antes.
CASOS_ALTERNANCIA_FALSO_POSITIVO = [
    ("posta o 5750 como alternativa",  # "alternativa" não é "alternado"
     {"acao": "postar_agora", "codigos": ["5750"]}),
    ("posta o 5750 alternativa boa",
     {"acao": "postar_agora", "codigos": ["5750"]}),
    ("posta o 5750 toda segunda às 13h30",  # semanal comum, sem alternar
     {"acao": "criar_vaga", "tipo_recorrencia": "semanal",
      "horario": datetime.time(13, 30), "dias_semana": [1], "codigos": ["5750"]}),
]

CASOS_COMBINADO = [
    # varias features novas juntas, pra confirmar que compoem sem briga
    ("solta 5750 e 5751 quinta feira e sexta feira às 9 e meia",
     {"acao": "criar_vaga", "tipo_recorrencia": "semanal",
      "horario": datetime.time(9, 30), "dias_semana": [4, 5],
      "codigos": ["5750", "5751"]}),
]


def _rodar(nome_secao, casos):
    global falhas
    print(f"--- {nome_secao} ---")
    for texto, esperado in casos:
        obtido = interpretar_comando(texto)
        ok = obtido == esperado
        falhas += 0 if ok else 1
        print(f"{texto!r} -> {obtido} {'OK' if ok else 'FALHOU (esperado ' + repr(esperado) + ')'}")
    print()


falhas = 0
_rodar("5 exemplos reais do doc 28", CASOS_DOC28)
_rodar("variações de escrita e casos que não podem virar adivinhação", CASOS_VARIACAO)
_rodar("verbo de postar: solta/publica/publicar", CASOS_VERBO_POSTAR)
_rodar("verbo de liberar: VENDIDA/ALUGADA/vendido/alugado", CASOS_VERBO_LIBERAR)
_rodar("remover da grade: tira/tirar/remove/remover (sem marcar vendido)", CASOS_REMOVER_DA_GRADE)
_rodar("horário por extenso: horas/e meia/meio-dia/meia-noite", CASOS_HORARIO_EXTENSO)
_rodar("sem teto de códigos por vaga (decisão do Tel: ilimitado)", CASOS_SEM_TETO_DE_CODIGOS)
_rodar("comando dedicado do Easy: postar_easy", CASOS_POSTAR_EASY)
_rodar("todo santo dia", CASOS_TODO_SANTO_DIA)
_rodar("dia da semana sem hífen", CASOS_DIA_SEM_HIFEN)
_rodar("combinado: várias features novas juntas", CASOS_COMBINADO)
_rodar("vocativo: o Tel chama a Nay pelo nome antes do comando", CASOS_VOCATIVO)
_rodar("vocativo: o que NÃO pode virar comando (a parte que sustenta a mudança)",
       CASOS_VOCATIVO_NEGATIVOS)
_rodar("limite conhecido e aceito do vocativo", CASOS_LIMITE_CONHECIDO)
_rodar("alternância que o parser ainda NÃO sabe montar (recusa explícita)",
       CASOS_ALTERNANCIA_AINDA_NAO_SUPORTADA)
_rodar("a guarda de alternância não pode ser gulosa", CASOS_ALTERNANCIA_FALSO_POSITIVO)

print(f"{'TODOS OS CASOS PASSARAM' if falhas == 0 else str(falhas) + ' CASO(S) FALHARAM'}")
