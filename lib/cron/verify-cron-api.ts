export class CronAuthError extends Error {
  status: number;

  constructor(message: string, status = 401) {
    super(message);
    this.status = status;
  }
}

const normalizeToken = (value: string | null) => {
  if (!value) return "";
  const trimmed = value.trim();
  if (trimmed.toLowerCase().startsWith("bearer ")) {
    return trimmed.slice(7).trim();
  }
  return trimmed;
};

export const verifyCronApiKey = (req: Request) => {
  const expected = process.env.CRON_API;
  if (!expected) {
    throw new CronAuthError("Cron API key is not configured.");
  }

  const headerValue =
    req.headers.get("authorization") || req.headers.get("x-cron-api-key");
  const token = normalizeToken(headerValue);

  if (!token || token !== expected) {
    throw new CronAuthError("Unauthorized cron request.");
  }
};
