# Nay - responder pendencia  (id NayRespConv00001, atualizado em 2026-10-02 03:31)

nó | tipo | modelo/extra | vai para
---|---|---|---
Receber chamada | executeWorkflowTrigger |  | Consultar
Consultar | postgres |  | Pode enviar?
Pode enviar? | if |  | Avisar corretor, Devolver
Avisar corretor | httpRequest | onError=continueRegularOutput | Devolver
Devolver | set |  | 
