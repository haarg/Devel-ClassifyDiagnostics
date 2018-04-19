package Devel::ClassifyDiagnostics;
use strict;
use warnings;

our $VERSION = '0.001000';
$VERSION = eval $VERSION;

use Config;
use Exporter; *import = \&Exporter::import;

our @EXPORT_OK = qw(diagnostics warning_categories warning_like_category);

my $bits = \%warnings::Bits;

my %E_codes = (
  lt      => '<',
  gt      => '>',
  verbar  => '|',
  sol     => '/',
  quot    => '"',
  amp     => '&',
);
sub _pod_to_text {
  my $pod = shift;
  my @parts = split /([IBCFSZLE])(?:<<<<\s+(.*?)\s+>>>>|<<<\s+(.*?)\s+>>>|<<\s+(.*?)\s+>>|<(.*?)>)/s, $pod;
  my $out = '';
  while (@parts) {
    $out .= shift @parts;
    if (@parts) {
      my $code = shift @parts;
      my ($text) = grep defined, splice @parts, 0, 4;
      if ($code eq 'E') {
        $out .= $E_codes{$text} || (
            $text =~ /^0x([0-9a-f]+)$/i ? chr(hex($1))
          : $text =~ /^[0-9]+$/         ? chr($text)
          : die "can't parse E<$text> code"
        );
        next;
      }
      elsif ($code eq 'L') {
        my ($t, $l, $s) = $text =~ m{^(?:(.*?)\|)?(\w+:.*|.*?)(?:/(.*?))?$}s;
        ($text) = grep defined, $t, $s, $l;
      }
      elsif ($code eq 'X') {
        next;
      }
      $out .= _pod_to_text($text);
    }
  }
  $out;
}

my %TYPE_MAP = (
  W => 'warning',
  D => 'warning',
  S => 'warning',
  F => 'error',
  P => 'internal',
  X => 'error',
  A => 'alien',
);
my %TYPE_CAT = (
  D => 'deprecated',
  S => 'severe',
);

sub read_perldiag {
  my $perldiag = shift;
  my @diag;
  local $_ = do {
    open my $fh, '<', $perldiag or die "can't open $perldiag: $!";
    local $/; <$fh>
  };
  s/\r\n?/\n/g;

  my $over_level = 0;
  my @headers;
  while (1) {
    if ( m/\G^=(\w+)(.*\n(?:.+\n)*)/mgc ) {
      my ($directive, $text) = ($1, $2);
      if ($directive eq 'begin') {
        m/^=end\b(.*\n(?:.+\n)*)/gcm
          or last;
      }
      elsif ($directive eq 'over') {
        $over_level++;
      }
      elsif ($directive eq 'back') {
        $over_level--;
        if ($over_level == 0) {
          @headers = ();
        }
      }
      elsif ($over_level == 1 && $directive eq 'item') {
        my $header = _pod_to_text($text);
        $header =~ s/^\s+//;
        $header =~ s/\s*$//;
        $header =~ s/\.$//;
        my @parts = split /(%l?[dxX]|%[ucp]|%(?:\.\d+)?[fs]|\s+)/, $header;
        my $match = join '', map {
            /^%c$/          ? '.'
          : /^%(?:d|u)$/    ? '\d+'
          : /^%(?:s|.*f)$/  ? '.*'
          : /^%.(\d+)s/     ? ".{$1}"
          : /^%l*[px]$/     ? '[\da-f]+'
          : /^%l*X$/        ? '[\dA-F]+'
          : /^\s+$/         ? '\s+'
                            : quotemeta;
        } @parts;
        $match =~ s/\.\*\z//;
        push @headers, {
          message => $header,
          match => qr/$match/,
        };
      }
      else {
        @headers = ();
      }
    }
    elsif ( m/\G(.+?)(?=^=|\z)/gcms ) {
      my $pod = $1;
      my @messages = @headers
        or next;
      @headers = ();
      my %types;
      $pod =~ s/\A\s+//;
      while ($pod =~ s/\A\(([WDSFPXA])(?:\s+([^\)]+))?\)\s*//ms) {
        my ($type, $type_cat, $cat) = ($TYPE_MAP{$1}, $TYPE_CAT{$1}, $2);
        my %seen;
        $types{$type} ||= [];
        @{ $types{$type} } =
          grep !$seen{$_}++,
          @{ $types{$type} },
          map { s/^\s+//, s/\s+$//; $_ }
          map { split /,/ }
          grep defined,
          $cat, $type_cat;
      }
      for my $message (@messages) {
        push @diag, map {;
          +{
            %$message,
            type        => $_,
            categories  => [ @{$types{$_}} ],
            pod         => $pod,
            text        => _pod_to_text($pod),
          };
        } sort keys %types;
      }
    }
    else {
      last;
    }
  }
  return @diag;
}

