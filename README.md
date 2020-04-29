# Stencil

> 🇺🇸 [English version below](#english)

Um motor de templates estilo Jinja, em Perl. Sim, Perl. Eu quis aprender a linguagem que segurou a web nos anos 90 e não achei projeto melhor do que um template engine: tem lexer, parser recursivo, precedência de operadores, escopo de variáveis, herança de template... é um mini compilador que cabe num arquivo.

```jinja
{{ user.name | upper }}
{{ items[0].price | round(2) }}
{% if a > 1 and not b %}...{% elif c %}...{% else %}...{% endif %}
{% for item in items | sort("name") %}
  {{ loop.index }}. {{ item.name }}{% if not loop.last %},{% endif %}
{% else %}
  no items
{% endfor %}
{% set total = price * qty %}
{% include "partial.html" %}
{% extends "layout.html" %}  {% block content %}...{% endblock %}
{{- trims whitespace on the left -}}
```

Operadores: `+ - * / %`, comparação, `and or not`, `in`, parênteses, listas `[1, 2]`, literais de string/número/`true`/`false`/`none`. Filtros embutidos: `upper lower capitalize title trim length join split reverse sort first last default escape safe replace truncate round abs keys values sum min max json`, e `add_filter` pra criar o seu.

```perl
use Stencil;
my $t = Stencil->new(path => 'templates', autoescape => 1);
print $t->render_string('Hello {{ name | upper }}!', { name => 'world' });
$t->add_filter(money => sub { sprintf '$%.2f', shift });
```

Ou pela linha de comando: `perl bin/stencil -p examples -e page.html examples/vars.json`.

Por dentro é o caminho clássico: uma passada de regex separa texto de tags, o parser monta a AST (`if`/`for`/`set`/`include`/`block`), o parser de expressões usa precedence climbing (então `a + b * c | upper` faz o que você espera), e o renderer anda na AST com uma pilha de escopos, resolvendo a cadeia de `extends` pra que blocos do filho sobrescrevam os do pai. Templates parseados ficam em cache por instância.

O que me surpreendeu no Perl: o quanto regex de verdade (com named captures e `/x`) deixa um lexer curto. O que não me surpreendeu: `$self->{_scopes}[-1]{$name}`.

Testes: `prove -l t`.

---

## English

A Jinja-style template engine, in Perl. Yes, Perl. I wanted to learn the language that held the web together in the 90s and couldn't find a better project than a template engine: it has a lexer, a recursive parser, operator precedence, variable scopes, template inheritance... it's a mini compiler that fits in one file.

```jinja
{{ user.name | upper }}
{{ items[0].price | round(2) }}
{% if a > 1 and not b %}...{% elif c %}...{% else %}...{% endif %}
{% for item in items | sort("name") %}
  {{ loop.index }}. {{ item.name }}{% if not loop.last %},{% endif %}
{% else %}
  no items
{% endfor %}
{% set total = price * qty %}
{% include "partial.html" %}
{% extends "layout.html" %}  {% block content %}...{% endblock %}
{{- trims whitespace on the left -}}
```

Operators: `+ - * / %`, comparison, `and or not`, `in`, parentheses, lists `[1, 2]`, string/number/`true`/`false`/`none` literals. Built-in filters: `upper lower capitalize title trim length join split reverse sort first last default escape safe replace truncate round abs keys values sum min max json`, and `add_filter` to create your own.

```perl
use Stencil;
my $t = Stencil->new(path => 'templates', autoescape => 1);
print $t->render_string('Hello {{ name | upper }}!', { name => 'world' });
$t->add_filter(money => sub { sprintf '$%.2f', shift });
```

Or from the command line: `perl bin/stencil -p examples -e page.html examples/vars.json`.

Inside it's the classic path: one regex pass separates text from tags, the parser builds the AST (`if`/`for`/`set`/`include`/`block`), the expression parser uses precedence climbing (so `a + b * c | upper` does what you expect), and the renderer walks the AST with a stack of scopes, resolving the `extends` chain so the child's blocks override the parent's. Parsed templates are cached per instance.

What surprised me about Perl: how much real regex (with named captures and `/x`) makes a lexer short. What did not surprise me: `$self->{_scopes}[-1]{$name}`.

Tests: `prove -l t`.

MIT.
