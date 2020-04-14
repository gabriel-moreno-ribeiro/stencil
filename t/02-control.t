use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Stencil;

my $t = Stencil->new;

# if / elif / else
my $tpl = '{% if n > 10 %}big{% elif n > 5 %}medium{% else %}small{% endif %}';
is $t->render_string($tpl, { n => 20 }), 'big', 'if branch';
is $t->render_string($tpl, { n => 7 }), 'medium', 'elif branch';
is $t->render_string($tpl, { n => 1 }), 'small', 'else branch';
is $t->render_string('{% if list %}y{% else %}n{% endif %}', { list => [] }), 'n', 'empty list is falsy';
is $t->render_string('{% if h %}y{% else %}n{% endif %}', { h => { a => 1 } }), 'y', 'non-empty hash is truthy';
is $t->render_string('{% if s %}y{% else %}n{% endif %}', { s => '0' }), 'n', 'string "0" is falsy';
is $t->render_string('{% if a and not b %}ok{% endif %}', { a => 1, b => 0 }), 'ok', 'compound condition';
is $t->render_string('{% if x %}{% if y %}deep{% endif %}{% endif %}', { x => 1, y => 1 }), 'deep', 'nested if';

# for loops
is $t->render_string('{% for x in xs %}{{ x }},{% endfor %}', { xs => [ 1, 2, 3 ] }), '1,2,3,', 'basic for';
is $t->render_string('{% for x in xs %}{{ x }}{% else %}empty{% endfor %}', { xs => [] }), 'empty', 'for else';
is $t->render_string('{% for x in xs %}{{ loop.index }}:{{ x }}{% if not loop.last %} {% endif %}{% endfor %}',
    { xs => [ 'a', 'b', 'c' ] }), '1:a 2:b 3:c', 'loop.index / loop.last';
is $t->render_string('{% for x in xs %}{{ loop.index0 }}{{ loop.revindex }}{% if loop.first %}F{% endif %}{% endfor %}',
    { xs => [ 'a', 'b' ] }), '02F11', 'loop.index0 / revindex / first';
is $t->render_string('{% for k, v in h %}{{ k }}={{ v }};{% endfor %}', { h => { b => 2, a => 1 } }), 'a=1;b=2;', 'hash iteration sorted by key';
is $t->render_string('{% for i, x in xs %}{{ i }}{{ x }}{% endfor %}', { xs => [ 'a', 'b' ] }), '0a1b', 'index, value over list';
is $t->render_string('{% for c in "abc" %}{{ c }}.{% endfor %}'), 'a.b.c.', 'iterate string chars';
is $t->render_string('{% for row in grid %}{% for c in row %}{{ c }}{% endfor %}|{% endfor %}',
    { grid => [ [ 1, 2 ], [ 3, 4 ] ] }), '12|34|', 'nested for';
is $t->render_string('{% for u in users %}{{ u.name }}{% if u.admin %}*{% endif %} {% endfor %}',
    { users => [ { name => 'a', admin => 1 }, { name => 'b' } ] }), 'a* b ', 'objects in loop';
is $t->render_string('{% for x in xs | sort %}{{ x }}{% endfor %}', { xs => [ 3, 1, 2 ] }), '123', 'filter in for expression';
is $t->render_string('{% for x in xs %}{{ x }}{% endfor %}{{ x }}', { xs => [ 1 ] }), '1', 'loop variable scoped to loop';

# set
is $t->render_string('{% set total = a + b %}{{ total }}', { a => 2, b => 3 }), '5', 'set variable';
is $t->render_string('{% set name = user.name | upper %}Hi {{ name }}', { user => { name => 'bo' } }), 'Hi BO', 'set with filter';

# include
my $inc = Stencil->new(path => "$FindBin::Bin/templates");
is $inc->render_file('include.txt', { name => 'Zed' }), "header for Zed\nbody\n", 'include renders with same context';

done_testing;
