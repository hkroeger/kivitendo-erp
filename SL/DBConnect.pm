package SL::DBConnect;

use strict;

use DBI;
use SL::DB;
use SL::DBConnect::Cache;

my %dateformat_to_datestyle = (
  'yy-mm-dd'   => 'ISO',
  'yyyy-mm-dd' => 'ISO',
  'mm/dd/yy'   => 'SQL, US',
  'dd/mm/yy'   => 'SQL, EUROPEAN',
  'dd.mm.yy'   => 'GERMAN'
);

sub _connect {
  my ($self, @args) = @_;
  @args = $self->get_connect_args if !@args;

  return DBI->connect(@args) unless $::lx_office_conf{debug} && $::lx_office_conf{debug}->{dbix_log4perl};

  require Log::Log4perl;
  require DBIx::Log4perl;

  my $filename =  $::lxdebug->file;
  my $config   =  $::lx_office_conf{debug}->{dbix_log4perl_config};
  $config      =~ s/LXDEBUGFILE/${filename}/g;

  Log::Log4perl->init(\$config);
  return DBIx::Log4perl->connect(@args);
}

sub connect {
  my ($self, @args) = @_;
  my $initial_sql = $self->get_initial_sql;

  if (my $cached_dbh = SL::DBConnect::Cache->get(@args, $initial_sql)) {
    return $cached_dbh;
  }

  my $dbh = $self->_connect(@args);
  return undef if !$dbh;

  if ($initial_sql) {
    $dbh->do($initial_sql);
    $dbh->commit if !$dbh->{AutoCommit};
  }
  SL::DBConnect::Cache->store($dbh, @args, $initial_sql);

  return $dbh;
}

sub get_datestyle {
  my ($self, $dateformat) = @_;
  return $dateformat_to_datestyle{ $dateformat || $::myconfig{dateformat} // '' };
}

sub get_initial_sql {
  my ($self) = @_;

  return undef if !%::myconfig || !$::myconfig{dateformat};

  my $datestyle = $self->get_datestyle;
  return $datestyle ? qq|SET DateStyle to '${datestyle}'| : '';
}

sub get_connect_args {
  my ($self, @args)   = @_;
  my ($domain, $type) = SL::DB::_register_db(SL::DB->default_domain, 'KIVITENDO');
  my $db_cfg          = SL::DB->registry->entry(domain => $domain, type => $type) || { };

  return (
    'dbi:Pg:dbname=' . $db_cfg->{database} . ';host=' . ($db_cfg->{host} || 'localhost') . ';port=' . ($db_cfg->{port} || 5432),
    $db_cfg->{username},
    $db_cfg->{password},
    $self->get_options(%{ $db_cfg->{connect_options} || {} }, @args),
  );
}

sub get_options {
  my $self    = shift;
  my $options = {
    pg_enable_utf8 => 1,
    @_
  };

  return $options;
}

1;
__END__

=pod

=encoding utf8

=head1 NAME

SL::DBConnect - Connect to database for configured client/user,
optionally routing through DBIx::Log4perl

=head1 SYNOPSIS

  # Connect to default database of current user/client, disabling auto
  # commit mode:
  my @options_suitable_for_dbi_connect =
    SL::DBConnect->get_connect_args(AutoCommit => 0);
  my $dbh = SL::DBConnect->connect(@options_suitable_for_dbi_connect);

  # Connect to a very specific database:
  my $dbh = SL::DBConnect->connect('dbi:Pg:dbname=demo', 'user', 'password');

=head1 FUNCTIONS

=over 4

=item C<connect [@dbi_args]>

Connects to the database. If the configuration parameter
C<debug.dbix_log4perl> is set then the call is made through
L<DBIx::Log4per/connect>. Otherwise L<DBI/connect> is called directly.

In each case C<@dbi_args> is passed through as-is.

If C<@dbi_args> are not given they're generated by a call to
L</get_connect_args>.

=item C<get_connect_args [%options]>

Returns an array of database connection settings suitable to a call to
L<DBI/connect> or L</connect>. The settings to use are retrieved by
calling L<SL::DB/_register_db>.

This requires that a client has been set up with
L<SL::Auth/set_client> or that C<%::myconfig> contains legacy
connection settings.

C<%options> are optional database options like C<AutoCommit> (fourth
parameter to L<DBI/connect>). They're merged with default settings by
filtering them through L/get_options>.

=item C<get_datestyle [$dateformat]>

Returns the appropriate value for the C<SET DateStyle to...> SQL call
depending on C<$dateformat> (e.g. C<SQL, EUROPEAN> if C<$dateformat>
equals C<dd.mm.yy>). If C<$dateformat> is not given then it defaults
to C<$::myconfig{dateformat}>.

=item C<get_initial_sql>

Returns SQL commands that should be executed right after a connection
has been established. This is usually the call to configure the
C<DateStyle> format used by the database.

=item C<get_options [%options]>

Returns a hash reference of database options (fourth parameter to
L<DBI/connect>) merged with certain default options.

=back

=head1 BUGS

Nothing here yet.

=head1 AUTHOR

Moritz Bunkus E<lt>m.bunkus@linet-services.deE<gt>

=cut
