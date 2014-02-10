use strict;
use warnings FATAL => 'all';

my %META = (
  name => 'Devel::ClassifyWarnings',
  license => 'perl_5',
  prereqs => {
    configure => { requires => {
      'ExtUtils::MakeMaker' => 0,
    } },
    build => { requires => {
    } },
    test => { requires => {
      'Test::More' => 0.94,
    } },
    runtime => { requires => {
      'perl' => '5.8.1',
    } },
    develop => { requires => { map { $_ => 0 } qw(
    ) } },
  },
  resources => {
    repository => {
      url => 'git://github.com/haarg/Devel-ClassifyWarnings',
      web => 'https://github.com/haarg/Devel-ClassifyWarnings',
      type => 'git',
    },
    bugtracker => {
      web => 'https://rt.cpan.org/Public/Dist/Display.html?Name=Devel-ClassifyWarnings',
      mailto => 'bug-Devel-ClassifyWarnings@rt.cpan.org',
    },
    license => [ 'http://dev.perl.org/licenses/' ],
  },
  no_index => {
    directory => [ 'xt' ]
  },
);

my %MM_ARGS = (
  EXE_FILES => [],
);

###############################################################################
use ExtUtils::MakeMaker;

(do 'maint/Makefile.PL.include' or die $@) unless -f 'META.yml';

# have to do this since old EUMM dev releases miss the eval $VERSION line
my $eumm_version = eval $ExtUtils::MakeMaker::VERSION;
my $mymeta_works      = $eumm_version >= 6.57_07;
my $mymeta            = $eumm_version >= 6.57_02;
my $has_test_requires = $eumm_version >= 6.63_03;

my %configure_deps = %{ $META{prereqs}{configure}{requires} };
my %build_deps     = %{ $META{prereqs}{build}{requires} };
my %test_deps      = %{ $META{prereqs}{test}{requires} };
my %run_deps       = %{ $META{prereqs}{runtime}{requires} };

my $min_perl_version = delete $run_deps{perl};

if (not $has_test_requires) {
  %build_deps = (%build_deps, %test_deps);
  %test_deps = ();
}
if (not $mymeta_works) {
  %run_deps = (%run_deps, %build_deps);
  %build_deps = ();
}

(my $module_name = $META{name}) =~ s/-/::/g;
(my $module_file = "lib/$module_name.pm") =~ s{::}{/}g;

WriteMakefile(
  NAME => $module_name,
  VERSION_FROM => $module_file,
  LICENSE => $META{license},

  $eumm_version >= 6.47_01 && $min_perl_version
    ? ( MIN_PERL_VERSION    => $min_perl_version ) : (),
  $eumm_version >= 6.51_03
    ? ( CONFIGURE_REQUIRES  => \%configure_deps ) : (),
  $eumm_version >= 6.55_01
    ? ( BUILD_REQUIRES      => \%build_deps ) : (),
  $eumm_version >= 6.63_03
    ? ( TEST_REQUIRES       => \%test_deps ) : (),
  PREREQ_PM => \%run_deps,

  ($mymeta && !$mymeta_works ? (NO_MYMETA => 1) : ()),
  -f 'META.yml' ? () : (META_ADD => { 'meta-spec' => { version => 2 }, %META }),

  %MM_ARGS,
);
