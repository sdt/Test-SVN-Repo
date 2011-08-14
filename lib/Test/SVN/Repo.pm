package Test::SVN::Repo;
# ABSTRACT: Authenticated subversion repositories for testing

use Carp        qw( croak );
use IPC::Run    qw( run );
use File::Temp  qw( tempdir );
use Path::Class ();
use Try::Tiny   qw( catch try );

use base qw( Class::Accessor Test::Builder::Module );

__PACKAGE__->mk_ro_accessors(qw(
        root_path users keep_files verbose start_port end_port retry_count
        port server_pid
    ));

#------------------------------------------------------------------------------

sub repo_path       { shift->root_path->subdir('repo')     }
sub conf_path       { shift->repo_path->subdir('conf')     }
sub server_pid_file { shift->conf_path->file('server.pid') }
sub has_auth        { exists $_[0]->{users} }

sub url {
    my ($self) = @_;
    return $self->has_auth
            ? 'svn://localhost:' . $self->port
            : 'file://' . $self->repo_path;
}

#------------------------------------------------------------------------------

sub new {
    my ($class, %args) = @_;
    my $self = {};

    $self->{root_path}   = Path::Class::Dir->new(
                            _defined_or($args{root_path}, tempdir));
    $self->{users}       = $args{users} if exists $args{users};
    $self->{keep_files}  = _defined_or($args{keep_files}, 0);
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

    my $repo_dir = $self->repo_path;

    $self->_do_cmd("svnadmin create $repo_dir");
    if ($self->has_auth) {
        croak 'users hash must contain at least one username/password pair'
            if scalar(keys %{ $self->users }) == 0;
        $self->_setup_auth;
        $self->_spawn_server;   # this will die if it fails
    }
    return $self;
}

sub DESTROY {
    my ($self) = @_;
    $self->_kill_server if defined $self->server_pid;
    $self->root_path->rmtree unless $self->keep_files;
}

#------------------------------------------------------------------------------

sub _diag { __PACKAGE__->builder->diag(@_) }

sub _setup_auth {
    my ($self) = @_;
    my $conf_path = $self->conf_path;

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

sub _do_cmd {
    my ($self, $command) = @_;
    my $output = `$command` || $?;

    croak "'$command' failed: $output" if $?;
    _diag($command, $output) if $self->verbose;
    return $output;
}

sub _create_file {
    my $fullpath = shift;
    print {$fullpath->openw} @_;
}

sub _spawn_server {
    my ($self) = @_;

    #TODO: maybe fork and run the server in foreground mode here

    my $retry_count = $self->retry_count;
    my $base_port = $self->start_port;
    my $port_range = $self->end_port - $self->start_port + 1;
    for (1 .. $retry_count) {
        my $port = _choose_random_port($base_port, $port_range);
        my $started = 0;
        try {
            $self->_try_spawn_server($port);
            $self->{port} = $port;
            $self->{server_pid} = $self->_get_server_pid;
            _diag('Server pid ', $self->server_pid,
                  'started on port ', $self->port) if $self->verbose;
            $started = 1;
        }
        catch {
            chomp;
            if (/Address already in use/) {
                # retry if we hit a busy port
                _diag("Port $port busy") if $self->verbose;
            }
            else {
                # otherwise give up
                die $_;
            }
        };
        return 1 if $started;
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
                '-r'            => $self->repo_path->stringify,
                '--pid-file'    => $self->server_pid_file->stringify,
                '--listen-host' => 'localhost',
                '--listen-port' => $port,
              );

    my ($in, $out, $err);
    run(\@cmd, \$in, \$out, \$err)
        or die "$err";
}

sub _get_server_pid {
    my ($self) = @_;
    my $retry_count = 5;
    my $pid_filename = $self->server_pid_file;
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
    my ($self) = @_;

    my $pid = $self->server_pid;
    _diag("Killing server process [$pid]") if $self->verbose;
    kill 15, $pid;
    waitpid($pid, 0);
}

sub _read_file {
    my $fh = $_[0]->openr;
    local $/ = <$fh>;
}

1;

__END__

=pod

=head1 SYNOPSIS

    # Create a repo with no password authentication
    my $repo = Test::SVN::Repo->new;

    # or, create a repo with password authentication
    $repo = Test::SVN::Repo->new(
            users       => { joe => 'secret', fred => 'foobar' },
            keep_files  => 1,
        );

    my $repo_url = $repo->url;

=head1 DESCRIPTION

Create a temporary subversion repository for testing.

If no authentication is required, a simple on-disk repo is created.
An svnserve instance is created when authentication is required.

=head1 ATTRIBUTES

=head2 users

Hashref containing username/password pairs.

If this attribute is specified, there must be at least one user.
If you want no users, don't specify this attribute.

=head2 has_auth

True if the users attribute was specified.

=head2 root_path

Base path to create the repo. By default, a temporary directory is created,
and deleted on exit.

=head2 keep_files

Prevent root_path from being deleted.
Defaults to true if root_path is specified, false otherwise.

=head2 verbose

Verbose output.

=head2 url

URL form of repo_path.

=head2 repo_path

Local path to the SVN repository.

=head2 server_pid_file

Full path to the pid file created by svnserve.

=head2 conf_path

Full path to svnserve configuration directory.

=for Pod::Coverage BUILD DEMOLISH

=cut
