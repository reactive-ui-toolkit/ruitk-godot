import type { ReactElement } from 'react'
import { HOST_TAGS } from './hostElements'
import { HOST_CONTENT } from './hostContent'
import { ComponentPage } from './pages/Components/ComponentPage'

export type Page = {
  id: string
  title: string
  path: string
  keywords?: string[]
  searchContent?: string
  group?: 'basic' | 'advanced'
  sinceGodot?: string
  element: () => ReactElement
}

export type Section = {
  id: string
  title: string
  pages: Page[]
}

/** PascalCase / camelCase host tag → kebab-case route segment (e.g. HSlider → h-slider). */
const toKebab = (tag: string): string =>
  tag
    .replace(/([a-z0-9])([A-Z])/g, '$1-$2')
    .replace(/([A-Z]+)([A-Z][a-z])/g, '$1-$2')
    .toLowerCase()

// One page per host tag, in HOST_TAGS (nav) order. The catalog is fully
// data-driven: metadata comes from hostContent and each page renders the
// generic ComponentPage for its tag.
const componentPages: Page[] = HOST_TAGS.map((tag) => {
  const content = HOST_CONTENT[tag]
  const kebab = toKebab(tag)
  return {
    id: `component-${kebab}`,
    title: tag,
    path: `/components/${kebab}`,
    keywords: content?.keywords ?? [tag.toLowerCase()],
    group: content?.group ?? 'advanced',
    element: () => <ComponentPage tag={tag} />,
  }
})

export const pages: Section[] = [
  {
    id: 'components',
    title: 'Components',
    pages: componentPages,
  },
]

export const flat: Page[] = pages.flatMap((s) => {
  if (s.id === 'components') {
    const common = s.pages.filter((p) => p.group === 'basic')
    const uncommon = s.pages.filter((p) => p.group === 'advanced' || !p.group)
    return [...common, ...uncommon]
  }
  return s.pages
})
