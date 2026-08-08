/** Public defaults for Web SDK domains. Hosts may override any field. */
export const PTE_IM_DEFAULT_DOMAINS = {
  apiUrl: 'https://api-im.qxkejiwl.top',
  wsUrl: 'wss://wss.qxkejiwl.top/ws',
  cosDomain: 'https://cos.qxkejiwl.top',
  commerceDomain: 'https://api-im-commerce.qxkejiwl.top',
} as const

export type PteIMDomainOverrides = {
  apiUrl?: string
  wsUrl?: string
  cosDomain?: string
  /** Pass `null` or `''` to disable Commerce; omit to use the default host. */
  commerceDomain?: string | null
}

function nonEmpty(value: string | undefined | null): string | undefined {
  const trimmed = value?.trim()
  return trimmed ? trimmed : undefined
}

/** Merge host overrides onto [PTE_IM_DEFAULT_DOMAINS]. */
export function resolvePteIMDomains(overrides: PteIMDomainOverrides = {}) {
  const commerceOverride = overrides.commerceDomain
  const commerceDomain =
    commerceOverride === undefined
      ? PTE_IM_DEFAULT_DOMAINS.commerceDomain
      : nonEmpty(commerceOverride)

  return {
    apiUrl: nonEmpty(overrides.apiUrl) ?? PTE_IM_DEFAULT_DOMAINS.apiUrl,
    wsUrl: nonEmpty(overrides.wsUrl) ?? PTE_IM_DEFAULT_DOMAINS.wsUrl,
    cosDomain: nonEmpty(overrides.cosDomain) ?? PTE_IM_DEFAULT_DOMAINS.cosDomain,
    commerceDomain,
  }
}
