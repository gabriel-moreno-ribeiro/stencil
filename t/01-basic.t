use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Stencil;

my $t = Stencil->new;

is $t->render_string('Hello {{ name }}!', { name => 'World' }), 'Hello World!', 'variable output';
is $t->render_string('{{ missing }}'), '', 'undefined variable renders empty';
is $t->render_string('{{ "lit" }} {{ 42 }} {{ 1.5 }}'), 'lit 42 1.5', 'literals';
is $t->render_string('{# comment #}x'), 'x', 'comments removed';

# attribute / index access
my $vars = { user => { name => 'Ana', tags => [ 'a', 'b', 'c' ] }, idx => 1 };
is $t->render_string('{{ user.name }}'), '', 'attr on missing';
is $t->render_string('{{ user.name }}', $vars), 'Ana', 'dotted hash access';
is $t->render_string('{{ user.tags.0 }}-{{ user.tags[2] }}-{{ user.tags[idx] }}', $vars), 'a-c-b', 'array index access';
is $t->render_string('{{ user["name"] }}', $vars), 'Ana', 'bracket string key';

# filters
is $t->render_string('{{ "abc" | upper }}'), 'ABC', 'upper';
is $t->render_string('{{ "ABC" | lower | capitalize }}'), 'Abc', 'chained filters';
is $t->render_string('{{ "hello big world" | title }}'), 'Hello Big World', 'title';
is $t->render_string('{{ list | join(", ") }}', { list => [ 1, 2, 3 ] }), '1, 2, 3', 'join with arg';
is $t->render_string('{{ list | length }}', { list => [ 1, 2, 3 ] }), '3', 'length of list';
is $t->render_string('{{ "abcd" | length }}'), '4', 'length of string';
is $t->render_string('{{ list | reverse | first }}', { list => [ 1, 2, 3 ] }), '3', 'reverse + first';
is $t->render_string('{{ list | sort | join("") }}', { list => [ 3, 1, 2 ] }), '123', 'numeric sort';
is $t->render_string('{{ missing | default("n/a") }}'), 'n/a', 'default filter';
is $t->render_string('{% for p in ps | sort("n") %}{{ p.n }}{% endfor %}', { ps => [ { n => 'b' }, { n => 'a' } ] }), 'ab', 'sort by attribute';
is $t->render_string('{{ "  x  " | trim }}|'), 'x|', 'trim';
is $t->render_string('{{ "a-b-c" | replace("-", "+") }}'), 'a+b+c', 'replace';
is $t->render_string('{{ "abcdefgh" | truncate(3) }}'), 'abc...', 'truncate';
is $t->render_string('{{ 3.14159 | round(2) }}'), '3.14', 'round';
is $t->render_string('{{ list | sum }} {{ list | max }} {{ list | min }}', { list => [ 4, 9, 2 ] }), '15 9 2', 'sum/max/min';
is $t->render_string('{{ h | keys | join(",") }}', { h => { b => 1, a => 2 } }), 'a,b', 'keys';
is $t->render_string('{{ "<b>" | escape }}'), '&lt;b&gt;', 'escape filter';
is $t->render_string('{{ d | json }}', { d => { a => [ 1, 2 ] } }), '{"a":[1,2]}', 'json filter';

# custom filter
$t->add_filter(shout => sub { uc($_[0]) . '!' });
is $t->render_string('{{ "hi" | shout }}'), 'HI!', 'custom filter';

# arithmetic and comparisons
is $t->render_string('{{ 1 + 2 * 3 }}'), '7', 'precedence';
is $t->render_string('{{ (1 + 2) * 3 }}'), '9', 'parens';
is $t->render_string('{{ 10 / 4 }} {{ 10 % 4 }} {{ -x }}', { x => 5 }), '2.5 2 -5', 'div mod neg';
is $t->render_string('{{ "a" + "b" }}'), 'ab', 'string concatenation with +';
is $t->render_string('{{ 2 > 1 }}{{ 1 == 1 }}{{ "a" != "a" }}{{ 3 <= 2 }}'), '1100', 'comparisons';
is $t->render_string('{{ "b" in list }}{{ "z" in list }}{{ "z" not in list }}', { list => [ 'a', 'b' ] }), '101', 'in / not in';
is $t->render_string('{{ "ell" in "hello" }}'), '1', 'substring in';
is $t->render_string('{{ a and b }}|{{ a or b }}|{{ not a }}', { a => 0, b => 'yes' }), '0|yes|1', 'logical operators';
is $t->render_string('{{ [1, 2, 3] | length }}'), '3', 'list literal';

# autoescape
my $safe = Stencil->new(autoescape => 1);
is $safe->render_string('{{ x }}', { x => '<a href="x">&</a>' }), '&lt;a href=&quot;x&quot;&gt;&amp;&lt;/a&gt;', 'autoescape on';
is $safe->render_string('{{ x | safe }}', { x => '<b>' }), '<b>', 'safe filter bypasses autoescape';
is $safe->render_string('{{ x | escape }}', { x => '<b>' }), '&lt;b&gt;', 'escape not double escaped';

# whitespace control
is $t->render_string("a  {{- 'b' -}}  c"), 'abc', 'strip both sides';
is $t->render_string("a\n{%- if 1 %}b{% endif -%}\nc"), 'abc', 'block whitespace control';

# raw block
is $t->render_string('{% raw %}{{ not_rendered }}{% endraw %}'), '{{ not_rendered }}', 'raw block';

# errors
eval { $t->render_string('{{ x | nope }}') };
like $@, qr/unknown filter 'nope'/, 'unknown filter dies';
eval { $t->render_string('{% if x %}unclosed') };
like $@, qr/missing/, 'unclosed block dies';
eval { $t->render_string('{{ 1 / 0 }}') };
like $@, qr/division by zero/, 'division by zero dies';

done_testing;
