import { resolveCname } from "node:dns/promises";

import { getApexDomain } from "@/lib/domains";
import {
  DomainConfigResponse,
  DomainResponse,
  DomainVerificationStatusProps,
} from "@/lib/types";

const normalizeHost = (value: string) =>
  value.trim().toLowerCase().replace(/\.$/, "");

export const isSelfHostedDomainProvider = () =>
  process.env.CUSTOM_DOMAIN_PROVIDER === "selfhosted";

export const getExpectedCnameTarget = () =>
  process.env.CUSTOM_DOMAIN_CNAME_TARGET?.trim();

export async function getSelfHostedDomainStatus(domain: string): Promise<{
  status: DomainVerificationStatusProps;
  domainJson: DomainResponse & { error?: { code: string; message: string } };
  configJson: DomainConfigResponse & {
    provider?: "selfhosted";
    recommendedCNAME?: { value: string }[];
  };
}> {
  const apexName = getApexDomain(`https://${domain}`) || domain;
  const expectedTargetRaw = getExpectedCnameTarget();
  const expectedTarget = expectedTargetRaw
    ? normalizeHost(expectedTargetRaw)
    : "";

  if (!expectedTarget) {
    return {
      status: "Unknown Error",
      domainJson: {
        name: domain,
        apexName,
        projectId: "selfhosted",
        verified: false,
        verification: [],
        error: {
          code: "missing_cname_target",
          message:
            "CUSTOM_DOMAIN_CNAME_TARGET is not set on the server. Set it to your ingress hostname.",
        },
      },
      configJson: {
        misconfigured: true,
        conflicts: [],
        configuredBy: "CNAME",
        acceptedChallenges: ["dns-01"],
        provider: "selfhosted",
        recommendedCNAME: [],
      },
    };
  }

  try {
    const records = await resolveCname(domain);
    const normalized = records.map(normalizeHost);
    const matches = normalized.includes(expectedTarget);
    const status: DomainVerificationStatusProps = matches
      ? "Valid Configuration"
      : "Invalid Configuration";

    return {
      status,
      domainJson: {
        name: domain,
        apexName,
        projectId: "selfhosted",
        verified: matches,
        verification: [],
      },
      configJson: {
        misconfigured: !matches,
        conflicts: [],
        configuredBy: "CNAME",
        acceptedChallenges: ["dns-01"],
        provider: "selfhosted",
        recommendedCNAME: [{ value: expectedTarget }],
      },
    };
  } catch (error) {
    const code = (error as NodeJS.ErrnoException).code;
    const isNotFound = code === "ENODATA" || code === "ENOTFOUND";

    return {
      status: isNotFound ? "Domain Not Found" : "Unknown Error",
      domainJson: {
        name: domain,
        apexName,
        projectId: "selfhosted",
        verified: false,
        verification: [],
        ...(isNotFound
          ? {}
          : {
              error: {
                code: code || "dns_error",
                message: "Failed to resolve CNAME record for this domain.",
              },
            }),
      },
      configJson: {
        misconfigured: true,
        conflicts: [],
        configuredBy: "CNAME",
        acceptedChallenges: ["dns-01"],
        provider: "selfhosted",
        recommendedCNAME: [{ value: expectedTarget }],
      },
    };
  }
}
