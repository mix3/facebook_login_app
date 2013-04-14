package Chaco;

use strict;
use warnings;
use utf8;

use Router::Simple::Sinatraish;
use Plack::Request;
use Text::Xslate;
use Data::Section::Simple;
use JSON::XS;
use Encode;
use Carp;

use parent 'Exporter';

our @EXPORT = qw/
	req
	res
	tmpl
	json
	text
	r404
	r500
	xslate_opt
	stash
	redirect
	forward
	uri_for
	param
	param_raw
	run
/;

my ($req, $res, $ds, %args, $tmpl, %xslate_opt, $req_param, $class, $stash);

sub import {
	my $class = shift;
	strict->import;
	warnings->import;
	utf8->import;
	Router::Simple::Sinatraish->export_to_level(1);
	$class->export_to_level(1);
}

sub run {
	($class) = caller(0);

	$tmpl = Text::Xslate->new(
		path => [ Data::Section::Simple->new($class)->get_data_section() ],
		%xslate_opt,
	);

	my $app = sub {
		my $env = shift;
		$req = Plack::Request->new($env);
		$res = $req->new_response;
		$res->status(200);
		($req_param, $stash) = ({}, {});
		_route();
		$res->finalize;
	};

	if ($ENV{'PLACK_ENV'}) {
		$app;
	} else {
		require Plack::Runner;
		my $runner = Plack::Runner->new;
		$runner->parse_options(@ARGV);
		$runner->run($app);
	}
}

sub _route {
	if (my $route = $class->router->match($req->env)) {
		(%args) = map { $_ => $route->{$_} } grep { $_ ne 'code' } keys %$route;
		$route->{code}->();
	} else {
		r404();
	}
}

sub req  { $req }
sub res  { $res }
sub tmpl {
	my $path = shift;
	my $render;
	if (ref($path) eq 'SCALAR') {
		$render = $tmpl->render_string($$path, @_);
	} else {
		$render = $tmpl->render($path, @_);
	}
	$render = encode_utf8 $render;
	$res->header(['Content-Length' => length $render ]);
	$res->content_type('text/html');
	$res->body($render);
}
sub json {
	my $render = encode_json shift;
	$res->header(['Content-Length' => length $render ]);
	$res->content_type('application/json');
	$res->body($render);
}
sub text {
	my $path = shift;
	my $render;
	if (ref($path) eq 'SCALAR') {
		$render = $tmpl->render_string($$path, @_);
	} else {
		$render = $tmpl->render($path, @_);
	}
	$render = encode_utf8 $render;
	$res->header(['Content-Length' => length $render ]);
	$res->content_type('text/plain');
	$res->body($render);
}
sub xslate_opt { (%xslate_opt) = @_ }
sub r404 {
	my $error = shift;
	$res->status(404);
	$res->body($error || 'Not Found');
}
sub r500 {
	my $error = shift;
	$res->status(500);
	$res->body($error || 'Internal Server Error');
}

sub stash { $stash }

sub param {
	my $source = shift;
	unless ($source) {
		$req_param->{merged} ||= _decode_param(param_raw($source));
	} elsif ($source eq 'query') {
		$req_param->{query} ||= _decode_param(param_raw($source));
	} elsif ($source eq 'body') {
		$req_param->{body} ||= _decode_param(param_raw($source));
	} elsif ($source eq 'args') {
		$req_param->{args} ||= _decode_param(param_raw($source));
	} else {
		croak "unknown source: $source";
	}
}

sub param_raw {
	my $source = shift;
	unless ($source) {
		$req_param->{merged_raw} ||= Hash::MultiValue->new(
			$req->query_parameters->flatten,
			$req->body_parameters->flatten,
			%args,
		);
	} elsif ($source eq 'query') {
		$req_param->{query_raw} ||= $req->query_parameters;
	} elsif ($source eq 'body') {
		$req_param->{body_raw} ||= $req->body_parameters;
	} elsif ($source eq 'args') {
		$req_param->{args_raw} ||= Hash::MultiValue->new(%args);
	} else {
		croak "unknown source: $source";
	}
}

sub _decode_param {
	my ($hmv) = @_;
	my @flatten = $hmv->flatten();
	my @decoded;
	while (my ($k, $v) = splice @flatten, 0, 2) {
		push @decoded, decode_utf8($k), decode_utf8($v);
	}
	return Hash::MultiValue->new(@decoded);
}

sub redirect { $res->redirect(@_) }
sub forward {
	my $path = shift;
	local $req->env->{PATH_INFO} = $path;
	_route();
}
sub uri_for {
	my ($path, $args) = @_;
	my $uri = $req->base;
	$uri->path($uri->path . $path);
	$uri->query_form(@$args) if ($args);
	$uri;
}

1;

=head1 NAME

Chaco

=head1 SYNOPSIS

    use Chaco;
    
    get '/' => sub {
      tmpl 'index.tx', {};
    };
    
    run;
    
    __DATA__
    
    @@ index.tx
    : cascade layouts::base
    : around title -> { "Chaco" }
    : around content -> {
      Hello World!
    : }
    
    @@ layouts/base.tx
    <!DOCTYPE html>
    <html>
      <head><title><: block title -> {} :></title></head>
      <body>
        : block content -> {}
      </body>
    </html>

=head1 EXPORTABLE FUNCTIONS

=head2 get

=head2 post

=head2 any

=head2 req

=head2 res

=head2 tmpl

=head2 json

=head2 text

=head2 r404

=head2 r500

=head2 xslate_opt

=head2 redirect

=head2 forward

=head2 uri_for

=head2 param

=head2 param_raw

=head2 run

=head1 SEE ALSO

L<Router::Simple::Sinatraish> L<Plack::Request> L<Plack::Response> L<Text::Xslate> L<Data::Section::Simple>

=cut
