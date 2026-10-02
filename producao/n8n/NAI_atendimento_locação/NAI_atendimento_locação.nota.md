## NAI atendimento locação
Cópia do "Nay- recebe mensagem" + a visita de verdade (proprietário, Fernando, lembretes).

**Toda mensagem que sai passa pela caixa `nai_saida`** e pelo CHECK DUPLO: o banco confere que o destino é parte da conversa ou da visita, e o nó "Conferir cabeçalho" confere de novo em JavaScript antes da Z-API.

**Quem cai aqui:** decide `nai_config.modo` (desligado / teste / todos). O fluxo antigo pergunta ao banco em cada mensagem.
