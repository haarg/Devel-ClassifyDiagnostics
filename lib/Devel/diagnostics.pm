package Devel::diagnostics;
BEGIN {
  # detect -d:diagnostics and disable the debugger features.  we don't actually
  # need them.
  if (!defined &DB::DB && $^P & 0x02) {
    $^P = 0;
  }
}

use strict;
use warnings;
use Devel::ClassifyDiagnostics qw(diagnostics);

my $bits = \%warnings::Bits;

my $OLD_WARN;
my $OLD_DIE;

my $pretty;

sub import {
  my $class = shift;
  for (@_) {
    if (/^--?d(ebug)?$/) {
    }
    elsif (/^--?v(erbose)?$/) {
    }
    elsif (/^--?p(retty)?$/) {
      $pretty = 1;
    }
    elsif (/^--?t(race(only)?)?$/) {
    }
    elsif (/^--?w(arntrace)?$/) {
    }
    else {
      warn "Unknown flag: $_";
    }
  }

  $OLD_WARN = _find_sig($SIG{__WARN__})
    unless defined $SIG{__WARN__} && $SIG{__WARN__} eq \&_warn;
  $OLD_DIE = _find_sig($SIG{__DIE__})
    unless defined $SIG{__DIE__} && $SIG{__DIE__} eq \&_die;

  $SIG{__WARN__} = \&_warn;
  $SIG{__DIE__} = \&_die;
}

sub _find_sig {
  my $sig = $_[0];
  return undef
    if !defined $sig;
  return undef
    if $sig eq 'DEFAULT' || $sig eq 'IGNORE';
  local $@;
  return $sig
    if ref $sig && eval { \&{$sig} };
  package #hide
    main;
  no strict 'refs';
  defined &{$sig} ? \&{$sig} : undef;
}

sub _warn {
  my $message = _splain(@_);
  if ($OLD_WARN) {
    $OLD_WARN->($message);
  }
  else {
    print STDERR $message;
  }
}

sub _die {
  my $error = $_[0];
  if (!$^S && !ref $error) {
    $error = _splain($error);
  }

  $OLD_DIE->($error)
    if $OLD_DIE;
  die $error;
}

sub _diagnostics {
  my $message = shift;
  $message =~ s/\n.*//s;
  $message =~ s/ at \S+ line [0-9]+(, <\S*> (?:line|chunk) [0-9]+)?\.?\s*$//;
  return
    grep $_->{type} eq 'warning' && $message =~ /^$_->{match}/,
    diagnostics;
}

sub _splain {
  my ($message) = @_;
  for my $diag (_diagnostics($message)) {
    my $text = $pretty ? _pod_to_ansi($diag->{pod}) : $diag->{text};
    $text =~ s/^/    /gm;
    $message .= $text . "\n";
  }
  return $message;
}

sub _pod_to_ansi {
  my $pod = shift;
  my @parts = split /([IBCFSL])(?:<<<<\s+(.*?)\s+>>>>|<<<\s+(.*?)\s+>>>|<<\s+(.*?)\s+>>|<(.*?)>)/, $pod;
  my $out = '';
  while (@parts) {
    $out .= shift @parts;
    if (@parts) {
      my $code = shift @parts;
      my ($text) = grep defined, splice @parts, 0, 4;
      if ($code eq 'E') {
        $out .= Devel::ClassifyDiagnostics::_pod_to_text("E<$text>");
        next;
      }
      elsif ($code eq 'L') {
        my ($t, $l, $s) = $text =~ m{^(?:(.*?)\|)?(\w+:.*|.*?)(?:/(.*?))?$};
        ($text) = grep defined, $t, $s, $l;
        $text = "\033[4m$text\033[0m";
      }
      elsif ($code eq 'X') {
        next;
      }
      elsif ($code eq 'B' || $code eq 'C') {
        $text = "\033[1m$text\033[0m";
      }
      elsif ($code eq 'I' || $code eq 'F') {
        $text = "\033[3m$text\033[0m";
      }
      $out .= _pod_to_ansi($text);
    }
  }
  $out;
}

1;

__END__
