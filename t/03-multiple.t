#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 31 + ($ENV{RELEASE_TESTING} ? 1 : 0);
use Test::Exception;
require Test::NoWarnings if $ENV{RELEASE_TESTING};

use Config;
use IPC::Cmd qw( can_run run );
use IPC::Run ();

BEGIN { use_ok( 'Test::SVN::Repo' ) }


my $svn;

SKIP: {
    skip 'Subversion not installed', 30
        unless ($svn = can_run('svn'));

    note 'Multiple on-disk repos'; {

        my $repo_count = 4;
        my @repo;

        for my $i (0 .. $repo_count-1) {
            lives_ok { $repo[$i] = Test::SVN::Repo->new } '... ctor lives';
        }

        for my $i (0 .. $repo_count-1) {
            ok( run_ok($svn, 'info', $repo[$i]->url), '... is a valid repo');
        }

    }

    note 'Multiple server repos'; {

        my $repo_count = 4;
        my @repo;

        for my $i (0 .. $repo_count-1) {
            lives_ok { $repo[$i] = Test::SVN::Repo->new(users => { a => 'b' }) }
                '... ctor lives';
        }

        for my $i (0 .. $repo_count-1) {
            ok( run_ok($svn, 'info', $repo[$i]->url), '... is a valid repo');
        }

        my @pid = map { $_->server_pid } @repo;
        undef @repo;
        for my $i (0 .. $repo_count-1) {
            ok(! process_exists($pid[$i]), '... server has shutdown')
        }

    }

    note 'Multiple mixed repos'; {

        my $repo_count = 4;
        my @repo;

        for my $i (0 .. $repo_count-1) {
            my %args;
            $args{users} = { a => 'b' } if $i & 1;
            lives_ok { $repo[$i] = Test::SVN::Repo->new(%args) } '... ctor lives';
        }

        for my $i (0 .. $repo_count-1) {
            ok( run_ok($svn, 'info', $repo[$i]->url), '... is a valid repo');
        }

        my @pid = map { $_->server_pid } @repo;
        undef @repo;
        for my $i (0 .. $repo_count-1) {
            ok(! process_exists($pid[$i]), '... server has shutdown')
                if defined $pid[$i];
        }

    }

}; # end SKIP

Test::NoWarnings::had_no_warnings() if $ENV{RELEASE_TESTING};

#------------------------------------------------------------------------------

sub process_exists {
    my ($pid) = @_;
    return kill(0, $pid);
}

sub run_ok {
    my (@cmd) = @_;
    return scalar run( command => \@cmd );
}