our $PERLDIAG = "$Config{privlibexp}/pods/perldiag.pod";
our $DIAGNOSTICS;
sub diagnostics () {
  @{ $DIAGNOSTICS ||= [ read_perldiag($PERLDIAG) ] };
}

sub warning_categories {
  my ($warning) = @_;

  my %seen;
  grep !$seen{$_}++,
    map @{$_->{categories}},
    grep $_->{type} eq 'warning' && $warning =~ $_->{match},
    diagnostics;
}

sub warning_like_category {
  my ($warning, $category) = @_;
  return
    unless $warning;
  my $category_bits = $bits->{$category} or return;
  !!grep { ($bits->{$_} & $category_bits) eq $bits->{$_} }
    warning_categories($warning);
}

1;
__END__

=head1 NAME

Devel::ClassifyDiagnostics - Classify perl diagnostic messages

=head1 SYNOPSIS

  use Devel::ClassifyDiagnostics qw(
    diagnostics
    warning_categories
    warning_like_category
  );

=head1 DESCRIPTION

This module allows you to classify diagnostics emitted by perl as their type
(warning or error) and the warning category.  This is based on the information
in L<perldiag>.

This module provides a programmatic interface to the L<perldiag> data, rather
than being only usable interactively like L<diagnostics>.

=head1 FUNCTIONS

=head2 diagnostics

  my @diagnostics = diagnostics;

Returns an array of diagnostics.  Each diagnostic is a hashref with the
following keys:

=over 4

=item message

The diagnostic message as shown in perldiag.  This may have placeholders like
C<%s> to indicate variable parts of the message.

=item match

A regular expression that can be used to match against a full diagnostic message
output by perl.

=item type

The type of diagnostic. This will be one of C<warning>, C<error>, C<internal>,
or C<alien>.

=item categories

For warnings, this will be an arrayref of categories the warning belongs to.

=item pod

The descriptive pod of the diagnostic, as listed in L<perldiag>.

=item text

The descriptive pod of the diagnostic, but with Pod formatting codes converted
to plain text.

=back

=head2 warning_categories

  warning_categories('Use of -l on filehandle $fh at perl_script.pl line 45.')

Returns a list of categories for a given warning string.  This will be the
specific categories listed in L<perldiag>, not including wider categories that
also include the warning.

=head2 warning_like_category

  warning_like_category('Use of -l on filehandle $fh at perl_script.pl line 45.', 'io')

Given a warning and a category, returns true if the warning is inside that
category.

=head2 read_perldiag

Not exportable.  Given the filename of a F<perldiag.pod>-like file, returns an
array of diagnostics with the same structure of the L</diagnostics> function.

=head1 SEE ALSO

=over 4

=item * L<diagnostics>

=back

=head1 AUTHOR

haarg - Graham Knop (cpan:HAARG) <haarg@haarg.org>

=head1 CONTRIBUTORS

None yet.

=head1 COPYRIGHT

Copyright (c) 2014 the Devel::ClassifyDiagnostics L</AUTHOR> and L</CONTRIBUTORS>
as listed above.

=head1 LICENSE

This library is free software and may be distributed under the same terms
as perl itself.

=cut
