import { describe, expect, it, vi } from 'vitest'
import { ApiError } from '@/api/errors'
import { HttpClient } from '@/api/http'
import { tokenStorage } from '@/api/tokenStorage'
import { jsonResponse } from '../helpers'

const expired = { detail: 'Session invalide ou expirée.', code: 'token_not_valid' }

/** @param {Array<(url: string, init: RequestInit) => Response>} responses */
function client(responses) {
  /** @type {Array<{ url: string, init: RequestInit }>} */
  const calls = []
  const fetchMock = vi.fn(async (url, init) => {
    calls.push({ url: String(url), init: init ?? {} })
    const next = responses.shift()
    if (!next) throw new Error(`unexpected call ${String(url)}`)
    return next(String(url), init ?? {})
  })
  return { http: new HttpClient('http://api.test', fetchMock), calls }
}

describe('HttpClient', () => {
  it('sends the bearer token, the device id and the language', async () => {
    tokenStorage.save({ access: 'A1', refresh: 'R1' })
    const { http, calls } = client([() => jsonResponse(200, { ok: true })])
    http.language = 'mg'

    await http.get('/api/auth/me/', { status: 'envoye', empty: '' })

    const headers = calls[0].init.headers
    expect(calls[0].url).toBe('http://api.test/api/auth/me/?status=envoye')
    expect(headers.Authorization).toBe('Bearer A1')
    expect(headers['Accept-Language']).toBe('mg')
    expect(headers['X-Device-Id']).toMatch(/^web-/)
  })

  it('refreshes once on token_not_valid, stores the rotated tokens and retries', async () => {
    tokenStorage.save({ access: 'old', refresh: 'R1' })
    const { http, calls } = client([
      () => jsonResponse(401, expired),
      (_url, init) => {
        expect(JSON.parse(String(init.body))).toEqual({ refresh: 'R1' })
        return jsonResponse(200, { access: 'new', refresh: 'R2' })
      },
      () => jsonResponse(200, { id: 1 }),
    ])

    await expect(http.get('/api/referrals/')).resolves.toEqual({ id: 1 })
    expect(calls.map((c) => c.url)).toEqual([
      'http://api.test/api/referrals/',
      'http://api.test/api/auth/refresh/',
      'http://api.test/api/referrals/',
    ])
    expect(calls[2].init.headers.Authorization).toBe('Bearer new')
    expect(tokenStorage.getRefresh()).toBe('R2')
  })

  it('shares one refresh between concurrent requests', async () => {
    tokenStorage.save({ access: 'old', refresh: 'R1' })
    let refreshes = 0
    const fetchMock = vi.fn(async (url, init) => {
      if (String(url).endsWith('/refresh/')) {
        refreshes += 1
        return jsonResponse(200, { access: 'new', refresh: 'R2' })
      }
      const auth = init?.headers?.Authorization
      return auth === 'Bearer new' ? jsonResponse(200, {}) : jsonResponse(401, expired)
    })
    const http = new HttpClient('', fetchMock)

    await Promise.all([http.get('/a/'), http.get('/b/'), http.get('/c/')])

    expect(refreshes).toBe(1)
  })

  it('expires the session when the refresh is refused', async () => {
    tokenStorage.save({ access: 'old', refresh: 'R1' })
    const { http } = client([() => jsonResponse(401, expired), () => jsonResponse(401, expired)])
    const listener = vi.fn()
    http.onSessionExpired(listener)

    await expect(http.get('/api/referrals/')).rejects.toMatchObject({ kind: 'session_expired' })
    expect(listener).toHaveBeenCalledOnce()
    expect(tokenStorage.getRefresh()).toBeNull()
  })

  it('does not try to refresh on a login failure', async () => {
    const { http, calls } = client([
      () => jsonResponse(401, { detail: 'Identifiant ou PIN incorrect', code: 'identifiants_incorrects' }),
    ])

    const error = await http.post('/api/auth/login/', {}, { auth: false }).catch((e) => e)

    expect(error).toBeInstanceOf(ApiError)
    expect(error).toMatchObject({ kind: 'unauthorized', code: 'identifiants_incorrects' })
    expect(calls).toHaveLength(1)
  })

  it('downloads a file with the token, refreshing it when needed', async () => {
    tokenStorage.save({ access: 'old', refresh: 'R1' })
    const { http, calls } = client([
      () => jsonResponse(401, expired),
      () => jsonResponse(200, { access: 'new', refresh: 'R2' }),
      () =>
        new Response('groupe,indicateur,valeur\r\nTotal,cas_mas,<5', {
          status: 200,
          headers: { 'Content-Type': 'text/csv' },
        }),
    ])

    const blob = await http.blob('/api/stats/export/', { region: 1 })

    expect(await blob.text()).toContain('cas_mas,<5')
    expect(calls[2].init.headers.Accept).toBe('text/csv')
    expect(calls[2].url).toBe('http://api.test/api/stats/export/?region=1')
  })

  it('reports a 404 as not found', async () => {
    const { http } = client([() => jsonResponse(404, { detail: 'Not found.' })])
    await expect(http.get('/api/referrals/x/')).rejects.toMatchObject({ kind: 'not_found' })
  })

  it('keeps field errors and the conflict body', async () => {
    const { http } = client([
      () => jsonResponse(400, { status: ['Le statut ne peut pas revenir en arrière.'] }),
      () => jsonResponse(409, { detail: 'Modifiée', code: 'conflit_version', current: { version: 4 } }),
    ])
    await expect(http.post('/x/')).rejects.toMatchObject({
      kind: 'validation',
      fieldErrors: { status: ['Le statut ne peut pas revenir en arrière.'] },
    })
    await expect(http.post('/x/')).rejects.toMatchObject({ kind: 'conflict', body: { current: { version: 4 } } })
  })

  it('turns a network failure into a network error', async () => {
    const http = new HttpClient('', async () => {
      throw new TypeError('Failed to fetch')
    })
    await expect(http.get('/x/')).rejects.toMatchObject({ kind: 'network' })
  })

  it('reads every page of a paginated list by page number', async () => {
    const { http, calls } = client([
      () => jsonResponse(200, { count: 3, next: 'http://backend:8000/api/x/?page=2', previous: null, results: [1, 2] }),
      () => jsonResponse(200, { count: 3, next: null, previous: 'x', results: [3] }),
    ])
    await expect(http.getAll('/api/x/', { status: 'clos' })).resolves.toEqual([1, 2, 3])
    expect(calls[1].url).toBe('http://api.test/api/x/?status=clos&page=2')
  })
})
