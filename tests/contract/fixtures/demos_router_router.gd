class_name DemoRouter
extends RefCounted
## AUTO-GENERATED from demos_router_router.guitkx -- do not edit.

const __RUI_HOOK_SIG := ""

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	return (V.router({ "initial": "/" }, [V.fc(DemoRouterInner.render)]))
