type AllowedRule =
  | { type: "any" }
  | { type: "email"; value: string }
  | { type: "domain"; value: string };

function parseAllowedRules(raw: string | undefined): AllowedRule[] {
  if (!raw) return [];
  const items = raw
    .split(",")
    .map((value) => value.trim().toLowerCase())
    .filter(Boolean);

  if (items.includes("*")) {
    return [{ type: "any" }];
  }

  return items.map((item) => {
    if (item.startsWith("@") && item.length > 1) {
      return { type: "domain", value: item.slice(1) };
    }
    if (item.includes("@")) {
      return { type: "email", value: item };
    }
    return { type: "domain", value: item };
  });
}

export function getAllowedUserRules() {
  return parseAllowedRules(process.env.ALLOWED_USER_EMAILS);
}

export function isAllowedUserEmail(email?: string | null) {
  if (!email) return false;
  const normalized = email.trim().toLowerCase();
  const allowed = getAllowedUserRules();
  if (allowed.length === 0) return false;
  if (allowed.some((rule) => rule.type === "any")) return true;

  const domain = normalized.split("@")[1];
  return allowed.some((rule) => {
    if (rule.type === "email") {
      return rule.value === normalized;
    }
    if (rule.type === "domain") {
      return !!domain && rule.value === domain;
    }
    return false;
  });
}
