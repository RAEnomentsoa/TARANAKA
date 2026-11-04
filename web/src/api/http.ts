import { ApiError, errorFromResponse } from './errors'
import { deviceId } from './deviceId'
import { tokenStorage } from './tokenStorage'
import type { Paginated, TokenPair } from './types'

export type QueryValue = string | number | boolean | null | undefined
export type Query = Record<string, QueryValue>

export interface RequestOptions {
  method?: 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE'
  query?: Query
  body?: unknown
  /** Send the access token (default true). */
  auth?: boolean
  /** The endpoint is proposed in docs/API_ISSUES.md and may not exist yet. */
  proposed?: boolean
  signal?: AbortSignal
}

type SessionListener = () => void

const REFRESH_PATH = '/api/auth/refresh/'

/**
 * Small fetch wrapper: base URL, JSON, bearer token, device id, language,
 * and one transparent token refresh on "token_not_valid" (see endpoint.md).
 */
export class HttpClient {
  private refreshing: Promise<boolean> | null = null
  private sessionExpiredListeners: SessionListener[] = []
  language = 'fr'

  constructor(
    private readonly baseUrl: string,
    private readonly fetchImpl: typeof fetch = (...args) => fetch(...args),
  ) {}

  onSessionExpired(listener: SessionListener): () => void {
    this.sessionExpiredListeners.push(listener)
    return () => {
      this.sessionExpiredListeners = this.sessionExpiredListeners.filter((l) => l !== listener)
    }
  }

  url(path: string, query?: Query): string {
    const params = new URLSearchParams()
    for (const [key, value] of Object.entries(query ?? {})) {
      if (value !== undefined && value !== null && value !== '') params.set(key, String(value))
    }
    const search = params.toString()
    return `${this.baseUrl}${path}${search ? `?${search}` : ''}`
  }

  async request<T>(path: string, options: RequestOptions = {}): Promise<T> {
    const response = await this.send(path, options)
    if (response.status === 401 && options.auth !== false && (await this.isExpiredToken(response))) {
      if (await this.refreshTokens()) return this.parse<T>(await this.send(path, options), options)
      this.expireSession()
      throw new ApiError({ kind: 'session_expired', status: 401, code: 'token_not_valid' })
    }
    return this.parse<T>(response, options)
  }

  get<T>(path: string, query?: Query, options: Omit<RequestOptions, 'query'> = {}): Promise<T> {
    return this.request<T>(path, { ...options, query })
  }

  post<T>(path: string, body?: unknown, options: Omit<RequestOptions, 'body' | 'method'> = {}): Promise<T> {
    return this.request<T>(path, { ...options, method: 'POST', body })
  }

  /**
   * Read every page of a DRF list. The backend's "next" link is absolute and
   * points at the backend host, so the page number is followed instead.
   */
  async getAll<T>(path: string, query: Query = {}, options: Omit<RequestOptions, 'query'> = {}): Promise<T[]> {
    const items: T[] = []
    const maxPages = 200
    for (let page = 1; page <= maxPages; page += 1) {
      const data = await this.get<Paginated<T> | T[]>(path, { ...query, page }, options)
      if (Array.isArray(data)) return data
      items.push(...data.results)
      if (!data.next) break
    }
    return items
  }

  private async send(path: string, options: RequestOptions): Promise<Response> {
    const headers: Record<string, string> = {
      Accept: 'application/json',
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

  private async parse<T>(response: Response, options: RequestOptions): Promise<T> {
    const body = await readBody(response)
    if (!response.ok) throw errorFromResponse(response.status, body, options.proposed)
    return body as T
  }

  private async isExpiredToken(response: Response): Promise<boolean> {
    const body = await readBody(response.clone())
    const code = body && typeof body === 'object' ? (body as { code?: unknown }).code : undefined
    // No code: no token was accepted at all, a refresh may still help.
    return code === 'token_not_valid' || code === undefined
  }

  /** Single flight: concurrent 401s share one refresh call. */
  refreshTokens(): Promise<boolean> {
    if (!this.refreshing) {
      this.refreshing = this.doRefresh().finally(() => {
        this.refreshing = null
      })
    }
    return this.refreshing
  }

  private async doRefresh(): Promise<boolean> {
    const refresh = tokenStorage.getRefresh()
    if (!refresh) return false
    try {
      const tokens = await this.parse<TokenPair>(
        await this.send(REFRESH_PATH, { method: 'POST', body: { refresh }, auth: false }),
        {},
      )
      tokenStorage.save(tokens)
      return true
    } catch {
      return false
    }
  }

  private expireSession(): void {
    tokenStorage.clear()
    for (const listener of this.sessionExpiredListeners) listener()
  }
}

async function readBody(response: Response): Promise<unknown> {
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
