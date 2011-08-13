#!/usr/bin/env perl

use Test::Most;

use POSIX ":sys_wait_h";

BEGIN { use_ok( 'Test::SVN::Repo' ) }

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
    is(waitpid($pid, WNOHANG), -1, '... server has shutdown')
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

note 'SVN binaries not available'; {
    local $ENV{PATH} = '';
    dies_ok { Test::SVN::Repo->new( users => \%users ) }
        '... ctor dies if svnadmin cannot be found';
}

done_testing();
