// The injected title bar, exercised against a DOM built here by hand.
//
// It is the one piece of this launcher that runs inside somebody else's page,
// and it is written to fail quietly — if code-server stops calling its title
// bar `.part.titlebar`, nothing is injected and nothing complains. That is the
// right behaviour and it is also why these exist: a silent failure is invisible
// until somebody opens the window and wonders where the buttons went.
//
// What is asserted is what a machine can see: that the script finds the bar,
// injects once, reserves room, and does nothing at all when the API it needs is
// absent. Whether the result looks right, drags, and closes the window is the
// half only a person in front of it can check.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const here = dirname(fileURLToPath(import.meta.url))
const script = readFileSync(join(here, 'title_bar.js'), 'utf8')

function fakeDom({ withBar = true, withApi = true } = {}) {
  const made = []
  const element = (tag) => ({
    tag,
    id: '',
    type: '',
    textContent: '',
    title: '',
    style: { cssText: '', paddingRight: '', background: '' },
    children: [],
    attributes: {},
    listeners: {},
    setAttribute(key, value) {
      this.attributes[key] = value
    },
    addEventListener(event, handler) {
      this.listeners[event] = handler
    },
    append(...kids) {
      this.children.push(...kids)
    },
  })

  const bar = element('div')
  const calls = { minimize: 0, toggleMaximize: 0, close: 0 }
  const document = {
    documentElement: element('html'),
    getElementById: (id) => made.find((one) => one.id === id) ?? null,
    querySelector: (selector) =>
      withBar && selector === '.part.titlebar' ? bar : null,
    createElement: (tag) => {
      const made_ = element(tag)
      made.push(made_)
      return made_
    },
  }

  const window = {
    document,
    MutationObserver: class {
      observe() {}
      disconnect() {}
    },
    setTimeout: () => {},
    __TAURI__: withApi
      ? {
          window: {
            getCurrentWindow: () => ({
              minimize: () => calls.minimize++,
              toggleMaximize: () => calls.toggleMaximize++,
              close: () => calls.close++,
            }),
          },
        }
      : undefined,
  }

  return { window, document, bar, calls }
}

function run(context) {
  const inWindow = new Function(
    'window',
    'document',
    'MutationObserver',
    'setTimeout',
    script,
  )
  inWindow(
    context.window,
    context.document,
    context.window.MutationObserver,
    context.window.setTimeout,
  )
}

test('the bar itself becomes the drag region, and only the bar', () => {
  const context = fakeDom()
  run(context)

  assert.equal(context.bar.attributes['data-tauri-drag-region'], '')
  // Not on the controls: a mousedown there is a click on a button, and Tauri
  // starts a drag from whichever element received it.
  const controls = context.bar.children[0]
  assert.equal(controls.attributes['data-tauri-drag-region'], undefined)
})

test('three buttons, and room reserved for them', () => {
  const context = fakeDom()
  run(context)

  const controls = context.bar.children[0]
  assert.equal(controls.children.length, 3)
  assert.deepEqual(
    controls.children.map((one) => one.title),
    ['Minimise', 'Maximise', 'Close'],
  )
  assert.equal(context.bar.style.paddingRight, '138px')
})

test('each button does the one thing it says', () => {
  const context = fakeDom()
  run(context)

  const [minimise, maximise, close] = context.bar.children[0].children
  minimise.listeners.click()
  maximise.listeners.click()
  close.listeners.click()

  assert.deepEqual(context.calls, { minimize: 1, toggleMaximize: 1, close: 1 })
})

test('injected once, however many times it runs', () => {
  const context = fakeDom()
  run(context)
  run(context)

  assert.equal(context.bar.children.length, 1)
})

test('without the window API it injects nothing at all', () => {
  const context = fakeDom({ withApi: false })
  run(context)

  // A page that is not ours, or a capability that does not reach it. Half a
  // title bar — draggable, with buttons that do nothing — is worse than none.
  assert.equal(context.bar.children.length, 0)
  assert.equal(context.bar.attributes['data-tauri-drag-region'], undefined)
})

test('without their title bar it waits instead of throwing', () => {
  const context = fakeDom({ withBar: false })

  assert.doesNotThrow(() => run(context))
})
