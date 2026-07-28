import type { DocPage } from './docs'

const cache = new Map<string, string>()

/** Props whose string values should be extracted for search. */
const TEXT_PROPS = ['children', 'code', 'codeRuntime', 'codeEditor', 'text', 'primary', 'secondary', 'label', 'title', 'placeholder', 'description']

/**
 * Walk a React element tree and collect every raw string value.
 * For function components that don't use hooks we call them to expand the tree;
 * if they throw (hooks / context) we still harvest their string props.
 */
function extractStrings(node: unknown, parts: string[], depth: number): void {
  if (node == null || typeof node === 'boolean') return
  if (typeof node === 'string') { parts.push(node); return }
  if (typeof node === 'number') { parts.push(String(node)); return }
  if (Array.isArray(node)) { for (const child of node) extractStrings(child, parts, depth); return }
  if (typeof node !== 'object') return

  const el = node as { type?: unknown; props?: Record<string, unknown> }
  if (!el.props) return

  // Try to expand function components (safe up to a depth limit)
  if (typeof el.type === 'function' && depth < 8) {
    try {
      const expanded = (el.type as (props: Record<string, unknown>) => unknown)(el.props)
      extractStrings(expanded, parts, depth + 1)
      return
    } catch { /* uses hooks or context – fall through to prop extraction */ }
  }

  // Harvest string-valued props
  for (const key of TEXT_PROPS) {
    const val = el.props[key]
    if (val != null) extractStrings(val, parts, depth)
  }
}

export function getRenderedText(page: DocPage): string {
  const cached = cache.get(page.id)
  if (cached !== undefined) return cached

  const parts: string[] = []
  try {
    extractStrings(page.element(), parts, 0)
  } catch { /* page element() itself threw */ }

  const text = parts.join(' ').toLowerCase()
  cache.set(page.id, text)
  return text
}
