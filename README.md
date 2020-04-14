# Stencil

A Jinja-style template engine written from scratch in Perl. Zero dependencies
outside the Perl core.

I wrote this to learn how template engines actually work: a lexer that splits
text from tags, a recursive-descent parser that builds an AST, an expression
parser with operator precedence and filters, and a renderer with scoped
variables, includes and template inheritance.

## Syntax

```jinja
{{ user.name | upper }}                {# expressions with filters #}
{{ items[0].price | round(2) }}        {# attribute and index access #}
{% if a > 1 and not b %}...{% elif c %}...{% else %}...{% endif %}
{% for item in items | sort("name") %}
  {{ loop.index }}. {{ item.name }}{% if not loop.last %},{% endif %}
{% else %}
  no items
{% endfor %}
{% for key, value in hash %}{{ key }}={{ value }}{% endfor %}
{% set total = price * qty %}
{% include "partial.html" %}
{% extends "layout.html" %}  {% block content %}...{% endblock %}
{% raw %}{{ not parsed }}{% endraw %}
{{- trims whitespace on the left -}}
```

Operators: `+ - * / %`, `== != < > <= >=`, `and or not`, `in`, `not in`,
parentheses, list literals `[1, 2]`, string/number/`true`/`false`/`none` literals.

Built-in filters: `upper lower capitalize title trim length join split reverse
sort first last default escape e safe replace truncate round abs keys values
sum min max json`. Add your own with `add_filter`.

## Usage

```perl
use Stencil;

my $t = Stencil->new(path => 'templates', autoescape => 1);
print $t->render_string('Hello {{ name | upper }}!', { name => 'world' });
print $t->render_file('page.html', { products => \@products });

$t->add_filter(money => sub { sprintf '$%.2f', shift });
```

Command line:

```sh
perl bin/stencil -p examples -e page.html examples/vars.json
```

## Tests

```sh
prove -l t
```

## How it works

1. **Lexer** (`_tokenize`): one regex pass over the source producing `text`,
   `var` and `block` tokens, then applies `-` whitespace control.
2. **Parser** (`_parse_nodes`, `_parse_block`): consumes tokens recursively,
   returning nested AST nodes for `if`/`for`/`set`/`include`/`block`.
3. **Expression parser** (`_p_*`): precedence climbing from `|` filters down
   to atoms, so `a + b * c | upper` parses the way you expect.
4. **Renderer** (`_render_nodes`, `_eval`): walks the AST with a stack of
   variable scopes, resolves the `extends` chain so child blocks override
   parent blocks, and escapes output when `autoescape` is on. Parsed
   templates are cached per engine instance.

## License

MIT
