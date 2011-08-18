package Test::SVN::Repo;
# ABSTRACT: Subversion repository fixtures for testing

use strict;
use warnings;

use Carp        qw( croak );
use IPC::Run    qw( run start );
use File::Temp  qw( tempdir );
use Path::Class ();
use Try::Tiny   qw( catch try );

use base qw( Class::Accessor Test::Builder::Module );

__PACKAGE__->mk_ro_accessors(qw(
        root_path users keep_files verbose start_port end_port retry_count
        server_port server_pid
    ));

#------------------------------------------------------------------------------

my %running_servers;

sub CLEANUP {
    for my $server (values %running_servers) {
        _kill_server($server);
    }
    exit(0);
}
$SIG{$_} = \&CLEANUP for qw( HUP INT QUIT TERM );

#------------------------------------------------------------------------------

sub repo_path        { shift->root_path->subdir('repo') }
sub is_authenticated { exists $_[0]->{users} }

sub url {
    my ($self) = @_;
    return $self->is_authenticated
            ? 'svn://localhost:' . $self->server_port
            : 'file://' . $self->repo_path;
}

#------------------------------------------------------------------------------

sub new {
    my ($class, %args) = @_;
    my $self = {};

    $self->{root_path}   = Path::Class::Dir->new(
                            _defined_or($args{root_path}, tempdir));
    $self->{users}       = $args{users} if exists $args{users};
    $self->{keep_files}  = _defined_or($args{keep_files},
                                defined($args{root_path})),
    $self->{verbose}     = _defined_or($args{verbose}, 0);
    $self->{start_port}  = _defined_or($args{start_port}, 1024);
    $self->{end_port}    = _defined_or($args{end_port}, 65535);
    $self->{retry_count} = _defined_or($args{retry_count}, 100);

    bless $self, $class;

    return $self->_init;
}

sub _defined_or {
    my ($arg, $default) = @_;
    return defined $arg ? $arg : $default;
}

sub _init {
    my ($self) = @_;

    $self->_create_repo;
    if ($self->is_authenticated) {
        croak 'users hash must contain at least one username/password pair'
            if scalar(keys %{ $self->users }) == 0;
        $self->_setup_auth;
        $self->_spawn_server;   # this will die if it fails
    }
    return $self;
}

sub DESTROY {
    my ($self) = @_;
    if (defined $self->{server}) {
        _diag('Shutting down server pid ', $self->server_pid) if $self->verbose;
        _kill_server($self->{server});
        delete $running_servers{$self->{server}};
    }
    $self->root_path->rmtree unless $self->keep_files;
}

#------------------------------------------------------------------------------

sub _diag { __PACKAGE__->builder->diag(@_) }

sub _setup_auth {
    my ($self) = @_;
    my $conf_path = $self->_server_conf_path;

    _create_file($conf_path->file('svnserve.conf'), <<'END');
[general]
anon-access = read
auth-access = write
realm = Test Repo
password-db = passwd
END

    my %auth = %{ $self->users };
    _create_file($conf_path->file('passwd'),
            "[users]\n",
            map { $_ . ' = ' . $auth{$_} . "\n" } keys %auth);

    my $repo_path = $self->repo_path->stringify;
    _create_file($conf_path->file('authz'),
            "[groups]\n",
            'users = ', join(',', keys %auth), "\n",
            "[$repo_path]\n",
            "users = rw\n");

#    _diag(`find $conf_path -type f -print -exec cat {} \\;`);
}

sub _create_repo {
    my ($self) = @_;

    my @cmd = ('svnadmin', 'create', $self->repo_path);
    my ($in, $out, $err);
    run(\@cmd, \$in, \$out, \$err)
        or croak $err;
    _diag(join(' ', @cmd), $out) if $out && $self->verbose;
    _diag(join(' ', @cmd), $err) if $err && $self->verbose;
}

sub _create_file {
    my $fullpath = shift;
    print {$fullpath->openw} @_;
}

