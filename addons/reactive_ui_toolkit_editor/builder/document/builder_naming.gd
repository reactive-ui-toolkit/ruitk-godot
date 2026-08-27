@tool
class_name RuitkBuilderNaming
extends RefCounted
## The house naming convention: which modules belong to the same COMPONENT.
##
## A component and the style and hook modules named after it are one family --
## `showcase_page.guitkx`, `showcase_page.style.guitkx`, `showcase_page.hooks.guitkx` --
## and a family lives in one folder. This is what decides where a new module is BORN; it is
## not an invariant, and nothing re-places a module that has been put somewhere deliberately.
##
## GODOT NOTE. The family name is simply the file BASENAME, because this leg's convention
## puts it there for all three companions: the suffix carries the kind, so the name in front
## of it is already the family. The Unity leg has to fold case and strip a `use` prefix
## because its companions are named `newComponent.style` and `useNewComponent.hooks`. The
## `use_` strip is kept here anyway -- a hook file deliberately named `use_thing.hooks.guitkx`
## reads as the family `thing`, which is what a person means by it, and the strip is inert
## for every name that does not start that way.
##
## Util modules are deliberately outside the convention. They have no suffix -- a util is a
## plain `.guitkx` classified by what it declares -- so there is no name to match on, and a
## util named for its component would collide with the component's own file.
##
## Cross-file references inside the builder go through preload CONSTS, never the global
## `class_name`s these files also declare. A global name resolves through the editor
## class cache, and `ProjectSettings.save()` rewrites that cache from whatever the
## running process happens to have loaded -- so a headless run of one suite can
## truncate it and leave the whole document layer unable to load in the next. A
## preload is a compile-time edge that nothing can invalidate. The `class_name`s stay,
## for consumers and for typing.

const Paths = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_paths.gd")
const Module = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_module.gd")


## The family a module belongs to, in canonical form: lower-cased, with a leading `use_`
## stripped from a hook.
static func family_of(kind: Module.Kind, module_name: String) -> String:
	var bare := module_name
	if kind == Module.Kind.HOOK and bare.length() > 4 and bare.begins_with("use_"):
		# `use_` is only a prefix when a NAME follows it: a module called `use_` is its own
		# name, and stripping it would leave nothing to match on.
		bare = bare.substr(4)
	return bare.to_lower()


## Whether two module names name the same family. Compared case-insensitively:
## `ShowcasePage` and `showcase_page` differ in spelling, not in what a person means, and
## the filesystem does not distinguish the first from `showcasepage` either.
static func same_family(
	a_kind: Module.Kind, a_name: String,
	b_kind: Module.Kind, b_name: String) -> bool:
	var a := family_of(a_kind, a_name)
	var b := family_of(b_kind, b_name)
	return not a.is_empty() and a == b


## How closely two folders are related, as the number of leading path SEGMENTS they share.
## Used to pick the NEAREST component when more than one in the tree carries the family name.
##
## Segments, not characters: `res://ui/card` and `res://ui/cardigan` share `res://ui` and
## nothing more, while a character count would score the second as much the nearer of the
## two and hand a new module to the wrong component.
##
static func shared_prefix_length(a: String, b: String) -> int:
	var x := Paths.canon(a).to_lower()
	var y := Paths.canon(b).to_lower()
	if x.is_empty() or y.is_empty():
		return 0
	var xs := x.split("/")
	var ys := y.split("/")
	var n: int = mini(xs.size(), ys.size())
	var shared := 0
	while shared < n and xs[shared] == ys[shared]:
		shared += 1
	return shared
