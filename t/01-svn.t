#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 1;
use File::Temp;

use Config;
use IPC::Cmd qw( can_run );
use IPC::Run qw( run );

my %path;

for my $cmd (qw( svn svnadmin svnserve )) {
    BAIL_OUT("Cannot find $cmd - is Subversion installed?")
        unless $path{$cmd} = can_run($cmd);
}

my $temp = File::Temp::newdir('temp.XXXX',
                              CLEANUP => 1, EXLOCK => 0, TMPDIR => 1);

BAIL_OUT('Cannot create test repo - is Subversion installed correctly?')
    unless run([ $path{svnadmin}, 'create', $temp ]);

my ($in, $out, $err);
BAIL_OUT('Cannot start svn server - is Subversion installed correctly?')
    unless run([ $path{svnserve}, '-i', '-r' => $temp, '--foreground' ],
               \$in, \$out, \$err);

ok(1, 'Subversion installation looks good');

done_testing();
