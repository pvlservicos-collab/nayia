export interface BusinessHoursConfig {
  start_hour: number;
  end_hour: number;
  tz: string;
}

export function isWithinBusinessHours(now: Date, cfg: BusinessHoursConfig): boolean {
  const fmt = new Intl.DateTimeFormat('en-US', {
    timeZone: cfg.tz,
    hour: 'numeric',
    hour12: false,
  });
  const hourStr = fmt.format(now);
  const hour = Number(hourStr) % 24;
  return hour >= cfg.start_hour && hour < cfg.end_hour;
}
