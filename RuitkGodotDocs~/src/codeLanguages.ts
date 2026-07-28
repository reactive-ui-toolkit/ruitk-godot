import { Prism } from 'prism-react-renderer'

// prism-react-renderer ships a fixed, curated set of Prism grammars (markup, jsx, tsx, json,
// python, yaml, css, go, rust, …) but NOT gdscript. Every `language="gdscript"` code block was
// therefore rendered as a single un-tokenized run — no keyword/string/comment colour at all,
// which is what looked "broken" on pages like Styling. We register a GDScript grammar on the
// SAME Prism instance that <Highlight> uses (prism-react-renderer re-exports it) so those blocks
// highlight identically to the bundled languages.
//
// Modelled on the official PrismJS `gdscript` component, extended for Godot 4 realities the
// original never covered: annotations (@export, @onready, @tool …), get-node shorthands
// ($Node / %Unique), StringName / NodePath literals (@"…"), and PascalCase type colouring.

if (!Prism.languages.gdscript) {
  Prism.languages.gdscript = {
    comment: /#.*/,
    string: {
      // Single/double/triple-quoted, with escapes; optional leading @ for StringName / NodePath.
      pattern:
        /@?(?:("|')(?:\\[\s\S]|(?!\1)[^\\\r\n])*\1(?!"|')|"""(?:[^\\]|\\[\s\S])*?""")/,
      greedy: true,
    },
    annotation: {
      // @export, @export_range, @onready, @tool, @icon, @rpc, @warning_ignore, …
      pattern: /@[A-Za-z_]\w*/,
      alias: 'keyword',
    },
    'class-name': [
      {
        // Type positions: `class X`, `extends X`, `as X`, `var x: X`, `(x: X)`, `-> X`.
        pattern:
          /(^[ \t]*(?:class|class_name|extends)[ \t]+|\bas[ \t]+|(?:\b(?:const|var)[ \t]|[,(])[ \t]*\w+[ \t]*:[ \t]*|->[ \t]*)[A-Za-z_]\w*/m,
        lookbehind: true,
      },
      // PascalCase used as a constructor call or namespace: Vector2(…), Color.RED, Input.is_…()
      /\b[A-Z]\w*(?=\s*[.(])/,
    ],
    keyword:
      /\b(?:and|as|assert|await|break|breakpoint|class_name|class|const|continue|elif|else|enum|extends|for|func|if|in|is|match|not|onready|or|pass|preload|remote|return|self|setget|signal|static|super|tool|var|void|while|yield)\b/,
    builtin:
      /\b(?:print|prints|printt|printerr|printraw|print_debug|push_error|push_warning|str|len|range|load|typeof|is_instance_valid|weakref|min|max|clamp|clampf|abs|absf|floor|ceil|round|snapped|sign|lerp|lerpf|move_toward|deg_to_rad|rad_to_deg|randi|randf|randf_range|randi_range|randomize|get_node|get_tree|get_parent|emit_signal|connect|call_deferred|queue_free|add_child|instantiate|has_method|has_node)\b/,
    function: /\b[a-z_]\w*(?=[ \t]*\()/i,
    variable: /\$\w+|%[A-Za-z_]\w*/,
    number: [
      /\b0b[01_]+\b|\b0x[\da-fA-F_]+\b|(?:\b\d[\d_]*(?:\.[\d_]*)?|\B\.[\d_]+)(?:e[+-]?[\d_]+)?\b/i,
      /\b(?:INF|NAN|PI|TAU)\b/,
    ],
    boolean: /\b(?:false|true)\b/,
    constant: /\b[A-Z][A-Z_\d]*\b/,
    operator:
      /:=|->|\*\*=?|<<=?|>>=?|&&|\|\||[-+*/%&|!<>=]=?|[~^]|\b(?:and|in|is|not|or)\b/,
    punctuation: /[.:,;()[\]{}]/,
  }
}

export { Prism }
