#!/usr/bin/env perl

use Test::Most;

use File::Temp  qw( tempdir );
use Path::Class ();

BEGIN { use_ok( 'Test::SVN::Repo' ) }

note 'Basic sanity checks'; {
    my $repo;
    lives_ok { $repo = Test::SVN::Repo->new } '... ctor lives';
    isa_ok($repo, 'Test::SVN::Repo', '...');
    like($repo->url, qr(^file://), '... url is file://');
    is(system('svn', 'info', $repo->url), 0, '... is a valid repo')
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

done_testing();
