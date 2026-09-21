import { assertEquals } from 'https://deno.land/std@0.208.0/assert/mod.ts';
import { isWithinBusinessHours } from './business-hours.ts';

Deno.test('08:00 Manaus is within [8,18)', () => {
  const now = new Date('2026-04-13T12:00:00Z');
  assertEquals(isWithinBusinessHours(now, { start_hour: 8, end_hour: 18, tz: 'America/Manaus' }), true);
});

Deno.test('17:59 Manaus is within [8,18)', () => {
  const now = new Date('2026-04-13T21:59:00Z');
  assertEquals(isWithinBusinessHours(now, { start_hour: 8, end_hour: 18, tz: 'America/Manaus' }), true);
});

Deno.test('18:00 Manaus is OUT (end_hour exclusive)', () => {
  const now = new Date('2026-04-13T22:00:00Z');
  assertEquals(isWithinBusinessHours(now, { start_hour: 8, end_hour: 18, tz: 'America/Manaus' }), false);
});

Deno.test('07:59 Manaus is OUT', () => {
  const now = new Date('2026-04-13T11:59:00Z');
  assertEquals(isWithinBusinessHours(now, { start_hour: 8, end_hour: 18, tz: 'America/Manaus' }), false);
});

Deno.test('midnight UTC maps to 20:00 Manaus — OUT', () => {
  const now = new Date('2026-04-14T00:00:00Z');
  assertEquals(isWithinBusinessHours(now, { start_hour: 8, end_hour: 18, tz: 'America/Manaus' }), false);
});
