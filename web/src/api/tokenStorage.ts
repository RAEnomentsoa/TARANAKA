import type { TokenPair } from './types'

/**
 * The access token lives in memory only. The refresh token is kept in
 * sessionStorage so a page reload keeps the session, and closing the tab
 * ends it. Each refresh token works once (rotation): always store the new one.
 */
const REFRESH_KEY = 'taranaka.refresh'

let accessToken: string | null = null

function storage(): Storage | null {
  try {
    return window.sessionStorage
  } catch {
    return null
  }
}

export const tokenStorage = {
  getAccess(): string | null {
    return accessToken
  },
  getRefresh(): string | null {
    try {
      return storage()?.getItem(REFRESH_KEY) ?? null
    } catch {
      return null
    }
  },
  save(tokens: TokenPair): void {
    accessToken = tokens.access
    try {
      storage()?.setItem(REFRESH_KEY, tokens.refresh)
    } catch {
      // Private mode or storage disabled: the session ends with the page.
    }
  },
  clear(): void {
    accessToken = null
    try {
      storage()?.removeItem(REFRESH_KEY)
    } catch {
      // Nothing to clear.
    }
  },
}
