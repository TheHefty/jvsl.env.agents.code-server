(() => {
  const BUTTONS = 'jvsl-window-controls'

  function api() {
    // v2 exposes getCurrentWindow(); some builds still carry getCurrent().
    const w = window.__TAURI__ && window.__TAURI__.window
    if (!w) return null
    const current = w.getCurrentWindow || w.getCurrent
    return current ? current.call(w) : null
  }

  function button(label, title, onClick) {
    const b = document.createElement('button')
    b.type = 'button'
    b.textContent = label
    b.title = title
    b.setAttribute('aria-label', title)
    b.style.cssText =
      'all:unset;display:grid;place-items:center;width:46px;height:100%;' +
      'font:12px system-ui;cursor:default;color:inherit;'
    b.addEventListener('mouseenter', () => (b.style.background = 'rgba(127,127,127,.2)'))
    b.addEventListener('mouseleave', () => (b.style.background = 'transparent'))
    b.addEventListener('click', onClick)
    return b
  }

  function decorate(bar) {
    if (document.getElementById(BUTTONS)) return true
    const window_ = api()
    if (!window_) return false

    bar.setAttribute('data-tauri-drag-region', '')

    const controls = document.createElement('div')
    controls.id = BUTTONS
    controls.style.cssText =
      'position:absolute;top:0;right:0;height:100%;display:flex;z-index:2147483647;'
    controls.append(
      button('–', 'Minimise', () => window_.minimize()),
      button('☐', 'Maximise', () => window_.toggleMaximize()),
      button('✕', 'Close', () => window_.close()),
    )
    bar.append(controls)

    // Nothing of theirs may end up underneath ours. The width is the three
    // buttons; the padding is applied to the bar rather than to any child of
    // it, so it survives whatever they do inside.
    bar.style.paddingRight = '138px'
    return true
  }

  const found = () => document.querySelector('.part.titlebar')
  if (found() && decorate(found())) return

  // The workbench is a single-page app and this script runs before it. Watch,
  // but not for ever: a version that never draws that element should cost
  // nothing rather than an observer for the life of the window.
  const observer = new MutationObserver(() => {
    const bar = found()
    if (bar && decorate(bar)) observer.disconnect()
  })
  observer.observe(document.documentElement, { childList: true, subtree: true })
  setTimeout(() => observer.disconnect(), 30000)
})()