sub _spawn_server {
    my ($self) = @_;

    my $retry_count = $self->retry_count;
    my $base_port = $self->start_port;
    my $port_range = $self->end_port - $self->start_port + 1;
    for (1 .. $retry_count) {
        my $port = _choose_random_port($base_port, $port_range);

        if ($self->_try_spawn_server($port)) {
            $running_servers{$self->{server}} = $self->{server};
            $self->{server_port} = $port;
            $self->{server_pid} = $self->_get_server_pid;
            _diag('Server pid ', $self->server_pid,
                  ' started on port ', $self->server_port) if $self->verbose;
            return 1;
        }
        _diag("Port $port busy") if $self->verbose;
    }
    die "Giving up after $retry_count attempts";
}

sub _choose_random_port {
    my ($base_port, $num_ports) = @_;
    return int(rand($num_ports)) + $base_port;
}

sub _try_spawn_server {
    my ($self, $port) = @_;
    my @cmd = ( 'svnserve',
                '-d',           # daemon mode
                '--foreground', # don't actually daemonize
                '-r'            => $self->repo_path->stringify,
                '--pid-file'    => $self->_server_pid_file->stringify,
                '--listen-host' => 'localhost',
                '--listen-port' => $port,
              );

    my ($in, $out, $err);
    my $h = start(\@cmd, \$in, \$out, \$err);
    while ($h->pumpable) {
        if (-e $self->_server_pid_file) {
            $self->{server} = $h;
            return 1;
        }
        $h->pump_nb;
    }
    $h->finish;
    return 0 if ($err =~ /Address already in use/); # retry
    die $err;
}

sub _get_server_pid {
    my ($self) = @_;
    my $retry_count = 5;
    my $pid_filename = $self->_server_pid_file;
    for (1 .. $retry_count) {
        my $pid;
        try {
            $pid = _read_file($pid_filename);
            chomp $pid;
        }
        catch {
            _diag('... retry');
            sleep 1; # svnserve may not have written its file yet
        };
        return $pid if defined $pid;
    }
    croak "Can't find pid file $pid_filename";
}

sub _kill_server {
    my ($server) = @_;
    $server->kill_kill, grace => 5;
}

sub _read_file {
    my $fh = $_[0]->openr;
    local $/ = <$fh>;
}

sub _server_conf_path { shift->repo_path->subdir('conf') }

sub _server_pid_file  { shift->_server_conf_path->file('server.pid') }
1;

__END__

=pod

=head1 SYNOPSIS

    # Create a plain on-disk repo
    $repo = Test::SVN::Repo->new;

    # Create a repo with password authenticated server
    $repo = Test::SVN::Repo->new(
            users => { joe => 'secret', fred => 'foobar' },
        );

    my $repo_url = $repo->url;

    system("svn co $repo");     # do stuff with your new repo

=head1 DESCRIPTION

Create temporary subversion repositories for testing.

If no authentication is required, a simple on-disk repo is created.
An svnserve instance is created when authentication is required.

Repositories and servers are cleaned up when the object is destroyed.

Requires the C<svnadmin> and C<svnserve> external binaries. These are both
included in standard Subversion releases.

=head1 METHODS

=head2 CONSTRUCTOR

Creates a new svn repository, spawning an svnserve server if authentication
is required.

Arguments. All are optional.

=over

=item users

Hashref containing username/password pairs for repository authentication.

If this attribute is specified, there must be at least one user.
Specifying users causes an svnserve instance to be created.

=item root_path

Base path to create the repo. By default, a temporary directory is created,
and deleted on exit.

=item keep_files

Prevent root_path from being deleted in the destructor.

If root_path is provided in the constructor, it will be preserved by default.
If no root_path is provided, and a temporary directory is created, it will
be destroyed by default.

=item verbose

Verbose output. Default off.

=item start_port end_port retry_count

Server mode only.

In order to find a free port for the server, ports are randomly selected from
the range [start_port, end_port] until one succeeds. Gives up after retry_count
failures.

Default values: 1024, 65536, 1000

=back

=head2 READ-ONLY ACCESSORS

=head3 url

Repository URL.

=head3 repo_path

Local path to the SVN repository.

=head3 is_authenticated

True if the the svn repo requires authorisation.
This is enabled by supplying a users hashref to the constructor.

=head3 server_pid

Process id of the svnserve process.

=head3 server_port

Listen port of the svnserve process.

=head1 ACKNOWLEDGEMENTS

Thanks to Strategic Data for sponsoring the development of this module.

=for Pod::Coverage CLEANUP
=for test_synopsis
my ($repo);

=cut
