package Stencil;

# Stencil - a Jinja-style template engine written from scratch in Perl.
#
# Pipeline:  source text -> tokens -> AST -> rendered string
#
#   {{ expr | filter(args) }}          output an expression
#   {% if a and b %} ... {% elif c %} ... {% else %} ... {% endif %}
#   {% for x in list %} ... {% else %} ... {% endfor %}   (loop.index, loop.first, ...)
#   {% set name = expr %}
#   {% include "file.html" %}
#   {% extends "base.html" %} / {% block name %} ... {% endblock %}
#   {# comment #}
#
# "-" next to a delimiter strips adjacent whitespace: {{- x -}}, {%- if -%}

use strict;
use warnings;
use Carp qw(croak);

our $VERSION = '1.0.0';

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

sub new {
    my ($class, %opts) = @_;
    my $self = bless {
        path       => $opts{path} || '.',
        autoescape => $opts{autoescape} ? 1 : 0,
        filters    => { %{ default_filters() }, %{ $opts{filters} || {} } },
        cache      => {},
    }, $class;
    return $self;
}

sub add_filter {
    my ($self, $name, $code) = @_;
    $self->{filters}{$name} = $code;
    return $self;
}

sub render_string {
    my ($self, $source, $vars) = @_;
    my $ast = $self->_parse($source, '<string>');
    return $self->_render_ast($ast, $vars || {});
}

sub render_file {
    my ($self, $name, $vars) = @_;
    my $ast = $self->_load($name);
    return $self->_render_ast($ast, $vars || {});
}

# ---------------------------------------------------------------------------
# Loading and caching
# ---------------------------------------------------------------------------

sub _load {
    my ($self, $name) = @_;
    return $self->{cache}{$name} if $self->{cache}{$name};
    my $file = "$self->{path}/$name";
    open my $fh, '<:encoding(UTF-8)', $file or croak "Stencil: cannot open template '$file': $!";
    local $/;
    my $src = <$fh>;
    close $fh;
    return $self->{cache}{$name} = $self->_parse($src, $name);
}

# ---------------------------------------------------------------------------
# Lexer
# ---------------------------------------------------------------------------

