## NAME

Test::SVN::Repo - Authenticated subversion repositories for testing

## VERSION

version 0.001

## SYNOPSIS

    # Create a repo with no password authentication
    my $repo = Test::SVN::Repo->new;

    # or, create a repo with password authentication
    $repo = Test::SVN::Repo->new(
            users       => { joe => 'secret', fred => 'foobar' },
            keep_files  => 1,
        );

    my $repo_url = $repo->url;

## DESCRIPTION

Create a temporary subversion repository for testing.

Password authentication is available is required.

## ATTRIBUTES

### users

Hashref containing username/password pairs.

If this attribute is specified, there must be at least one user.
If you want no users, don't specify this attribute.

### has_auth

True if the users attribute was specified.

### root_path

Base path to create the repo. By default, a temporary directory is created,
and deleted on exit.

### keep_files

Prevent root_path from being deleted.
Defaults to true if root_path is specified, false otherwise.

### verbose

Verbose output.

### url

URL form of repo_path.

### repo_path

Local path to the SVN repository.

### server_pid_file

Full path to the pid file created by svnserve.

### conf_path

Full path to svnserve configuration directory.

## AUTHOR

Stephen Thirlwall <sdt@cpan.org>

## COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Stephen Thirlwall.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
