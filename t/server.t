#!/usr/bin/env perl

use Test::More tests => 17;
use Test::Exception;

use IPC::Run ();

use POSIX ":sys_wait_h";

BEGIN { use_ok( 'Test::SVN::Repo' ) }

SKIP: {
    skip 'Subversion not installed', 16
        unless can_run('svn');

    my %users = ( userA => 'passA', userB => 'passB' );

    note 'Basic sanity checks'; {
        my $repo;
        lives_ok { $repo = Test::SVN::Repo->new( users => \%users ) }
            '... ctor lives';
        isa_ok($repo, 'Test::SVN::Repo', '...');
        like($repo->url, qr(^svn://), '... url is svn://');
        is(system('svn', 'info', $repo->url), 0, '... is a valid repo');

        my $pid = $repo->server_pid;
        undef $repo;
        ok(! process_exists($pid), '... server has shutdown')
    }

    note 'Check authentication'; {
        my $repo = Test::SVN::Repo->new( users => \%users );

        my $tempdir = $repo->root_path->subdir('test');
        my $file = create_file($tempdir->file('test.txt'), 'Test');

        my @cmd = qw( svn import --non-interactive --no-auth-cache );
        is(system(@cmd, '-m', 'import no auth', $tempdir, $repo->url),
            256, '... import without auth fails okay');

        is(system(@cmd, '-m', 'import bad user',
                '--username' => 'unknown', '--password' => 'wrong',
                $tempdir, $repo->url), 256, '... unknown user rejected');

        is(system(@cmd, '-m', 'import bad password',
                '--username' => 'userA', '--password' => 'wrong',
                $tempdir, $repo->url), 256, '... bad password rejected');

        for my $user (keys %users) {
            my $pass = $users{$user};
            is(system(@cmd, '-m', 'import correct auth',
                '--username' => $user, '--password' => $pass,
                create_file($tempdir->file($user, $user . '.txt'), $user)->dir,
                $repo->url), 0, '... correct auth succeeds');
        }
    }

    note 'Port range tests'; {
        my $repo = Test::SVN::Repo->new( users      => \%users,
                                        start_port => 50000,
                                        end_port   => 60000 );
        my $port = $repo->port;
        ok($port >= $repo->start_port, '... port is within specified range');
        ok($port <= $repo->end_port,   '... port is within specified range');

        # Try creating a server on a port we know is taken
        my $retry_count = 5;
        throws_ok { Test::SVN::Repo->new( users       => \%users,
                                        start_port  => $port,
                                        end_port    => $port,
                                        retry_count => $retry_count ) }
            qr/Giving up after $retry_count attempts/,
            '... server gives up if no ports available';
    }

    note 'Check that svnserve gets cleaned up'; {
        my $code = <<'END';
my $repo = Test::SVN::Repo->new( users => { a => 'b' } );
print $repo->server_pid, "\n";
1 while 1;
END

        # Spawn a sub-process that starts a server.
        my @cmd = ( qw( perl -MTest::SVN::Repo -e ), $code);
        my ($in, $out, $err);
        my $h = IPC::Run::start(\@cmd, \$in, \$out, \$err);

        # Obtain the server pid
        $h->pump;
        my $pid = $out;
        chomp $pid;

        # Kill the sub-process
        $h->signal(15);
        $h->finish;

        # Check that the server (grandchild process) has exited
        ok(! process_exists($pid), '... svnserve process has shutdown')
    }

    note 'Verbose mode'; {
        lives_ok { Test::SVN::Repo->new( users => \%users, verbose => 1 ) }
            '... ctor lives';
    }

}; # end SKIP

#------------------------------------------------------------------------------

sub can_run {
    my (@cmd) = @_;
    return (system(@cmd) != -1);
}

sub create_file {
    my ($path, @data) = @_;
    $path->dir->mkpath;
    print {$path->openw} @_;
    return $path;
}

sub process_exists {
    my ($pid) = @_;
    return kill(0, 0+$pid);
}