sub _tokenize {
    my ($self, $src, $name) = @_;
    my @tokens;
    my $line = 1;
    pos($src) = 0;
    while (pos($src) < length $src) {
        if ($src =~ /\G\{\{(-?)\s*(.*?)\s*(-?)\}\}/gcs) {
            push @tokens, { type => 'var', text => $2, lstrip => $1, rstrip => $3, line => $line };
            $line += () = "$2" =~ /\n/g;
        }
        elsif ($src =~ /\G\{%(-?)\s*(.*?)\s*(-?)%\}/gcs) {
            push @tokens, { type => 'block', text => $2, lstrip => $1, rstrip => $3, line => $line };
            $line += () = "$2" =~ /\n/g;
        }
        elsif ($src =~ /\G\{#(.*?)#\}/gcs) {
            $line += () = "$1" =~ /\n/g;
        }
        elsif ($src =~ /\G(.+?)(?=\{\{|\{%|\{#|\z)/gcs) {
            push @tokens, { type => 'text', text => $1, line => $line };
            $line += () = "$1" =~ /\n/g;
        }
        else {
            croak "Stencil: unterminated tag in $name at line $line";
        }
    }
    # whitespace control
    for my $i (0 .. $#tokens) {
        my $t = $tokens[$i];
        next if $t->{type} eq 'text';
        if ($t->{lstrip} && $i > 0 && $tokens[$i - 1]{type} eq 'text') {
            $tokens[$i - 1]{text} =~ s/\s+\z//;
        }
        if ($t->{rstrip} && $i < $#tokens && $tokens[$i + 1]{type} eq 'text') {
            $tokens[$i + 1]{text} =~ s/\A\s+//;
        }
    }
    return \@tokens;
}

# ---------------------------------------------------------------------------
# Parser: tokens -> AST
# AST nodes are array refs: [type, ...payload]
# ---------------------------------------------------------------------------

sub _parse {
    my ($self, $src, $name) = @_;
    my $tokens = $self->_tokenize($src, $name);
    my $state  = { tokens => $tokens, pos => 0, name => $name, blocks => {}, extends => undef };
    my $body   = $self->_parse_nodes($state, []);
    croak "Stencil: unexpected '$state->{stop}' in $name" if $state->{stop};
    return { body => $body, blocks => $state->{blocks}, extends => $state->{extends} };
}

sub _parse_nodes {
    my ($self, $state, $terminators) = @_;
    my @nodes;
    my $tokens = $state->{tokens};
    while ($state->{pos} < @$tokens) {
        my $t = $tokens->[ $state->{pos}++ ];
        if ($t->{type} eq 'text') {
            push @nodes, [ 'text', $t->{text} ];
        }
        elsif ($t->{type} eq 'var') {
            push @nodes, [ 'output', $self->_parse_expr($t->{text}, $t->{line}, $state->{name}) ];
        }
        else {
            my ($kw, $rest) = $t->{text} =~ /^(\w+)\s*(.*)$/s
                or croak "Stencil: malformed block tag '{% $t->{text} %}' in $state->{name} line $t->{line}";
            if (grep { $_ eq $kw } @$terminators) {
                $state->{stop} = $kw;
                $state->{stop_rest} = $rest;
                return \@nodes;
            }
            push @nodes, $self->_parse_block($state, $kw, $rest, $t);
        }
    }
    croak "Stencil: missing '@{[ join '/', @$terminators ]}' in $state->{name}" if @$terminators;
    return \@nodes;
}

sub _parse_block {
    my ($self, $state, $kw, $rest, $t) = @_;
    my $name = $state->{name};

    if ($kw eq 'if') {
        my @branches;
        my $cond = $self->_parse_expr($rest, $t->{line}, $name);
        while (1) {
            my $body = $self->_parse_nodes($state, [qw(elif else endif)]);
            push @branches, [ $cond, $body ];
            my $stop = delete $state->{stop};
            if ($stop eq 'elif') {
                $cond = $self->_parse_expr($state->{stop_rest}, $t->{line}, $name);
                next;
            }
            if ($stop eq 'else') {
                my $else = $self->_parse_nodes($state, ['endif']);
                delete $state->{stop};
                push @branches, [ [ 'lit', 1 ], $else ];
            }
            last;
        }
        return [ 'if', \@branches ];
    }
    if ($kw eq 'for') {
        my ($vars, $expr) = $rest =~ /^(\w+(?:\s*,\s*\w+)?)\s+in\s+(.+)$/s
            or croak "Stencil: bad for loop '$rest' in $name line $t->{line}";
        my @vars = split /\s*,\s*/, $vars;
        my $iter = $self->_parse_expr($expr, $t->{line}, $name);
        my $body = $self->_parse_nodes($state, [qw(else endfor)]);
        my $else = [];
        if (delete($state->{stop}) eq 'else') {
            $else = $self->_parse_nodes($state, ['endfor']);
            delete $state->{stop};
        }
        return [ 'for', \@vars, $iter, $body, $else ];
    }
    if ($kw eq 'set') {
        my ($var, $expr) = $rest =~ /^(\w+)\s*=\s*(.+)$/s
            or croak "Stencil: bad set '$rest' in $name line $t->{line}";
        return [ 'set', $var, $self->_parse_expr($expr, $t->{line}, $name) ];
    }
    if ($kw eq 'include') {
        return [ 'include', $self->_parse_expr($rest, $t->{line}, $name) ];
    }
    if ($kw eq 'extends') {
        my $expr = $self->_parse_expr($rest, $t->{line}, $name);
        croak "Stencil: extends must be a string literal" unless $expr->[0] eq 'lit';
        $state->{extends} = $expr->[1];
        return [ 'noop' ];
    }
    if ($kw eq 'block') {
        my ($bname) = $rest =~ /^(\w+)$/ or croak "Stencil: bad block name '$rest' in $name";
        my $body = $self->_parse_nodes($state, ['endblock']);
        delete $state->{stop};
        $state->{blocks}{$bname} = $body;
        return [ 'block', $bname, $body ];
    }
    if ($kw eq 'raw') {
        my $tokens = $state->{tokens};
        my $text = '';
        while ($state->{pos} < @$tokens) {
            my $n = $tokens->[ $state->{pos}++ ];
            last if $n->{type} eq 'block' && $n->{text} =~ /^endraw$/;
            $text .= $n->{type} eq 'text' ? $n->{text}
                   : $n->{type} eq 'var'  ? "{{ $n->{text} }}"
                   :                        "{% $n->{text} %}";
        }
        return [ 'text', $text ];
    }
    croak "Stencil: unknown tag '$kw' in $name line $t->{line}";
}

# ---------------------------------------------------------------------------
# Expression parser (precedence climbing)
#   or > and > not > comparison/in > + - > * / % > unary - > postfix (.x [i] (args)) > atoms
#   Filters bind loosest of all: expr | f(a) | g
# ---------------------------------------------------------------------------

my $TOKEN_RE = qr/
    \s*(?:
        (?<num>\d+(?:\.\d+)?)
      | "(?<str>(?:[^"\\]|\\.)*)"
      | '(?<str>(?:[^'\\]|\\.)*)'
      | (?<id>[A-Za-z_]\w*)
      | (?<op>==|!=|<=|>=|[-+*\/%<>()\[\].,|:])
    )
