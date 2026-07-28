export const UITKX_ROUTER_EXAMPLE = `RouterDemo() -> RuitkVNode {
  var navigate = RuitkRouter.useNavigate()
  var search = RuitkRouter.useSearchParams()   // [query, setter]

  var ACTIVE := { "font_color": Color(1.0, 0.85, 0.3) }
  var IDLE := { "font_color": Color(0.7, 0.7, 0.8) }

  // Router, NavLink, Routes, Route, and Outlet have no markup tags — the whole
  // router tree below is built with V.* calls, then mounted with one embedded { expr }.
  var app = V.router({ "basename": "/app" }, [
    V.VBoxContainer({ "style": { "separation": 8 } }, [
      // nav_link applies active_style when its target matches the location.
      V.nav_link({ "to": "/", "end": true, "label": "Home", "style": IDLE, "active_style": ACTIVE }),
      V.nav_link({ "to": "/about", "label": "About", "style": IDLE, "active_style": ACTIVE }),
      V.nav_link({ "to": "/users", "label": "Users", "style": IDLE, "active_style": ACTIVE }),

      V.Button({ "text": "Open profile 42",
                 "onPressed": func(): navigate.call("/users/42?tab=profile") }),

      // routes picks the single best match using RR's ranking algorithm.
      V.routes({}, [
        // Index route — matches the parent path exactly.
        V.route({ "index": true, "element": V.Label({ "text": "Landing route" }) }),

        V.route({ "path": "/about", "element": V.Label({ "text": "About route" }) }),

        // Layout route — element wraps the matched child via V.outlet(...).
        V.route({ "path": "/users", "element": V.fc(UsersLayout.render) }, [
            V.route({ "index": true, "element": V.Label({ "text": "Pick a user" }) }),
            V.route({ "path": ":id", "element": V.fc(UserDetails.render) }),
        ]),

        // Declarative redirect (replace = true by default).
        V.route({ "path": "/old", "element": V.navigate({ "to": "/about" }) }),

        V.route({ "path": "*", "element": V.Label({ "text": "Not found" }) }),
      ]),
    ]),
  ])

  return (
    <VBoxContainer>
      { app }
    </VBoxContainer>
  )
}`

export const UITKX_ROUTER_LAYOUT_EXAMPLE = `UsersLayout() -> RuitkVNode {
  return (
    <VBoxContainer style={ {"separation": 8} }>
      <Label text="Users header" />
      // Nested route content renders here — Outlet has no markup tag either.
      { V.outlet() }
    </VBoxContainer>
  )
}`

export const UITKX_ROUTER_DETAILS_EXAMPLE = `UserDetails() -> RuitkVNode {
  var params = RuitkRouter.useParams()       // { "id": "42", ... }
  var matches = RuitkRouter.useMatches()     // breadcrumb chain (root -> current)
  return (
    <Label text={ "User id: %s" % str(params.get("id")) } />
  )
}`
