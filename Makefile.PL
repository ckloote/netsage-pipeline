use strict;
use warnings;

use ExtUtils::MakeMaker;

sub MY::postamble { <<'END'; }

rpm:	dist
	rpmbuild -ta grnoc-netsage-deidentifier-$(VERSION).tar.gz
END

sub MY::test
	{
    q(
TEST_VERBOSE=1

test :	pure_all
	$(FULLPERL) t/TEST $(TEST_VERBOSE)

test_jenkins : pure_all
	$(FULLPERL) t/TEST $(TEST_VERBOSE) --formatter=TAP::Formatter::Console
    );
}

WriteMakefile(
              NAME                => 'grnoc-netsage-deidentifier',
              AUTHOR              => 'GRNOC Software Engineering <globalnoc@iu.edu>',
              VERSION_FROM        => 'lib/GRNOC/NetSage/Deidentifier.pm',
              PL_FILES            => {},
              PREREQ_PM => {
                           },
              dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
              clean               => { FILES => 'grnoc-netsage-deidentifier-*' },
             );