/x;

sub _lex_expr {
    my ($src, $line, $name) = @_;
    my @out;
    pos($src) = 0;
    while (pos($src) < length $src) {
        last if $src =~ /\G\s*\z/gc;
        $src =~ /\G$TOKEN_RE/gc or croak "Stencil: bad expression near '" . substr($src, pos($src) // 0, 10) . "' in $name line $line";
        if (defined $+{num}) { push @out, [ 'num', $+{num} ] }
        elsif (defined $+{str}) { my $s = $+{str}; $s =~ s/\\(.)/$1/g; push @out, [ 'str', $s ] }
        elsif (defined $+{id}) { push @out, [ 'id', $+{id} ] }
        else { push @out, [ 'op', $+{op} ] }
    }
    return \@out;
}

sub _parse_expr {
    my ($self, $src, $line, $name) = @_;
    my $toks = _lex_expr($src, $line, $name);
    my $p = { toks => $toks, i => 0, name => $name, line => $line };
    my $node = $self->_p_filters($p);
    croak "Stencil: trailing tokens in expression '$src' in $name line $line" if $p->{i} < @$toks;
    return $node;
}

sub _peek { my ($p, $type, $val) = @_; my $t = $p->{toks}[ $p->{i} ] or return 0; return 0 if $t->[0] ne $type; return !defined $val || $t->[1] eq $val; }
sub _next { my ($p) = @_; return $p->{toks}[ $p->{i}++ ]; }
sub _expect {
    my ($p, $type, $val) = @_;
    _peek($p, $type, $val) or croak "Stencil: expected '$val' in $p->{name} line $p->{line}";
    return _next($p);
}

sub _p_filters {
    my ($self, $p) = @_;
    my $node = $self->_p_or($p);
    while (_peek($p, 'op', '|')) {
        _next($p);
        my $fname = _expect($p, 'id')->[1];
        my @args;
        if (_peek($p, 'op', '(')) {
            _next($p);
            until (_peek($p, 'op', ')')) {
                push @args, $self->_p_or($p);
                _next($p) if _peek($p, 'op', ',');
            }
            _next($p);
        }
        $node = [ 'filter', $fname, $node, \@args ];
    }
    return $node;
}

sub _p_or {
    my ($self, $p) = @_;
    my $l = $self->_p_and($p);
    while (_peek($p, 'id', 'or')) { _next($p); $l = [ 'or', $l, $self->_p_and($p) ] }
    return $l;
}

sub _p_and {
    my ($self, $p) = @_;
    my $l = $self->_p_not($p);
    while (_peek($p, 'id', 'and')) { _next($p); $l = [ 'and', $l, $self->_p_not($p) ] }
    return $l;
}

sub _p_not {
    my ($self, $p) = @_;
    if (_peek($p, 'id', 'not')) { _next($p); return [ 'not', $self->_p_not($p) ] }
    return $self->_p_cmp($p);
}

sub _p_cmp {
    my ($self, $p) = @_;
    my $l = $self->_p_add($p);
    while (1) {
        if (_peek($p, 'op') && $p->{toks}[ $p->{i} ][1] =~ /^(==|!=|<=|>=|<|>)$/) {
            my $op = _next($p)->[1];
            $l = [ 'cmp', $op, $l, $self->_p_add($p) ];
        }
        elsif (_peek($p, 'id', 'in')) { _next($p); $l = [ 'in', $l, $self->_p_add($p) ] }
        elsif (_peek($p, 'id', 'not') && $p->{toks}[ $p->{i} + 1 ] && $p->{toks}[ $p->{i} + 1 ][1] eq 'in') {
            _next($p); _next($p); $l = [ 'not', [ 'in', $l, $self->_p_add($p) ] ];
        }
        else { last }
    }
    return $l;
}

sub _p_add {
    my ($self, $p) = @_;
    my $l = $self->_p_mul($p);
    while (_peek($p, 'op', '+') || _peek($p, 'op', '-')) {
        my $op = _next($p)->[1];
        $l = [ 'bin', $op, $l, $self->_p_mul($p) ];
    }
    return $l;
}

sub _p_mul {
    my ($self, $p) = @_;
    my $l = $self->_p_unary($p);
    while (_peek($p, 'op', '*') || _peek($p, 'op', '/') || _peek($p, 'op', '%')) {
        my $op = _next($p)->[1];
        $l = [ 'bin', $op, $l, $self->_p_unary($p) ];
    }
    return $l;
}

sub _p_unary {
    my ($self, $p) = @_;
    if (_peek($p, 'op', '-')) { _next($p); return [ 'neg', $self->_p_unary($p) ] }
    return $self->_p_postfix($p);
}

sub _p_postfix {
    my ($self, $p) = @_;
    my $node = $self->_p_atom($p);
    while (1) {
        if (_peek($p, 'op', '.')) {
            _next($p);
            my $t = _next($p);
            croak "Stencil: expected attribute name in $p->{name} line $p->{line}" unless $t && ($t->[0] eq 'id' || $t->[0] eq 'num');
            $node = [ 'attr', $node, [ 'lit', $t->[1] ] ];
        }
        elsif (_peek($p, 'op', '[')) {
            _next($p);
            my $idx = $self->_p_or($p);
            _expect($p, 'op', ']');
            $node = [ 'attr', $node, $idx ];
        }
        else { last }
    }
    return $node;
}

sub _p_atom {
    my ($self, $p) = @_;
    my $t = _next($p) or croak "Stencil: unexpected end of expression in $p->{name} line $p->{line}";
    return [ 'lit', $t->[1] + 0 ] if $t->[0] eq 'num';
    return [ 'lit', $t->[1] ]     if $t->[0] eq 'str';
    if ($t->[0] eq 'id') {
        return [ 'lit', 1 ]     if $t->[1] eq 'true';
        return [ 'lit', 0 ]     if $t->[1] eq 'false';
        return [ 'lit', undef ] if $t->[1] eq 'none' || $t->[1] eq 'null';
        return [ 'var', $t->[1] ];
    }
    if ($t->[0] eq 'op' && $t->[1] eq '(') {
        my $inner = $self->_p_filters($p);
        _expect($p, 'op', ')');
        return $inner;
    }
    if ($t->[0] eq 'op' && $t->[1] eq '[') {
        my @items;
        until (_peek($p, 'op', ']')) {
            push @items, $self->_p_or($p);
            _next($p) if _peek($p, 'op', ',');
        }
        _next($p);
        return [ 'list', \@items ];
    }
    croak "Stencil: unexpected '$t->[1]' in expression in $p->{name} line $p->{line}";
}

# ---------------------------------------------------------------------------
# Renderer
# ---------------------------------------------------------------------------

sub _render_ast {
    my ($self, $tpl, $vars) = @_;
    my $ctx = { vars => [ { %$vars } ], blocks => {} };
    # resolve inheritance chain: child blocks override parent blocks
    my @chain = ($tpl);
    while ($chain[-1]{extends}) {
        push @chain, $self->_load($chain[-1]{extends});
        croak "Stencil: inheritance loop" if @chain > 50;
    }
    for my $t (@chain) {
        for my $b (keys %{ $t->{blocks} }) {
            $ctx->{blocks}{$b} //= $t->{blocks}{$b};
        }
    }
    my $out = '';
    $self->_render_nodes($chain[-1]{body}, $ctx, \$out);
    return $out;
}

sub _render_nodes {
    my ($self, $nodes, $ctx, $out) = @_;
    for my $n (@$nodes) {
        my $type = $n->[0];
        if ($type eq 'text') { $$out .= $n->[1] }
        elsif ($type eq 'output') {
            my $v = $self->_eval($n->[1], $ctx);
            $$out .= $self->_stringify($v, $n->[1]);
        }
        elsif ($type eq 'if') {
            for my $br (@{ $n->[1] }) {
                if (_truthy($self->_eval($br->[0], $ctx))) {
                    $self->_render_nodes($br->[1], $ctx, $out);
                    last;
                }
            }
        }
        elsif ($type eq 'for') { $self->_render_for($n, $ctx, $out) }
        elsif ($type eq 'set') { $ctx->{vars}[-1]{ $n->[1] } = $self->_eval($n->[2], $ctx) }
        elsif ($type eq 'include') {
            my $name = $self->_eval($n->[1], $ctx);
            my $tpl  = $self->_load($name);
            $self->_render_nodes($tpl->{body}, $ctx, $out);
        }
        elsif ($type eq 'block') {
            my $body = $ctx->{blocks}{ $n->[1] } || $n->[2];
            $self->_render_nodes($body, $ctx, $out);
        }
    }
}

sub _render_for {
    my ($self, $n, $ctx, $out) = @_;
    my ($vars, $iter_expr, $body, $else) = @$n[1 .. 4];
    my $iter = $self->_eval($iter_expr, $ctx);
    my @items;
    if (ref $iter eq 'ARRAY') { @items = @$iter }
    elsif (ref $iter eq 'HASH') { @items = map { [ $_, $iter->{$_} ] } sort keys %$iter }
    elsif (defined $iter && !ref $iter) { @items = split //, $iter }
    if (!@items) {
        $self->_render_nodes($else, $ctx, $out);
        return;
    }
    my $count = @items;
    for my $i (0 .. $#items) {
        my %scope;
        if (@$vars == 2) {
            my $it = $items[$i];
            @scope{@$vars} = ref $it eq 'ARRAY' ? @$it[0, 1] : ($i, $it);
        }
        else { $scope{ $vars->[0] } = $items[$i] }
        $scope{loop} = {
            index => $i + 1, index0 => $i, revindex => $count - $i, revindex0 => $count - $i - 1,
            first => $i == 0 ? 1 : 0, last => $i == $#items ? 1 : 0, length => $count,
        };
        push @{ $ctx->{vars} }, \%scope;
        $self->_render_nodes($body, $ctx, $out);
        pop @{ $ctx->{vars} };
    }
}

sub _lookup {
    my ($ctx, $name) = @_;
    for my $scope (reverse @{ $ctx->{vars} }) {
        return $scope->{$name} if exists $scope->{$name};
    }
    return undef;
}

sub _eval {
    my ($self, $e, $ctx) = @_;
    my $t = $e->[0];
    return $e->[1] if $t eq 'lit';
    return _lookup($ctx, $e->[1]) if $t eq 'var';
    if ($t eq 'attr') {
        my $obj = $self->_eval($e->[1], $ctx);
        my $key = $self->_eval($e->[2], $ctx);
        return undef unless defined $obj && defined $key;
        if (ref $obj eq 'HASH')  { return $obj->{$key} }
        if (ref $obj eq 'ARRAY') { return $key =~ /^-?\d+$/ ? $obj->[$key] : undef }
        if (ref $obj && eval { $obj->can($key) }) { return $obj->$key() }
        return undef;
    }
    if ($t eq 'list') { return [ map { $self->_eval($_, $ctx) } @{ $e->[1] } ] }
    if ($t eq 'filter') {
        my $f = $self->{filters}{ $e->[1] } or croak "Stencil: unknown filter '$e->[1]'";
        my $val = $self->_eval($e->[2], $ctx);
        return $f->($val, map { $self->_eval($_, $ctx) } @{ $e->[3] });
    }
    if ($t eq 'and') { my $l = $self->_eval($e->[1], $ctx); return _truthy($l) ? $self->_eval($e->[2], $ctx) : $l }
    if ($t eq 'or')  { my $l = $self->_eval($e->[1], $ctx); return _truthy($l) ? $l : $self->_eval($e->[2], $ctx) }
    if ($t eq 'not') { return _truthy($self->_eval($e->[1], $ctx)) ? 0 : 1 }
    if ($t eq 'neg') { return -( $self->_eval($e->[1], $ctx) // 0 ) }
    if ($t eq 'in') {
        my $needle = $self->_eval($e->[1], $ctx);
        my $hay    = $self->_eval($e->[2], $ctx);
        return 0 unless defined $hay;
        if (ref $hay eq 'ARRAY') { return (grep { defined $_ && defined $needle && $_ eq $needle } @$hay) ? 1 : 0 }
        if (ref $hay eq 'HASH')  { return exists $hay->{ $needle // '' } ? 1 : 0 }
        return index($hay, $needle // '') >= 0 ? 1 : 0;
    }
    if ($t eq 'cmp') {
        my ($op, $l, $r) = ($e->[1], $self->_eval($e->[2], $ctx), $self->_eval($e->[3], $ctx));
        my $numeric = _is_num($l) && _is_num($r);
        $l //= ''; $r //= '';
        if ($op eq '==') { return ($numeric ? $l == $r : $l eq $r) ? 1 : 0 }
        if ($op eq '!=') { return ($numeric ? $l != $r : $l ne $r) ? 1 : 0 }
        if ($op eq '<')  { return ($numeric ? $l < $r  : $l lt $r) ? 1 : 0 }
        if ($op eq '>')  { return ($numeric ? $l > $r  : $l gt $r) ? 1 : 0 }
        if ($op eq '<=') { return ($numeric ? $l <= $r : $l le $r) ? 1 : 0 }
        if ($op eq '>=') { return ($numeric ? $l >= $r : $l ge $r) ? 1 : 0 }
    }
    if ($t eq 'bin') {
        my ($op, $l, $r) = ($e->[1], $self->_eval($e->[2], $ctx), $self->_eval($e->[3], $ctx));
        if ($op eq '+' && !(_is_num($l) && _is_num($r))) { return ($l // '') . ($r // '') }
        $l //= 0; $r //= 0;
        return $l + $r if $op eq '+';
        return $l - $r if $op eq '-';
        return $l * $r if $op eq '*';
        if ($op eq '/') { croak "Stencil: division by zero" if $r == 0; return $l / $r }
        if ($op eq '%') { croak "Stencil: division by zero" if $r == 0; return $l % $r }
    }
    croak "Stencil: cannot evaluate node '$t'";
}

sub _is_num { my $v = shift; return defined $v && !ref $v && $v =~ /^-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?$/ }

sub _truthy {
    my $v = shift;
    return 0 unless defined $v;
    return @$v ? 1 : 0 if ref $v eq 'ARRAY';
    return %$v ? 1 : 0 if ref $v eq 'HASH';
    return 1 if ref $v;
    return 0 if $v eq '' || $v eq '0';
    return 1;
}

sub _stringify {
    my ($self, $v, $expr) = @_;
    return '' unless defined $v;
    if (ref $v eq 'ARRAY') { return join ', ', map { $self->_stringify($_) } @$v }
    if (ref $v eq 'HASH')  { return join ', ', map { "$_=" . $self->_stringify($v->{$_}) } sort keys %$v }
    if (ref $v eq 'Stencil::Safe') { return $$v }
    return $self->{autoescape} ? html_escape($v) : "$v";
}

sub html_escape {
    my $s = shift;
    return '' unless defined $s;
    return $$s if ref $s eq 'Stencil::Safe';
    $s =~ s/&/&amp;/g; $s =~ s/</&lt;/g; $s =~ s/>/&gt;/g; $s =~ s/"/&quot;/g; $s =~ s/'/&#39;/g;
    return $s;
}

sub safe { my $s = shift; return bless \$s, 'Stencil::Safe' }

# ---------------------------------------------------------------------------
# Built-in filters
# ---------------------------------------------------------------------------

sub default_filters {
    return {
        upper      => sub { uc($_[0] // '') },
        lower      => sub { lc($_[0] // '') },
        capitalize => sub { ucfirst(lc($_[0] // '')) },
        title      => sub { my $s = $_[0] // ''; $s =~ s/(\w+)/\u\L$1/g; $s },
        trim       => sub { my $s = $_[0] // ''; $s =~ s/^\s+|\s+$//g; $s },
        length     => sub { my $v = $_[0]; return 0 unless defined $v; ref $v eq 'ARRAY' ? scalar @$v : ref $v eq 'HASH' ? scalar keys %$v : length $v },
        join       => sub { my ($v, $sep) = @_; join($sep // '', ref $v eq 'ARRAY' ? @$v : ($v // '')) },
        split      => sub { my ($v, $sep) = @_; [ split(defined $sep ? quotemeta $sep : qr/\s+/, $v // '') ] },
        reverse    => sub { my $v = $_[0]; ref $v eq 'ARRAY' ? [ reverse @$v ] : scalar reverse($v // '') },
        sort       => sub {
            my ($v, $attr) = @_;
            return $v unless ref $v eq 'ARRAY';
            my @keyed = map { [ defined $attr && ref $_ eq 'HASH' ? $_->{$attr} : $_, $_ ] } @$v;
            my $numeric = !grep { !_is_num($_->[0]) } @keyed;
            return [ map { $_->[1] } sort { $numeric ? $a->[0] <=> $b->[0] : ($a->[0] // '') cmp ($b->[0] // '') } @keyed ];
        },
        first      => sub { my $v = $_[0]; ref $v eq 'ARRAY' ? $v->[0] : substr($v // '', 0, 1) },
        last       => sub { my $v = $_[0]; ref $v eq 'ARRAY' ? $v->[-1] : substr($v // '', -1) },
        default    => sub { my ($v, $d) = @_; (defined $v && $v ne '') ? $v : $d },
        escape     => sub { safe(html_escape($_[0])) },
        e          => sub { safe(html_escape($_[0])) },
        safe       => sub { safe($_[0] // '') },
        replace    => sub { my ($v, $from, $to) = @_; $v //= ''; $from = quotemeta($from // ''); $v =~ s/$from/$to/g; $v },
        truncate   => sub { my ($v, $n, $end) = @_; $v //= ''; $n //= 255; $end //= '...'; length $v <= $n ? $v : substr($v, 0, $n) . $end },
        round      => sub { my ($v, $p) = @_; sprintf("%.${\($p // 0)}f", $v // 0) },
        abs        => sub { abs($_[0] // 0) },
        keys       => sub { [ sort keys %{ $_[0] || {} } ] },
        values     => sub { my $h = $_[0] || {}; [ map { $h->{$_} } sort keys %$h ] },
        sum        => sub { my $s = 0; $s += $_ for @{ $_[0] || [] }; $s },
        min        => sub { my @v = sort { $a <=> $b } @{ $_[0] || [] }; $v[0] },
        max        => sub { my @v = sort { $a <=> $b } @{ $_[0] || [] }; $v[-1] },
        json       => sub { require JSON::PP; JSON::PP->new->canonical->encode($_[0]) },
    };
}

1;

__END__

=head1 NAME

Stencil - a Jinja-style template engine written from scratch in Perl

=head1 SYNOPSIS

    my $t = Stencil->new(path => 'templates', autoescape => 1);
    print $t->render_string('Hello {{ name | upper }}!', { name => 'world' });
    print $t->render_file('page.html', { items => [1, 2, 3] });

=cut
