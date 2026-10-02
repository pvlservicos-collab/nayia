# Nay - escalar  (id hw18FZjm108KTXa9, atualizado em 2026-10-02 03:31)

nó | tipo | modelo/extra | vai para
---|---|---|---
Receber chamada | executeWorkflowTrigger |  | Consultar escalacao
Consultar escalacao | postgres |  | Tem que escalar?
Tem que escalar? | if |  | Avisar Telegram, Avisar WhatsApp, Devolver
Avisar Telegram | telegram | onError=continueRegularOutput | Devolver
Avisar WhatsApp | httpRequest | onError=continueRegularOutput | Devolver
Devolver | set |  | 
