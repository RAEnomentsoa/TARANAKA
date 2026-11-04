import { readFileSync, readdirSync, statSync } from 'node:fs'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'
import fr from '@/i18n/locales/fr.json'
import mg from '@/i18n/locales/mg.json'

/** @typedef {{ [key: string]: string | Tree }} Tree */

/**
 * @param {Tree} tree
 * @param {*} [prefix='']
 * @returns {Record<string, string>}
 */
function flatten(tree, prefix = '') {
  return Object.entries(tree).reduce((acc, [key, value]) => {
    const path = prefix ? `${prefix}.${key}` : key
    if (typeof value === 'string') acc[path] = value
    else Object.assign(acc, flatten(value, path))
    return acc
  }, {})
}

const frKeys = flatten(fr)
const mgKeys = flatten(mg)
/** @param {string} text */
const placeholders = (text) => [...text.matchAll(/\{(\w+)\}/g)].map((m) => m[1]).sort()

/**
 * @param {string} dir
 * @returns {string[]}
 */
function sourceFiles(dir) {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name)
    return statSync(path).isDirectory() ? sourceFiles(path) : /\.(vue|js)$/.test(name) ? [path] : []
  })
}

describe('translations', () => {
  it('French and Malagasy have exactly the same keys', () => {
    expect(Object.keys(mgKeys).sort()).toEqual(Object.keys(frKeys).sort())
  })

  it('has no empty message', () => {
    for (const [key, value] of [...Object.entries(frKeys), ...Object.entries(mgKeys)]) {
      expect(value.trim(), key).not.toBe('')
    }
  })

  it('uses the same placeholders in both languages', () => {
    for (const key of Object.keys(frKeys)) {
      expect(placeholders(mgKeys[key] ?? ''), key).toEqual(placeholders(frKeys[key] ?? ''))
    }
  })

  it('has the same number of plural forms in both languages', () => {
    for (const key of Object.keys(frKeys)) {
      expect((mgKeys[key] ?? '').split(' | ').length, key).toBe((frKeys[key] ?? '').split(' | ').length)
    }
  })

  it('every static t("...") key used in the code exists', () => {
    const src = join(__dirname, '../../src')
    /** @type {string[]} */
    const missing = []
    for (const file of sourceFiles(src)) {
      const text = readFileSync(file, 'utf8')
      for (const match of text.matchAll(/\bt\(\s*'([a-zA-Z0-9_.]+)'/g)) {
        const key = match[1]
        if (!(key in frKeys)) missing.push(`${file}: ${key}`)
      }
    }
    expect(missing).toEqual([])
  })
})
