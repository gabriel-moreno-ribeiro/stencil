use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Stencil;

my $t = Stencil->new(path => "$FindBin::Bin/templates");

my $base = $t->render_file('base.html', { year => 2020 });
like $base, qr/<title>Default title<\/title>/, 'base block default';
like $base, qr/base content/, 'base content block';

my $child = $t->render_file('child.html', { items => [ 1, 2 ], year => 2020 });
like $child, qr/<title>Child title<\/title>/, 'child overrides title';
like $child, qr/<li>1<\/li><li>2<\/li>/, 'child content block with loop';
like $child, qr/\(c\) 2020/, 'inherited footer block';
unlike $child, qr/base content/, 'overridden block not rendered';

my $gc = $t->render_file('grandchild.html', { items => [ 9 ], year => 2020 });
like $gc, qr/Child title/, 'grandchild keeps parent override';
like $gc, qr/custom footer/, 'grandchild overrides footer';
like $gc, qr/<li>9<\/li>/, 'grandchild inherits child content';

# cache: second render reuses parsed template
is $t->render_file('child.html', { items => [], year => 1 }), $t->render_file('child.html', { items => [], year => 1 }), 'cached render is stable';

done_testing;
