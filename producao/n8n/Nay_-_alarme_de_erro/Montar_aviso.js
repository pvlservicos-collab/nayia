// Monta o texto do alarme a partir do payload do Error Trigger.
//
// O BUG QUE ISSO CONSERTA (medido em 27/08): cada no de envio montava o
// texto por conta propria a partir de $json -- e no n8n $json e a saida do
// no ANTERIOR, nao a do gatilho. Como 'Avisar o Tel' vinha DEPOIS do
// Telegram, ele lia a resposta da API do Telegram, onde nao existe
// 'workflow' nem 'execution'. Resultado no WhatsApp do Tel:
//   Workflow: ?  /  No: ?  /  Erro: ?
// Um alarme que nao diz o que falhou custa exatamente o tempo que deveria
// economizar.
//
// Ler do gatilho pelo nome e seguro aqui: o Error Trigger SEMPRE roda --
// e ele que dispara este fluxo. Nao e o caso da Parte 4.2 do historico.
const e = $('Quando a Nay falhar').first().json || {};

const nome = (e.workflow && e.workflow.name) ? e.workflow.name : null;

// 'execution' e a forma quando a falha e de execucao; 'trigger' e a forma
// quando a falha e na ativacao do gatilho. Cobrir as duas.
const no = (e.execution && e.execution.lastNodeExecuted) ? e.execution.lastNodeExecuted
         : (e.trigger && e.trigger.error && e.trigger.error.node) ? e.trigger.error.node
         : null;

const erro = (e.execution && e.execution.error && e.execution.error.message) ? e.execution.error.message
           : (e.trigger && e.trigger.error && e.trigger.error.message) ? e.trigger.error.message
           : (e.error && e.error.message) ? e.error.message
           : null;

const execId = (e.execution && e.execution.id) ? e.execution.id : null;

let m = '\u{1F6A8} A Nay falhou';
m += '\n\nFluxo: ' + (nome || '?');
m += '\nNo: ' + (no || '?');
m += '\nErro: ' + (erro || '?');
if (execId) { m += '\nExecucao: ' + execId; }

// Rede de seguranca: se algum campo essencial nao veio, manda o payload
// cru. Assim a PROXIMA falha se explica sozinha, seja qual for a forma.
if (!nome || !no || !erro) {
  let cru;
  try { cru = JSON.stringify(e); } catch (x) { cru = String(e); }
  m += '\n\n(nao reconheci o formato do aviso. payload cru:)\n' + cru.slice(0, 600);
}

return [{ json: { mensagem: m } }];
