export const CONTEXT_HANDLE_API = `# Create a context handle (React parity for createContext). Declare it once —
# a top-level value or a script static — and share the SAME handle between
# provider and consumers.
Hooks.createContext(default_value = null, name = "") -> RuitkContext

# Provide a value for all descendants (call inside a component's setup body).
Hooks.provideContext(handle_or_key, value) -> void

# Consume the nearest provided value above; returns the handle's default when
# no ancestor provides it. (String keys return null when unprovided.)
Hooks.useContext(handle_or_key)   # auto-prefixed to Hooks.useContext in .guitkx`

export const CONTEXT_HANDLE_EXAMPLE = `# app_contexts.gd — declare the handle ONCE, as a script static, so every file
# references the same object. Its identity is the map key, so it can never
# collide with an unrelated feature that happens to also use "theme".
class_name AppContexts
extends RefCounted

# The argument is the DEFAULT returned by useContext(Theme) when unprovided.
static var Theme: RuitkContext = Hooks.createContext({ "accent": Color.CYAN }, "Theme")

# ── Provider ────────────────────────────────────────────────
AppRoot(my_theme: Dictionary) -> RuitkVNode {
  # Pass the HANDLE (not a string) plus the value.
  Hooks.provideContext(AppContexts.Theme, my_theme)

  return (
    <VBoxContainer>
      <Toolbar />
    </VBoxContainer>
  )
}

# ── Consumer ────────────────────────────────────────────────
Toolbar() -> RuitkVNode {
  # Pass the same handle. Returns my_theme, or the handle's default if no
  # AppRoot provided one above this component.
  var theme = Hooks.useContext(AppContexts.Theme)

  return (
    <PanelContainer style={ {"bg_color": theme["accent"]} }>
      <Label text="Toolbar" />
    </PanelContainer>
  )
}`

export const CONTEXT_HANDLE_MODULE_EXAMPLE = `# Idiomatic single-file form: the handle is a top-level value in the same file
# as the component that owns it, created with an inline default value.
# @class_name keeps the file's binding "ThemePanel" so the dotted references
# below stay stable no matter which declaration comes first.
@class_name ThemePanel

Theme := Hooks.createContext({ "accent": Color.CYAN }, "Theme")

ThemePanel(accent: Color = Color.MAGENTA) -> RuitkVNode {
  # Provide overrides the default for this subtree.
  Hooks.provideContext(ThemePanel.Theme, { "accent": accent })

  return (
    <VBoxContainer>
      <AccentDot />
    </VBoxContainer>
  )
}

AccentDot() -> RuitkVNode {
  # If no ThemePanel provided a value above, this returns { "accent": Color.CYAN }
  # — the handle's default — rather than null.
  var theme = Hooks.useContext(ThemePanel.Theme)

  return (
    <PanelContainer style={ {"bg_color": theme["accent"], "custom_minimum_size": Vector2(16, 16)} } />
  )
}`

export const CONTEXT_BASIC_EXAMPLE = `# Provider — makes a value available to all descendants
AppRoot() -> RuitkVNode {
  Hooks.provideContext("user_name", "Alice")
  Hooks.provideContext("theme", "dark")

  return (
    <VBoxContainer>
      <Sidebar />
      <MainContent />
    </VBoxContainer>
  )
}

# Consumer — reads the value anywhere in the subtree
Sidebar() -> RuitkVNode {
  var user_name = useContext("user_name")
  var theme = useContext("theme")

  return (
    <PanelContainer style={ {"bg_color": Color("#1e1e1e") if theme == "dark" else Color.WHITE} }>
      <Label text={ "Logged in as %s" % user_name } />
    </PanelContainer>
  )
}`

export const CONTEXT_SHADOWING_EXAMPLE = `OuterProvider() -> RuitkVNode {
  Hooks.provideContext("theme", "light")

  return (
    <VBoxContainer>
      <Label text={ useContext("theme") } />   # "light"
      <InnerProvider />
    </VBoxContainer>
  )
}

InnerProvider() -> RuitkVNode {
  Hooks.provideContext("theme", "dark")   # shadows outer

  return (
    <VBoxContainer>
      <Label text={ useContext("theme") } />   # "dark"
    </VBoxContainer>
  )
}`

export const CONTEXT_DYNAMIC_EXAMPLE = `ThemeToggle() -> RuitkVNode {
  var dark = useState(true)
  Hooks.provideContext("theme", "dark" if dark[0] else "light")

  return (
    <VBoxContainer>
      <CheckButton text="Dark mode" button_pressed={ dark[0] }
                   onToggled={ func(pressed): dark[1].call(pressed) } />
      <ThemedPanel />
    </VBoxContainer>
  )
}

ThemedPanel() -> RuitkVNode {
  var theme = useContext("theme")
  # Automatically re-renders when the provided value changes

  return (
    <PanelContainer style={ {
      "bg_color": Color("#1e1e1e") if theme == "dark" else Color.WHITE,
      "content_margin_all": 16,
    } }>
      <Label text={ "Current theme: %s" % theme } />
    </PanelContainer>
  )
}`

export const CONTEXT_VS_SIGNALS = `# Use context when:
# - Data is scoped to a subtree (e.g., theme for a panel)
# - Different parts of the tree need different values
# - Provider/consumer relationship is 1-to-many within a branch

# Use signals (RuitkSignal / useSignalKey) when:
# - Data is truly global (e.g., user session, app-wide settings)
# - Multiple independent trees need the same value
# - You want process-wide reactivity without a component hierarchy`

export const CONTEXT_TYPED_EXAMPLE = `# Predefined context keys, kept in a small shared .gd script. (Since 0.11 they
# could equally be .guitkx value exports — \`export THEME := "app.theme"\` — but a
# hand-written class_name script is ambient: no import line needed anywhere.)
class_name AppContextKeys
extends RefCounted

const THEME := "app.theme"
const LOCALE := "app.locale"
const AUTH := "app.auth"

# Provider
AppShell(current_theme, auth_state) -> RuitkVNode {
  Hooks.provideContext(AppContextKeys.THEME, current_theme)
  Hooks.provideContext(AppContextKeys.LOCALE, "en-US")
  Hooks.provideContext(AppContextKeys.AUTH, auth_state)
  # ...
}

# Consumer
LocalizedLabel() -> RuitkVNode {
  var locale = useContext(AppContextKeys.LOCALE)
  # ...
}`
