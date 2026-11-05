/** @typedef {import('./types').TokenPair} TokenPair */

/**
 * The access token lives in memory only. The refresh token is kept in
 * sessionStorage so a page reload keeps the session, and closing the tab
 * ends it. Each refresh token works once (rotation): always store the new one.
 */
const REFRESH_KEY = 'taranaka.refresh'

/** @type {string | null} */
let accessToken = null

/** @returns {Storage | null} */
function storage() {
  try {
    return window.sessionStorage
  } catch {
    return null
  }
}

export const tokenStorage = {
  /** @returns {string | null} */
  getAccess() {
    return accessToken
  },
  /** @returns {string | null} */
  getRefresh() {
    try {
      return storage()?.getItem(REFRESH_KEY) ?? null
    } catch {
      return null
    }
  },
  /** @param {TokenPair} tokens */
  save(tokens) {
    accessToken = tokens.access
    try {
      storage()?.setItem(REFRESH_KEY, tokens.refresh)
    } catch {
      // Private mode or storage disabled: the session ends with the page.
    }
  },
  clear() {
    accessToken = null
    try {
      storage()?.removeItem(REFRESH_KEY)
    } catch {
      // Nothing to clear.
    }
  },
}
