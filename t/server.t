#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 24;
use Test::Exception;
use Test::NoWarnings;

use Config;
use IPC::Cmd qw( can_run run );
use IPC::Run ();

BEGIN { use_ok( 'Test::SVN::Repo' ) }

my %sig_num;
@sig_num{split ' ', $Config{sig_name}} = split ' ', $Config{sig_num};

my $svn;

SKIP: {
    skip 'Subversion not installed', 22
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

    note 'Port range tests'; {
        my $repo = Test::SVN::Repo->new( users      => \%users,
                                        start_port => 50000,
                                        end_port   => 60000 );
        my $port = $repo->server_port;
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

        for my $signame (qw( HUP INT QUIT TERM )) {
            my $pid = spawn_and_signal($sig_num{$signame});

            like($pid, qr/^\d+$/, '... got valid pid for server process');

            # Check that the server (grandchild process) exits if we
            # kill its parent
            ok(! process_exists($pid), '... svnserve process has shutdown after receiving signal ' . $signame)
        }
    }

    note 'Verbose mode'; {
        lives_ok { Test::SVN::Repo->new( users => \%users, verbose => 1 ) }
            '... ctor lives';
    }

}; # end SKIP

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
    my @cmd = ( qw( perl -MTest::SVN::Repo -e ), $code);
    my ($in, $out, $err);
    my $h = IPC::Run::start(\@cmd, \$in, \$out, \$err);

    # Obtain the server pid (grandchild)
    my $pid;
    while (not $pid) {
        $h->pump;
        $pid = $out;
        chomp $pid;
    }

    # Kill the child process
    $h->signal($signal);
    $h->finish;

    return $pid;
}
