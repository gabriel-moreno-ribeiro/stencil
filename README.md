# Stencil

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

**EN:** a Jinja-style template engine in core Perl (zero CPAN dependencies). One regex pass tokenizes, a recursive-descent parser builds the AST, a precedence-climbing expression parser handles filters and operators, and the renderer walks the tree with scoped variables, `include` and `extends`/`block` inheritance, autoescaping and a per-engine template cache. `prove -l t` runs the tests. MIT.
