package App::Cache;
use strict;
use File::Find::Rule;
use File::HomeDir;
use File::stat;
use HTTP::Cookies;
use LWP::UserAgent;
use Path::Class;
use Storable qw(nstore retrieve);
use base qw( Class::Accessor::Chained::Fast );
__PACKAGE__->mk_accessors(qw( application directory ttl ));
our $VERSION = '0.35';

sub new {
  my $class = shift;
  my $self  = $class->SUPER::new(@_);

  unless ($self->application) {
    my $caller = (caller)[0];
    $self->application($caller);
  }

  my $directory = dir(home(), "." . $self->_clean($self->application), "cache");
  $self->directory($directory);

  my $topdirectory = dir(home(), "." . $self->_clean($self->application));
  unless (-d $topdirectory) {
    mkdir($topdirectory) || die "Error mkdiring $topdirectory: $!";
  }

  unless (-d $directory) {
    mkdir($directory) || die "Error mkdiring $directory: $!";
  }

  return $self;
}

sub clear {
  my $self = shift;
  foreach my $filename (File::Find::Rule->new->file->in($self->directory)) {
    unlink($filename) || die "Error unlinking $filename: $!";
  }
  foreach my $dirname (sort { length($b) <=> length($a) }
    File::Find::Rule->new->directory->in($self->directory))
  {
    next if $dirname eq $self->directory;
    rmdir($dirname) || die "Error unlinking $dirname: $!";
  }
}

sub delete {
  my ($self, $key) = @_;
  my $filename = $self->_clean_filename($key);
  return unless -f $filename;
  unlink($filename) || die "Error unlinking $filename: $!";
}

sub get {
  my ($self, $key) = @_;
  my $ttl = $self->ttl || 60 * 30;               # default ttl of 30 minutes
  my $filename = $self->_clean_filename($key);
  return undef unless -f $filename;
  my $now   = time;
  my $stat  = stat($filename) || die "Error stating $filename: $!";
  my $ctime = $stat->ctime;
  my $age   = $now - $ctime;
  if ($age < $ttl) {
    my $value = retrieve("$filename")
      || die "Error reading from $filename: $!";
    return $value->{value};
  } else {
    $self->delete($key);
    return undef;
  }
}

sub get_code {
  my ($self, $key, $code) = @_;
  my $data = $self->get($key);
  unless ($data) {
    $data = $code->();
    $self->set($key, $data);
  }
  return $data;
}

sub get_url {
  my ($self, $url) = @_;
  my $data = $self->get($url);
  unless ($data) {
    my $ua       = LWP::UserAgent->new;
    $ua->cookie_jar(HTTP::Cookies->new());
    my $response = $ua->get($url);
    if ($response->is_success) {
      $data = $response->content;
    } else {
      die "Error fetching $url: " . $response->status_line;
    }
    $self->set($url, $data);
  }
  return $data;
}

sub scratch {
  my $self      = shift;
  my $directory = $self->_clean_filename("_scratch");
  unless (-d $directory) {
    mkdir($directory) || die "Error mkdiring $directory: $!";
  }
  return $directory;
}

sub set {
  my ($self, $key, $value) = @_;
  my $filename = $self->_clean_filename($key);
  nstore({ value => $value }, "$filename")
    || die "Error writing to $filename: $!";
}

sub _clean {
  my ($self, $text) = @_;
  $text = lc $text;
  $text =~ s/[^a-z0-9]+/_/g;
  return $text;
}

sub _clean_filename {
  my ($self, $key) = @_;
  $key = $self->_clean($key);
  my $filename = file($self->directory, $key);
  return $filename;
}

1;

__END__

=head1 NAME

App::Cache - Easy application-level caching

=head1 SYNOPSIS

  # in your class:
  my $cache = App::Cache->new({ ttl => 60*60 });
  $cache->delete('test');
  my $data = $cache->get('test');
  my $code = $cache->get_code("code", sub { $self->calculate() });
  my $html = $cache->get_url("http://www.google.com/");
  $cache->set('test', 'one');
  $cache->set('test', { foo => 'bar' });
  my $scratch = $cache->scratch;
  $cache->clear;

=head1 DESCRIPTION

The L<App::Cache> module lets an application cache data locally. There
are a few times an application would need to cache data: when it is
retrieving information from the network or when it has to complete a
large calculation.

For example, the L<Parse::BACKPAN::Packages> module downloads a file off
the net and parses it, creating a data structure. Only then can it
actually provide any useful information for the programmer.
L<Parse::BACKPAN::Packages> uses L<App::Cache> to cache both the file
download and data structures, providing much faster use when the data is
cached.

This module stores data in the home directory of the user, in a dot
directory. For example, the L<Parse::BACKPAN::Packages> cache is
actually stored underneath "~/.parse_backpan_packages/cache/". This is
so that permisssions are not a problem - it is a per-user,
per-application cache.

=head1 METHODS

=head2 new

The constructor creates an L<App::Cache> object. It takes two optional
parameters: a ttl parameter which contains the number of seconds in
which a cache entry expires, and an application parameter which
signifies the application name. If you are calling new() from a class,
the application is automagically set to the calling class, so you should
rarely need to pass it in:

  my $cache = App::Cache->new({ ttl => 60*60 });

=head2 clear

Clears the cache:

  $cache->clear;
  
=head2 delete

Deletes an entry in the cache:

  $cache->delete('test');
  
=head2 get

Gets an entry from the cache. Returns undef if the entry does not exist
or if it has expired:

  my $data = $cache->get('test');
  
=head2 get_code

This is a convenience method. Gets an entry from the cache, but if the
entry does not exist, set the entry to the value of the code reference
passed:

  my $code = $cache->get_code("code", sub { $self->calculate() });

=head2 get_url

This is a convenience method. Gets the content of a URL from the cache,
but if the entry does not exist, set the entry to the content of the URL
passed:

  my $html = $cache->get_url("http://www.google.com/");

=head2 scratch

Returns a directory in the cache that the application may use for
scratch files:

  my $scratch = $cache->scratch;

=head2 set

Set an entry in the cache. Note that an entry value may be an arbitrary
Perl data structure:

  $cache->set('test', 'one');
  $cache->set('test', { foo => 'bar' });

=head1 AUTHOR

Leon Brocard <acme@astray.com>

=head1 COPYRIGHT

Copyright (C) 2005-7, Leon Brocard

=head1 LICENSE

This module is free software; you can redistribute it or modify it under
the same terms as Perl itself.
