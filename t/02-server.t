#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 30 + ($ENV{RELEASE_TESTING} ? 1 : 0);
use Test::Exception;
require Test::NoWarnings if $ENV{RELEASE_TESTING};

use IPC::Cmd qw( can_run run );
use IPC::Run ();
use Probe::Perl;

BEGIN { use_ok( 'Test::SVN::Repo' ) }

my $svn;

SKIP: {
    skip 'Subversion not installed', 29
        unless ($svn = can_run('svn'));

    my %users = ( userA => 'passA', userB => 'passB' );

    note 'Basic sanity checks'; {
        my $repo;
        lives_ok { $repo = Test::SVN::Repo->new( users => \%users ) }
            '... ctor lives';
        isa_ok($repo, 'Test::SVN::Repo', '...');
        like($repo->url, qr(^svn://), '... url is svn://');
        ok( run_ok($svn, 'info', $repo->url), '... is a valid repo');

        my $pid = $repo->server_pid;
        ok(process_exists($pid), '... server is running');
        undef $repo;
        ok(! process_exists($pid), '... server has shutdown')
    }

    note 'Check authentication'; {
        my $repo = Test::SVN::Repo->new( users => \%users );

        my $tempdir = $repo->root_path->subdir('test');
        my $file = create_file($tempdir->file('test.txt'), 'Test');

        my @cmd = qw( svn import --non-interactive --no-auth-cache );
        ok( ! run_ok(@cmd, '-m', 'import no auth', $tempdir, $repo->url),
            '... import without auth fails okay');

        ok( ! run_ok(@cmd, '-m', 'import bad user',
                '--username' => 'unknown', '--password' => 'wrong',
                $tempdir, $repo->url), '... unknown user rejected');

        ok( ! run_ok(@cmd, '-m', 'import bad password',
                '--username' => 'userA', '--password' => 'wrong',
                $tempdir, $repo->url), '... bad password rejected');

        for my $user (keys %users) {
            my $pass = $users{$user};
            ok(run_ok(@cmd, '-m', 'import correct auth',
                '--username' => $user, '--password' => $pass,
                create_file($tempdir->file($user, $user . '.txt'), $user)->dir,
                $repo->url), '... correct auth succeeds');
        }
    }

SKIP: {
    skip 'Not valid for Win32', 18
       if $^O eq 'MSWin32';

    note 'Port range tests'; {

        # This mysteriously doesn't work on win32.
        # I can manually start multiple svnserve instances on a single port.
        # Its as if they get queued up - the first one serves the requests,
        # and the second takes over once the first has exited.

        my $repo = Test::SVN::Repo->new( users      => \%users,
                                         start_port => 50000,
                                         end_port   => 60000 );
        my $port = $repo->server_port;
        ok($port >= $repo->start_port, '... port is within specified range');
        ok($port <= $repo->end_port,   '... port is within specified range');

        # Try creating a server on a port we know is taken
        my $retry_count = 5;
        throws_ok { Test::SVN::Repo->new(users       => \%users,
                                         start_port  => $port,
                                         end_port    => $port,
                                         retry_count => $retry_count ) }
            qr/Giving up after $retry_count attempts/,
            '... server gives up if no ports available';
    }

    note 'Check that svnserve gets cleaned up'; {

        # Killing the child process doesn't seem to work on win32.
        # IPC::Run confirms this behaviour. Processes can only be KILLED
        # under win32.

        for my $signame (qw( HUP INT QUIT TERM )) {
            my $pid;
            lives_ok { $pid = spawn_and_signal($signame) }
                '... child process started okay';

            like($pid, qr/^\d+$/, '... got valid pid for server process');

            # Check that the server (grandchild process) exits if we
            # kill its parent
            ok(! process_exists($pid), '... svnserve process has shutdown after receiving signal ' . $signame)
        }
    }

    note 'Forking'; {

        my $repo = Test::SVN::Repo->new( users => \%users );
        ok(run_ok($svn, 'info', $repo->url), '... server is alive');

        lives_ok {
            my $pid = fork;
            die unless defined $pid;
            if ($pid) {
                waitpid($pid, 0);
            }
            else {
                exit 0;
            }
        } '... created child process';

        my $ok;
        ok($ok = run_ok($svn, 'info', $repo->url), '... server is still alive');

        # This is a hack so that we don't hang if the test fails
        delete $repo->{server} unless $ok;
    }

}; # end SKIP Win32
}; # end SKIP no svn

Test::NoWarnings::had_no_warnings() if $ENV{RELEASE_TESTING};

#------------------------------------------------------------------------------

sub create_file {
    my ($path, @data) = @_;
    $path->dir->mkpath;
    print {$path->openw} @_;
    return $path;
}

sub process_exists {
    my ($pid) = @_;
    return kill(0, $pid);
}

sub run_ok {
    my (@cmd) = @_;
    return scalar run( command => \@cmd );
}

sub spawn_and_signal {
    my ($signal) = @_;

    my $code = <<'END';
my $repo = Test::SVN::Repo->new( users => { a => 'b' } );
$| = 1;
print $repo->server_pid, "\n";
1 while 1;
END

    # Spawn a child process that starts a server (grandchild process).
    my $perl = Probe::Perl->find_perl_interpreter;
    my @cmd = ( $perl, '-MTest::SVN::Repo', '-e' => $code);
    my ($in, $out, $err);
    my $h = IPC::Run::start(\@cmd, \$in, \$out, \$err);

    # Obtain the server pid (grandchild)
    my $pid;
    while (not $pid) {
        die "Child process has died: $err" if not $h->pumpable;
        $h->pump;
        $pid = $out;
        chomp $pid;
    }

    # Kill the child process
    $h->signal($signal);
    $h->finish;

    return $pid;
}
