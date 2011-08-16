#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 23;
use Test::Exception;
use Test::NoWarnings;

use File::Temp  qw( tempdir );
use IPC::Cmd    qw( can_run run );
use Path::Class ();

BEGIN { use_ok( 'Test::SVN::Repo' ) }

my $svn;

SKIP: {
    skip 'Subversion not installed', 21
        unless ($svn = can_run('svn'));

    note 'Basic sanity checks'; {
        my $repo;
        lives_ok { $repo = Test::SVN::Repo->new } '... ctor lives';
        isa_ok($repo, 'Test::SVN::Repo', '...');
        like($repo->url, qr(^file://), '... url is file://');
        ok( my $ok = run( command => [ $svn, 'info', $repo->url ] ),
            '... is a valid repo');
    }

    note 'Automatic temporary directory handling with cleanup'; {
        my $repo = Test::SVN::Repo->new;
        my $path = $repo->root_path;

        ok(-d $path, '... root path exists');
        ok(scalar($path->children) > 0, '... root path is non-empty');

        undef $repo;
        ok(! -d $path, '... ! -d root path got cleaned up');
    }

    note 'Automatic temporary directory handling no cleanup'; {
        my $repo = Test::SVN::Repo->new( keep_files => 1 );
        my $path = $repo->root_path;

        ok(-d $path, '... root path exists');
        ok(scalar($path->children) > 0, '... root path is non-empty');

        undef $repo;
        ok(-d $path, '... root path still exists');
        ok(scalar($path->children) > 0, '... root path is non-empty');

        $path->rmtree;
    }

    note 'Manual temporary directory handling with cleanup'; {
        my $tempdir = tempdir();
        my $repo = Test::SVN::Repo->new ( root_path => $tempdir );
        my $path = $repo->root_path;

        is($tempdir, $path->stringify, '... manual path is the one used');
        ok(-d $path, '... root path exists');
        ok(scalar($path->children) > 0, '... root path is non-empty');

        undef $repo;
        ok(! -d $path, '... ! -d root path got cleaned up');
    }

    note 'Manual temporary directory handling without cleanup'; {
        my $tempdir = tempdir();
        my $repo = Test::SVN::Repo->new ( root_path => $tempdir, keep_files => 1 );
        my $path = $repo->root_path;

        is($tempdir, $path->stringify, '... manual path is the one used');
        ok(-d $path, '... root path exists');
        ok(scalar($path->children) > 0, '... root path is non-empty');

        undef $repo;
        ok(-d $path, '... root path still exists');
        ok(scalar($path->children) > 0, '... root path is still non-empty');

        $path->rmtree;
    }

    note 'Verbose mode'; {
        lives_ok { Test::SVN::Repo->new( verbose => 1 ) }
            '... ctor lives';
    }

}; # end SKIP
