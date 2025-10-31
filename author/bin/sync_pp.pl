# This script is to sync JSON::backportPP with the latest JSON::PP

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../lib";
use Path::Tiny;
use JSON;

my $re_pp_methods = join '|', JSON->pureperl_only_methods;

my $root = path("$FindBin::Bin/../..");
my $pp_root = $root->parent->child('JSON-PP');
my $test_dir = $root->child('t');

die "JSON-PP directory not found" unless -d $pp_root;

{
    my $pp_lib = $pp_root->child('lib/JSON/PP.pm');
    my $content = $pp_lib->slurp;
    $content =~ s/^package /package # This is JSON::backportPP\n    /;
    $content =~ s/^( *)package (JSON::PP(?:::(?:Boolean|IncrParser))?);/$1package # hide from PAUSE\n$1  $2;/gm;
    $content =~ s/use JSON::PP::Boolean/use JSON::backportPP::Boolean/;
    $content =~ s/JSON::PP::Compat/JSON::backportPP::Compat/g;
    $content =~ s/\$JSON::PP::([\w:]+)VERSION/\$JSON::backportPP::$1VERSION/g;
    $content =~ s/\$JSON::PP::VERSION/\$JSON::backportPP::VERSION/g;
    $content =~ s/\@JSON::PP::ISA/\@JSON::backportPP::ISA/g;
    $root->child('lib/JSON/backportPP.pm')->spew($content);
}

{
    my $pp_lib = $pp_root->child('lib/JSON/PP/Boolean.pm');
    my $content = $pp_lib->slurp;
    $content =~ s/^package /package # This is JSON::backportPP\n    /;
    $content =~ s/^( *)package (JSON::PP(?:::(?:Boolean|IncrParser))?);/$1package # hide from PAUSE\n$1  $2;/gm;
    $content =~ s/\$JSON::PP::([\w:]+)?VERSION/\$JSON::backportPP::$1VERSION/g;
    $content =~ s/JSON::PP( )/JSON::backportPP$1/g;
    $root->child('lib/JSON/backportPP/Boolean.pm')->spew($content);
}

