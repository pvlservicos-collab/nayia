## Os arquivos deste projeto (revisão da Nay pelo Gemini)

- `dados/conversas/`: as conversas da Nay Parceria exportadas do banco (o mesmo formato do projeto Nay Parceria:
  `indice.tsv`, `AAAA-MM-DD/_resumo.txt` e `AAAA-MM-DD/<tel4>-<n>.txt`, uma linha por fala, com o RESULTADO no fim).
- `dados/semana/<desde>_a_<ate>/conversas.md`: todas as conversas do período num markdown só (o que foi ao Gemini).
- `dados/semana/<desde>_a_<ate>/erros.md`: SÓ as conversas com erro (nota abaixo de 90): os erros (tipo, gravidade,
  trecho, o que devia, pista para o Claude) e a conversa inteira. É o arquivo que vai ao Claude corrigir.
- `dados/semana/<desde>_a_<ate>/erros.json`: o mesmo, em JSON.

Quem gera: `/opt/agente-claude/gemini_revisao.py` (a semana de hoje; `--desde/--ate` para outro período). Ao terminar,
ele abre uma conversa neste quadro com o resumo.
