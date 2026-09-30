"""O orquestrador de UM turno, na ordem: identidade -> contexto -> pré-roteador ->
(classificador) -> estado -> ferramentas -> compositor -> validador -> saída. Grava trace
de cada etapa. Não decide nada sozinho: só chama os setores na ordem.
"""
