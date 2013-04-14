use FindBin::libs;
use Chaco;
use DBIx::Handler;
use DBIx::Sunny;
use Plack::Builder;
use Plack::Session;
use URI;
use URI::Escape;
use Furl;
use JSON::XS;
use Devel::KYTProf;
use Config::Pit;

my $config = pit_get('facebook.app', require => {
  app_id           => 'app_id',
  app_secret       => 'app_secret',
  app_url          => 'app_url',
  app_callback_url => 'app_callback_url'
});

$config = {
  %$config,
  dialog_url => 'https://www.facebook.com/dialog/oauth',
  oauth_url  => 'https://graph.facebook.com/oauth/access_token',
  api_url    => 'https://graph.facebook.com/',
};

my $handler = DBIx::Handler->new(
  'dbi:SQLite::memory:', '', '', { sqlite_unicode => 1 }, {
    dbi_class => 'DBIx::Sunny',
  },
);

$handler->dbh->query(<<SQL);
  CREATE TABLE IF NOT EXISTS user (
    id   INTEGER,
    name TEXT,
    icon TEXT,
    PRIMARY KEY (id)
  );
SQL

sub get_user {
  my $id = shift or return undef;
  $handler->dbh->select_row(q{SELECT * FROM user WHERE id = ? LIMIT 1}, $id);
}

sub create_user {
  my ($id, $name, $icon) = @_;
  unless (get_user($id)) {
    $handler->dbh->query(q{INSERT INTO user (id, name, icon) VALUES (?, ?, ?) }, $id, $name, $icon);
  }
}

my $ses;
sub ses {
    $ses ||= Plack::Session->new(req->env);
}

get '/' => sub {
  my $user;
  if (my $id = ses->get('access_token')) {
    $user = get_user($id);
  }
  tmpl 'index.tx', { config => $config, user => $user };
};

post '/logout' => sub {
  ses->remove('access_token');
  redirect '/';
};

get '/callback' => sub {
  my $furl = Furl->new();

  my $uri = URI->new($config->{oauth_url});
  $uri->query_form(
    'client_id'     => $config->{app_id},
    'redirect_uri'  => $config->{app_callback_url},
    'client_secret' => $config->{app_secret},
    'code'          => param_raw->get('code'),
  );
  my $res = $furl->get($uri);

  my $param = { URI->new('?'.$res->content)->query_form };

  $uri = URI->new($config->{api_url}.'me');
  $uri->query_form(
    fields       => 'name,picture',
    access_token => $param->{access_token},
  );
  $res = $furl->get($uri);

  my $json = decode_json $res->content;
  create_user($json->{id}, $json->{name}, $json->{picture}->{data}->{url});
  ses->set('access_token', $json->{id});

  redirect '/';
};

builder {
  enable 'Session';
  run;
};

__DATA__

@@ index.tx
: cascade layouts::base
: around title -> { "Chaco" }
: around content -> {
  : if (!$user) {
    please login<br />
    <form method="GET" action="<: $config.dialog_url :>">
      <input type="hidden" name="client_id" value="<: $config.app_id :>" />
      <input type="hidden" name="redirect_uri" value="<: $config.app_callback_url :>" />
      <input type="hidden" name="state" value="1" />
      <input type="submit" value="login" />
    </form>
  : } else {
    <: $user.name :><br />
    <img src="<: $user.icon :>" /><br />
    <form method="POST" action="/logout">
      <input type="submit" value="logout" />
    </form>
  : }
: }

@@ layouts/base.tx
<!DOCTYPE html>
<html>
  <head><title><: block title -> {} :></title></head>
  <body>
    : block content -> {}
  </body>
</html>
