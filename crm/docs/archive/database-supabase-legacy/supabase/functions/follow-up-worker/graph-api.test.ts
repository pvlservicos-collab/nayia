import { assertEquals } from 'https://deno.land/std@0.208.0/assert/mod.ts';
import { buildTemplatePayload, buildTextPayload } from './graph-api.ts';

Deno.test('template payload omits components entirely', () => {
  const p = buildTemplatePayload({ to: '559292034074', templateName: 'follow_up_avaliacao', languageCode: 'pt_BR' });
  assertEquals(p, {
    messaging_product: 'whatsapp',
    to: '559292034074',
    type: 'template',
    template: { name: 'follow_up_avaliacao', language: { code: 'pt_BR' } },
  });
});

Deno.test('template payload strips leading +', () => {
  const p = buildTemplatePayload({ to: '+559292034074', templateName: 'x', languageCode: 'pt_BR' });
  assertEquals(p.to, '559292034074');
});

Deno.test('text payload structure', () => {
  const p = buildTextPayload({ to: '559292034074', body: 'Oi, podemos continuar?' });
  assertEquals(p, {
    messaging_product: 'whatsapp',
    to: '559292034074',
    type: 'text',
    text: { body: 'Oi, podemos continuar?' },
  });
});
