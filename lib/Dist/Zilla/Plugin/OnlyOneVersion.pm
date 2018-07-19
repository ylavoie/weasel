=pod

=encoding UTF-8

=head1 NAME

Dist::Zilla::Plugin::OnlyOneVersion - add a VERSION head1 to each Perl document based on $VERSION

=cut

package Dist::Zilla::Plugin::OnlyOneVersion 1.000;
# ABSTRACT: add a VERSION head1 to each Perl document, based on $VERSION

use Moose;
with(
  'Dist::Zilla::Role::FileMunger',
  'Dist::Zilla::Role::FileFinderUser' => {
    default_finders => [ ':InstallModules', ':ExecFiles' ],
  },
);

our $VERSION = '1.000';

has version_prefix => (is => 'ro', isa => 'Str', default => 'Version ');

use namespace::autoclean;
use List::Util qw(any first);

=head1 SYNOPSIS

Enable the plugin by putting the following in your dist.ini
[OnlyOneVersion]
version_prefix = Text to prepend to the version in the pod section

=head1 DESCRIPTION

This plugin adds a C<=head1 VERSION> section to most perl files in the
distribution, indicating the version of the dist being built.  This section is
added after C<=head1 NAME>.  If there is no such section, the version section
will not be added.

The version in POD will be set from the $VERSION variable.

This package is inspired from the excellent L<PodVersion|Dist::Zilla::Plugin::PodVersion>
by Ricardo SIGNES.

=head1 SUBROUTINES/METHODS

=over

=item munge_file($file)

Munge a specific file

=cut

sub munge_file {
  my ($self, $file) = @_;

  my @content = split /\n/x, $file->content;

#  List::Util->VERSION('1.33');
  if (any(sub { return /^=head1 VERSION\b/x }, @content)) {
    $self->log($file->name . ' already has a VERSION section in POD');
    return;
  }
  my $version;
  if (any(sub { return /^our\s\$VERSION\s*=\s*'(.+)'\s*;/x }, @content)) {
    $version = first {/^our\s\$VERSION\s*=\s*'(.+)'\s*;/x} @content;
    $self->log($file->name . " VERSION variable defined to $VERSION");
  } else {
    ## no critic(RequireInterpolationOfMetachars)
    $self->log($file->name . ' no $VERSION variable defined');
    return;
  }

  for (0 .. $#content) {
    ## no critic(ProhibitPostfixControls)
    next until $content[$_] =~ /^=head1\s+NAME/x;

    $_++; # move past the =head1 line itself
    $_++ while $content[$_] =~ /^\s*$/x;

    $_++ while $content[$_] !~ /^\s*$/x; # move past the abstract
    $_++ while $content[$_] =~ /^\s*$/x;
    ## critic(ProhibitPostfixControls)

    splice @content, $_ - 1, 0, (
      q{},
      '=head1 VERSION',
      q{},
      $self->version_prefix . $version . q{},
    );

    $self->log_debug([ 'adding VERSION Pod section to %s', $file->name ]);

    my $content = join "\n", @content;
    $content .= "\n" if length $content;
    $file->content($content);
    return;
  }

  $self->log([
    q{couldn't find '=head1 NAME' in %s, not adding '=head1 VERSION'},
    $file->name,
  ]);
  return;
}

=back
=cut

__PACKAGE__->meta->make_immutable;
1;

__END__

=head1 SEE ALSO

Core Dist::Zilla plugins:
L<PodVersion|Dist::Zilla::Plugin::PodVersion>,
L<PkgVersion|Dist::Zilla::Plugin::PkgVersion>,
L<AutoVersion|Dist::Zilla::Plugin::AutoVersion>,
L<NextRelease|Dist::Zilla::Plugin::NextRelease>.

=head1 AUTHOR

Yves Lavoie 😏 <ylavoie@yveslavoie.com>

=head1 DEPENDENCIES


=head1 BUGS AND LIMITATIONS


=head1 SOURCE


=head1 LICENSE AND COPYRIGHT

This software is copyright (c) 2018 by Yves Lavoie.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

