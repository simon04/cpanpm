# Test CPAN::Distribution objects
#
# Very, very preliminary API testing, but we have to start somewhere

my $has_cpan_meta;
BEGIN {
    unshift @INC, './lib', './t';

    require local_utils;
    local_utils::cleanup_dot_cpan();
    local_utils::prepare_dot_cpan();
    require CPAN::MyConfig;
    require CPAN;

    CPAN::HandleConfig->load;
    $CPAN::Config->{load_module_verbosity} = q[none];
    $has_cpan_meta = $CPAN::META->has_usable("CPAN::Meta");
}

use strict;

use Cwd qw(cwd);
use File::Copy qw(cp);
use File::Path qw(rmtree mkpath);
use File::Temp qw(tempdir);
use File::Spec::Functions qw/catdir catfile/;
use File::Basename qw/basename/;
use Storable 'dclone';

use lib "inc";
use lib "t";
use local_utils;

# prepare local CPAN
local_utils::cleanup_dot_cpan();
local_utils::prepare_dot_cpan();
# and be sure to clean it up
END{ local_utils::cleanup_dot_cpan(); }

use Test::More;

my (@meta_tests); # defined later in BEGIN blocks

if ( $has_cpan_meta ) {
    plan tests => 4 * @meta_tests;
}
else {
    plan 'skip_all' => "CPAN::Meta not available";
}

#--------------------------------------------------------------------------#
# read_meta() testing
#--------------------------------------------------------------------------#

BEGIN {
    my $meta_json_prereqs = {
        "configure" => {
            "requires" => {
                "ExtUtils::MakeMaker" => "6.31"
            }
        },
        "runtime" => {
            "requires" => {
                "Time::Local" => 0,
                "perl" => "5.006"
            }
        },
        "test" => {
            "requires" => {
                "Test::More" => "0.88"
            }
        }
    };

    my $mymeta_json_prereqs = dclone($meta_json_prereqs);
    $mymeta_json_prereqs->{runtime}{requires}{"File::Spec"} = "0.87";

    # YAML has build_requires, not test_requires
    my $meta_yml_prereqs = dclone($meta_json_prereqs);
    $meta_yml_prereqs->{build} = delete $meta_yml_prereqs->{test};

    my $mymeta_yml_prereqs = dclone($meta_yml_prereqs);
    $mymeta_yml_prereqs->{runtime}{requires}{"File::Spec"} = "0.87";

    @meta_tests = (
        # No META files at all
        {
            label => 'no META',
            copies => [],
            pick => undef,
            prereqs => undef,
        },
        # Single META file -- dynamic
        {
            label => 'dynamic META.json only',
            copies => [ 'META-dynamic.json' => 'META.json' ],
            pick => 'META.json',
            prereqs => undef,
        },
        {
            label => 'dynamic META.yml only',
            copies => [ 'META-dynamic.yml' => 'META.yml' ],
            pick => 'META.yml',
            prereqs => undef,
        },
        # Single META file -- static
        {
            label => 'static META.json only',
            copies => [ 'META-static.json' => 'META.json' ],
            pick => 'META.json',
            prereqs => $meta_json_prereqs,
        },
        {
            label => 'static META.yml only',
            copies => [ 'META-static.yml' => 'META.yml' ],
            pick => 'META.yml',
            prereqs => $meta_yml_prereqs,
        },
        # Both META.json and META.yml -- static
        {
            label => 'both META.json and META.yml',
            copies => [
                'META-static.json' => 'META.json',
                'META-static.yml' => 'META.yml'
            ],
            pick => 'META.json',
            prereqs => $meta_json_prereqs,
        },
        # Single MYMETA file -- static
        {
            label => 'MYMETA.json only',
            copies => [ 'MYMETA.json' => 'MYMETA.json' ],
            pick => 'MYMETA.json',
            prereqs => $mymeta_json_prereqs,
        },
        {
            label => 'MYMETA.yml only',
            copies => [ 'MYMETA.yml' => 'MYMETA.yml' ],
            pick => 'MYMETA.yml',
            prereqs => $mymeta_yml_prereqs,
        },
        # Both MYMETA.json and MYMETA.yml -- static
        {
            label => 'both MYMETA.json and MYMETA.yml',
            copies => [
                'MYMETA.json' => 'MYMETA.json',
                'MYMETA.yml' => 'MYMETA.yml'
            ],
            pick => 'MYMETA.json',
            prereqs => $mymeta_json_prereqs,
        },
        #  static MYMETA.json and dynamic META.json
        {
            label => 'MYMETA.json and META.json',
            copies => [
                'MYMETA.json' => 'MYMETA.json',
                'META-dynamic.json' => 'META.json',
            ],
            pick => 'MYMETA.json',
            prereqs => $mymeta_json_prereqs,
        },
        #  static MYMETA.yml and dynamic META.yml
        {
            label => 'MYMETA.yml and META.yml',
            copies => [
                'MYMETA.yml' => 'MYMETA.yml',
                'META-dynamic.yml' => 'META.yml',
            ],
            pick => 'MYMETA.yml',
            prereqs => $mymeta_yml_prereqs,
        },
    );
}

{
    for my $case ( @meta_tests ) {
        my $label = $case->{label};
        my $tempdir = tempdir( "t/41distributionXXXX", CLEANUP => 1 );

        # dummy distribution
        my $dist = CPAN::Distribution->new(
            ID => "D/DA/DAGOLDEN/Bogus-Module-1.234"
        );
        $dist->{build_dir} = $tempdir;

        # copy files
        if ( $case->{copies} ) {
            while (@{$case->{copies}}) {
                my ($from, $to) = splice(@{$case->{copies}},0,2);
                cp catfile( qw/t data/, $from) => catfile($tempdir, $to);
            }
        }

        # check read_yaml
        my $pick = $dist->pick_meta_file;
        is( ( defined $pick ? basename($pick) : $pick ), $case->{pick},
            "$label\: pick_meta_file $case->{pick}"
        );
        my $meta = $dist->read_meta;
        my $prereqs = $case->{prereqs};
        if ( defined $prereqs ) {
            isa_ok( $meta, 'CPAN::Meta', "$label\: read_meta" );
            isa_ok( $dist->read_meta, 'CPAN::Meta', "$label\: repeat read_meta" );
            is_deeply( ($meta ? $meta->prereqs : undef), $prereqs, "$label\: prereq data correct");
        }
        else {
            is( $meta, undef, "$label\: read_meta returns undef");
            is( $dist->read_meta, undef, "$label\: repeat read_yaml returns undef");
            pass( "$label\: no requirement checks apply" );
        }
    }
}

# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# End:
# vi: ts=4:sts=4:sw=4:et:
