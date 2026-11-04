/** Every failure of the API layer is turned into an ApiError. */

export type ApiErrorKind =
  | 'network'
  | 'unauthorized'
  | 'session_expired'
  | 'forbidden'
  | 'not_found'
  | 'conflict'
  | 'validation'
  | 'locked'
  | 'throttled'
  | 'server'

export type FieldErrors = Record<string, string[]>

export class ApiError extends Error {
  readonly kind: ApiErrorKind
  readonly status: number
  /** Machine-readable code sent by the backend, such as "compte_bloque". */
  readonly code: string | null
  readonly fieldErrors: FieldErrors
  readonly body: unknown

  constructor(options: {
    kind: ApiErrorKind
    status: number
    code?: string | null
    detail?: string
    fieldErrors?: FieldErrors
    body?: unknown
  }) {
    super(options.detail ?? options.kind)
    this.name = 'ApiError'
    this.kind = options.kind
    this.status = options.status
    this.code = options.code ?? null
    this.fieldErrors = options.fieldErrors ?? {}
    this.body = options.body
  }

  /** Text sent by the server, if any. The UI shows its own message first. */
  get detail(): string | null {
    return this.message === this.kind ? null : this.message
  }
}

export function isApiError(value: unknown): value is ApiError {
  return value instanceof ApiError
}

function kindFromStatus(status: number): ApiErrorKind {
  if (status === 400) return 'validation'
  if (status === 401) return 'unauthorized'
  if (status === 403) return 'forbidden'
  if (status === 404) return 'not_found'
  if (status === 409) return 'conflict'
  if (status === 423) return 'locked'
  if (status === 429) return 'throttled'
  return 'server'
}

/** Split a DRF error body into a detail, a code and the field errors. */
export function errorFromResponse(status: number, body: unknown): ApiError {
  let detail: string | undefined
  let code: string | null = null
  const fieldErrors: FieldErrors = {}

  if (body && typeof body === 'object' && !Array.isArray(body)) {
    for (const [key, value] of Object.entries(body as Record<string, unknown>)) {
      if (key === 'detail' && typeof value === 'string') detail = value
      else if (key === 'code' && typeof value === 'string') code = value
      else if (Array.isArray(value)) fieldErrors[key] = value.map(String)
      else if (typeof value === 'string' && key !== 'current') fieldErrors[key] = [value]
    }
  } else if (Array.isArray(body)) {
    fieldErrors.non_field_errors = body.map(String)
  }

  return new ApiError({
    kind: kindFromStatus(status),
    status,
    code,
    detail,
    fieldErrors,
    body,
  })
}
