/** RFC 4180 CSV, with a UTF-8 BOM so spreadsheet software reads accents. */

export type CsvCell = string | number | null | undefined

export function escapeCsvCell(cell: CsvCell): string {
  if (cell === null || cell === undefined) return ''
  let text = String(cell)
  // Neutralise formulas: a cell starting with = + - @ runs in spreadsheets.
  if (/^[=+\-@\t\r]/.test(text) && Number.isNaN(Number(text))) text = `'${text}`
  if (/[",\r\n]/.test(text)) return `"${text.replace(/"/g, '""')}"`
  return text
}

export function toCsv(rows: CsvCell[][]): string {
  return rows.map((row) => row.map(escapeCsvCell).join(',')).join('\r\n')
}

export function downloadCsv(filename: string, rows: CsvCell[][]): void {
  const blob = new Blob(['﻿', toCsv(rows)], { type: 'text/csv;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = filename
  document.body.append(link)
  link.click()
  link.remove()
  URL.revokeObjectURL(url)
}
