import { ApiError, errorFromResponse } from './errors'
import { deviceId } from './deviceId'
import { tokenStorage } from './tokenStorage'

/** @typedef {import('./types').Paginated} Paginated */
/** @typedef {import('./types').TokenPair} TokenPair */

/** @typedef {string | number | boolean | null | undefined} QueryValue */
/** @typedef {Record<string, QueryValue>} Query */

/**
 * @typedef {Object} RequestOptions
 * @property {'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE'} [method]
 * @property {Query} [query]
 * @property {unknown} [body]
 * @property {boolean} [auth] Send the access token (default true).
 * @property {AbortSignal} [signal]
 */

/** @typedef {() => void} SessionListener */

const REFRESH_PATH = '/api/auth/refresh/'

/**
 * Small fetch wrapper: base URL, JSON, bearer token, device id, language,
 * and one transparent token refresh on "token_not_valid" (see endpoint.md).
 */
export class HttpClient {
  /** @type {Promise<boolean> | null} */
  refreshing = null
  /** @type {SessionListener[]} */
  sessionExpiredListeners = []
  language = 'fr'

  /** @type {string} */
  baseUrl
  /** @type {typeof fetch} */
  fetchImpl

  /**
   * @param {string} baseUrl
   * @param {typeof fetch} [fetchImpl=(...args) => fetch(...args)]
   */
  constructor(baseUrl, fetchImpl = (...args) => fetch(...args)) {
    this.baseUrl = baseUrl
    this.fetchImpl = fetchImpl
  }

  /**
   * @param {SessionListener} listener
   * @returns {() => void}
   */
  onSessionExpired(listener) {
    this.sessionExpiredListeners.push(listener)
    return () => {
      this.sessionExpiredListeners = this.sessionExpiredListeners.filter((l) => l !== listener)
    }
  }

  /**
   * @param {string} path
   * @param {Query} [query]
   * @returns {string}
   */
  url(path, query) {
    const params = new URLSearchParams()
    for (const [key, value] of Object.entries(query ?? {})) {
      if (value !== undefined && value !== null && value !== '') params.set(key, String(value))
    }
    const search = params.toString()
    return `${this.baseUrl}${path}${search ? `?${search}` : ''}`
  }

  /**
   * @template T
   * @param {string} path
   * @param {RequestOptions} [options={}]
   * @returns {Promise<T>}
   */
  async request(path, options = {}) {
    const response = await this.send(path, options)
    if (response.status === 401 && options.auth !== false && (await this.isExpiredToken(response))) {
      if (await this.refreshTokens()) return this.parse(await this.send(path, options))
      this.expireSession()
      throw new ApiError({ kind: 'session_expired', status: 401, code: 'token_not_valid' })
    }
    return this.parse(response)
  }

  /**
   * @template T
   * @param {string} path
   * @param {Query} [query]
   * @param {Omit<RequestOptions, 'query'>} [options={}]
   * @returns {Promise<T>}
   */
  get(path, query, options = {}) {
    return this.request(path, { ...options, query })
  }

  /**
   * @template T
   * @param {string} path
   * @param {unknown} [body]
   * @param {Omit<RequestOptions, 'body' | 'method'>} [options={}]
   * @returns {Promise<T>}
   */
  post(path, body, options = {}) {
    return this.request(path, { ...options, method: 'POST', body })
  }

  /**
   * @template T
   * @param {string} path
   * @param {unknown} body
   * @returns {Promise<T>}
   */
  patch(path, body) {
    return this.request(path, { method: 'PATCH', body })
  }

  /**
   * A file answer (CSV export), with the same token handling as JSON calls.
   * "Accept: text/csv" gets a 406 from DRF's content negotiation on
   * /api/stats/export/ (docs/API_ISSUES.md), so any type is accepted.
   * @param {string} path
   * @param {Query} [query]
   * @returns {Promise<Blob>}
   */
  async blob(path, query) {
    let response = await this.send(path, { query, accept: '*/*' })
    if (response.status === 401 && (await this.isExpiredToken(response))) {
      if (!(await this.refreshTokens())) {
        this.expireSession()
        throw new ApiError({ kind: 'session_expired', status: 401, code: 'token_not_valid' })
      }
      response = await this.send(path, { query, accept: '*/*' })
    }
    if (!response.ok) throw errorFromResponse(response.status, await readBody(response))
    return response.blob()
  }

  /**
   * Read every page of a DRF list. The backend's "next" link is absolute and
   * points at the backend host, so the page number is followed instead.
   * @template T
   * @param {string} path
   * @param {Query} [query={}]
   * @param {Omit<RequestOptions, 'query'>} [options={}]
   * @returns {Promise<T[]>}
   */
  async getAll(path, query = {}, options = {}) {
    /** @type {T[]} */
    const items = []
    const maxPages = 200
    for (let page = 1; page <= maxPages; page += 1) {
      const data = await this.get(path, { ...query, page }, options)
      if (Array.isArray(data)) return data
      items.push(...data.results)
      if (!data.next) break
    }
    return items
  }

  /**
   * @param {string} path
   * @param {RequestOptions & { accept?: string }} options
   * @returns {Promise<Response>}
   */
  async send(path, options) {
    /** @type {Record<string, string>} */
    const headers = {
      Accept: options.accept ?? 'application/json',
      'Accept-Language': this.language,
      'X-Device-Id': deviceId(),
    }
    if (options.body !== undefined) headers['Content-Type'] = 'application/json'
    const access = tokenStorage.getAccess()
    if (options.auth !== false && access) headers.Authorization = `Bearer ${access}`

    try {
      return await this.fetchImpl(this.url(path, options.query), {
        method: options.method ?? 'GET',
        headers,
        body: options.body === undefined ? undefined : JSON.stringify(options.body),
        signal: options.signal,
      })
    } catch (error) {
      if (error instanceof DOMException && error.name === 'AbortError') throw error
      throw new ApiError({ kind: 'network', status: 0 })
    }
  }

  /**
   * @template T
   * @param {Response} response
   * @returns {Promise<T>}
   */
  async parse(response) {
    const body = await readBody(response)
    if (!response.ok) throw errorFromResponse(response.status, body)
    return body
  }

  /**
   * @param {Response} response
   * @returns {Promise<boolean>}
   */
  async isExpiredToken(response) {
    const body = await readBody(response.clone())
    const code = body && typeof body === 'object' ? body.code : undefined
    // No code: no token was accepted at all, a refresh may still help.
    return code === 'token_not_valid' || code === undefined
  }

  /**
   * Single flight: concurrent 401s share one refresh call.
   * @returns {Promise<boolean>}
   */
  refreshTokens() {
    if (!this.refreshing) {
      this.refreshing = this.doRefresh().finally(() => {
        this.refreshing = null
      })
    }
    return this.refreshing
  }

  /** @returns {Promise<boolean>} */
  async doRefresh() {
    const refresh = tokenStorage.getRefresh()
    if (!refresh) return false
    try {
      const tokens = await this.parse(await this.send(REFRESH_PATH, { method: 'POST', body: { refresh }, auth: false }))
      tokenStorage.save(tokens)
      return true
    } catch {
      return false
    }
  }

  expireSession() {
    tokenStorage.clear()
    for (const listener of this.sessionExpiredListeners) listener()
  }
}

/**
 * @param {Response} response
 * @returns {Promise<unknown>}
 */
async function readBody(response) {
  if (response.status === 204) return null
  const text = await response.text()
  if (!text) return null
  try {
    return JSON.parse(text)
  } catch {
    return text
  }
}

export const http = new HttpClient(import.meta.env.VITE_API_BASE_URL ?? '')
