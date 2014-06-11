# NAME

Test::SVN::Repo - Subversion repository fixtures for testing

# VERSION

version 0.016

# SYNOPSIS

    # Create a plain on-disk repo
    my $repo = Test::SVN::Repo->new;

    # Create a repo with password authenticated server
    $repo = Test::SVN::Repo->new(
            users => { joe => 'secret', fred => 'foobar' },
        );

    my $repo_url = $repo->url;

    # do stuff with your new repo
    system("svn co --username joe --password secret $repo_url");

# DESCRIPTION

Create temporary subversion repositories for testing.

If no authentication is required, a simple on-disk repo is created.
An svnserve instance is created when authentication is required.

Repositories and servers are cleaned up when the object is destroyed.

Requires the `svnadmin` and `svnserve` external binaries. These are both
included in standard Subversion releases.

# METHODS

## CONSTRUCTOR

Creates a new svn repository, spawning an svnserve server if authentication
is required.

Arguments. All are optional.

- users

    Hashref containing username/password pairs for repository authentication.

    If this attribute is specified, there must be at least one user.
    Specifying users causes an svnserve instance to be created.

- root\_path

    Base path to create the repo. By default, a temporary directory is created,
    and deleted on exit.

- keep\_files

    Prevent root\_path from being deleted in the destructor.

    If root\_path is provided in the constructor, it will be preserved by default.
    If no root\_path is provided, and a temporary directory is created, it will
    be destroyed by default.

- verbose

    Verbose output. Default off.

- start\_port end\_port retry\_count

    Server mode only.

    In order to find a free port for the server, ports are randomly selected from
    the range \[start\_port, end\_port\] until one succeeds. Gives up after retry\_count
    failures.

    Default values: 1024, 65536, 1000

## READ-ONLY ACCESSORS

### url

Repository URL.

### repo\_path

Local path to the SVN repository.

### is\_authenticated

True if the the svn repo requires authorisation.
This is enabled by supplying a users hashref to the constructor.

### server\_pid

Process id of the svnserve process.

### server\_port

Listen port of the svnserve process.

# ACKNOWLEDGEMENTS

Thanks to Strategic Data for sponsoring the development of this module.

# AUTHOR

Stephen Thirlwall <sdt@cpan.org>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by Stephen Thirlwall.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