for my $pp_test ($pp_root->child('t')->children) {
    my $basename = $pp_test->basename;
    $basename =~ s/^0([0-9][0-9])/$1/;
    my $json_test = $test_dir->child($basename);
    if ($basename =~ /\.pm$/) {
        my $content = $pp_test->slurp;
        $content =~ s/JSON::PP::/JSON::/g;
        $json_test->spew($content);
        print STDERR "copied $pp_test to $json_test\n";
        next;
    }
    if ($basename =~ /\.t$/) {
        my $content = $pp_test->slurp;
        $content =~ s/JSON::PP(::|->|;| |\.|$)/JSON$1/mg;
        $content =~ s/\$ENV{PERL_JSON_BACKEND} = 0/\$ENV{PERL_JSON_BACKEND} ||= "JSON::backportPP"/;
        $content =~ s/\{\s*#SKIP_UNLESS_PP (\S+)\s*,\s*(\S+)/SKIP: { skip "requires \$JSON::BackendModule $1 or newer", $2 if \$JSON::BackendModulePP and eval \$JSON::BackendModulePP->VERSION < $1;/g;
        $content =~ s/\{\s*#SKIP_IF_CPANEL/SKIP: { skip "not for \$JSON::BackendModule", 1 if \$JSON::BackendModule eq 'Cpanel::JSON::XS';/g;
        $content =~ s/#SKIP_ALL_UNLESS_PP (\S+)/BEGIN { plan skip_all => "requires \$JSON::BackendModule $1 or newer" if JSON->backend->is_pp and eval \$JSON::BackendModule->VERSION < $1 }/g;
        $content =~ s/#SKIP_ALL_IF_XS/BEGIN { plan skip_all => "not for \$JSON::BackendModule" if \$JSON::BackendModule eq 'JSON::XS' }/g;

        $content =~ s/\{\s*#SKIP_UNLESS_XS4_COMPAT (\S+)/SKIP: { skip "requires JSON::XS 4 compat backend", $1 if (\$JSON::BackendModulePP and eval \$JSON::BackendModulePP->VERSION < 3) or (\$JSON::BackendModule eq 'Cpanel::JSON::XS') or (\$JSON::BackendModule eq 'JSON::XS' and \$JSON::BackendModule->VERSION < 4);/g;
        $content =~ s/#SKIP_ALL_UNLESS_XS4_COMPAT/BEGIN { plan skip_all => "requires JSON::XS 4 compat backend" if (\$JSON::BackendModulePP and eval \$JSON::BackendModulePP->VERSION < 3) or (\$JSON::BackendModule eq 'Cpanel::JSON::XS') or (\$JSON::BackendModule eq 'JSON::XS' and \$JSON::BackendModule->VERSION < 4); }/g;

        if ($content !~ /\$ENV{PERL_JSON_BACKEND}/) {
            $content =~ s/use JSON;/BEGIN { \$ENV{PERL_JSON_BACKEND} ||= "JSON::backportPP"; }\n\nuse JSON;/;
        }

        if ($content =~ /$re_pp_methods/) {
            $content =~ s/use JSON;/use JSON -support_by_pp;/g;
        }

        # special cases
        if ($basename eq '19_incr.t') {
            $content =~ s/(splitter \+JSON\->new)\s+/$1->allow_nonref (1)/g;
            $content =~ s/encode_json ([^,]+?),/encode_json($1),/g;
        }
        if ($basename eq '52_object.t') {
            my $plan = '';
            if ($content =~ s|BEGIN \{ (plan tests => \d+) };\n||s) {
                $plan = $1;
            }
            my $skip = <<'SKIP';
my $backend_version = JSON->backend->VERSION; $backend_version =~ s/_//;

plan skip_all => "allow_tags is not supported" if $backend_version < 3;
SKIP
            $content =~ s|(use JSON;\n)|$1\n$skip\n$plan;\n|s;
        }
        if ($basename eq '104_sortby.t') {
            $content =~ s/JSON::hoge/JSON::PP::hoge/g;
            $content =~ s/\$JSON::(a|b)\b/\$JSON::PP::$1/g;
        }
        if ($basename eq 'gh_28_json_test_suite.t') {
            $content =~ s/\$ENV{PERL_JSON_BACKEND} \|\|= "JSON::backportPP"/\$ENV{PERL_JSON_BACKEND} = "JSON::backportPP"/;
        }
        if ($basename eq '118_boolean_values.t') {
            $content =~ s/JSON::Boolean/JSON::PP::Boolean/g;
            $content =~ s/(push \@tests, \[JSON::true\(\), JSON::false\(\), 'JSON::PP::Boolean', 'JSON::PP::Boolean'\];\n)/$1    push \@tests, [JSON->boolean(11), JSON->boolean(undef), 'JSON::PP::Boolean', 'JSON::PP::Boolean'];\n    push \@tests, [JSON::boolean(11), JSON::boolean(undef), 'JSON::PP::Boolean', 'JSON::PP::Boolean'];\n/;
        }
        if ($basename eq '119_incr_parse_utf8.t') {
            $content =~ s[(use JSON;)]
                         [$1\nplan skip_all => "not for older version of JSON::PP" if JSON->backend->isa('JSON::PP') && JSON->backend->VERSION < 4.07;]s;
            $content =~ s|use Test::More tests => 24;|use Test::More;|;
            $content =~ s|(use charnames qw< :full >;)|$1\n\nplan tests => 24;|;
        }
        if ($basename eq '120_incr_parse_truncated.t') {
            $content =~ s[(use JSON;)]
                         [$1\nplan skip_all => "not for older version of JSON::PP" if JSON->backend->isa('JSON::PP') && JSON->backend->VERSION < 4.09;]s;
            $content =~ s|my \$coder = JSON->new;|my \$coder = JSON->new->allow_nonref(1);|g;
        }
        if ($basename eq '03_types.t') {
            $content =~ s|JSON\->can\("CORE_BOOL"\) && JSON::CORE_BOOL\(\)|JSON->backend->can("CORE_BOOL") && JSON->backend->CORE_BOOL|g;
        }
        if ($basename eq 'core_bools.t') {
            $content =~ s|JSON->can\('CORE_BOOL'\)|JSON->backend->can('CORE_BOOL')|g;
            $content =~ s|JSON::CORE_BOOL|JSON->backend->CORE_BOOL|g;
        }

        $json_test->spew($content);
        print STDERR "copied $pp_test to $json_test\n";
        next;
    }
    print STDERR "Skipped $pp_test\n";
}
