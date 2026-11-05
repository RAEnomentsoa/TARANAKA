/** Every failure of the API layer is turned into an ApiError. */

/**
 * @typedef {(
 *   | 'network'
 *   | 'unauthorized'
 *   | 'session_expired'
 *   | 'forbidden'
 *   | 'not_found'
 *   | 'conflict'
 *   | 'validation'
 *   | 'locked'
 *   | 'throttled'
 *   | 'server'
 * )} ApiErrorKind
 */

/** @typedef {Record<string, string[]>} FieldErrors */

export class ApiError extends Error {
  /** @type {ApiErrorKind} */
  kind
  /** @type {number} */
  status
  /**
   * Machine-readable code sent by the backend, such as "compte_bloque".
   * @type {string | null}
   */
  code
  /** @type {FieldErrors} */
  fieldErrors
  /** @type {unknown} */
  body

  /**
   * @param {{ kind: ApiErrorKind, status: number, code?: string | null, detail?: string, fieldErrors?: FieldErrors, body?: unknown }} options
   */
  constructor(options) {
    super(options.detail ?? options.kind)
    this.name = 'ApiError'
    this.kind = options.kind
    this.status = options.status
    this.code = options.code ?? null
    this.fieldErrors = options.fieldErrors ?? {}
    this.body = options.body
  }

  /** Text sent by the server, if any. The UI shows its own message first. */
  get detail() {
    return this.message === this.kind ? null : this.message
  }
}

/**
 * @param {unknown} value
 * @returns {value is ApiError}
 */
export function isApiError(value) {
  return value instanceof ApiError
}

/**
 * @param {number} status
 * @returns {ApiErrorKind}
 */
function kindFromStatus(status) {
  if (status === 400) return 'validation'
  if (status === 401) return 'unauthorized'
  if (status === 403) return 'forbidden'
  if (status === 404) return 'not_found'
  if (status === 409) return 'conflict'
  if (status === 423) return 'locked'
  if (status === 429) return 'throttled'
  return 'server'
}

/**
 * Split a DRF error body into a detail, a code and the field errors.
 * @param {number} status
 * @param {unknown} body
 * @returns {ApiError}
 */
export function errorFromResponse(status, body) {
  /** @type {string | undefined} */
  let detail
  /** @type {string | null} */
  let code = null
  /** @type {FieldErrors} */
  const fieldErrors = {}

  if (body && typeof body === 'object' && !Array.isArray(body)) {
    for (const [key, value] of Object.entries(body)) {
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
