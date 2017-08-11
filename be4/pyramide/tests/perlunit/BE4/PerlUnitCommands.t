# Copyright © (2011) Institut national de l'information
#                    géographique et forestière
#
# Géoportail SAV <geop_services@geoportail.fr>
#
# This software is a computer program whose purpose is to publish geographic
# data using OGC WMS and WMTS protocol.
#
# This software is governed by the CeCILL-C license under French law and
# abiding by the rules of distribution of free software.  You can  use,
# modify and/ or redistribute the software under the terms of the CeCILL-C
# license as circulated by CEA, CNRS and INRIA at the following URL
# "http://www.cecill.info".
#
# As a counterpart to the access to the source code and  rights to copy,
# modify and redistribute granted by the license, users are provided only
# with a limited warranty  and the software's author,  the holder of the
# economic rights,  and the successive licensors  have only  limited
# liability.
#
# In this respect, the user's attention is drawn to the risks associated
# with loading,  using,  modifying and/or developing or reproducing the
# software by the user in light of its specific status of free software,
# that may mean  that it is complicated to manipulate,  and  that  also
# therefore means  that it is reserved for developers  and  experienced
# professionals having in-depth computer knowledge. Users are therefore
# encouraged to load and test the software's suitability as regards their
# requirements in conditions enabling the security of their systems and/or
# data to be ensured and,  more generally, to use and operate it in the
# same conditions as regards security.
#
# The fact that you are presently reading this means that you have had
#
# knowledge of the CeCILL-C license and that you accept its terms.

use strict;
use warnings;

use Test::More;

use Log::Log4perl qw(:easy);
# logger by default for unit tests
Log::Log4perl->easy_init({
    level => $WARN,
    layout => '%5p : %m (%M) %n'
});

use FindBin qw($Bin); # aboslute path of the present testfile in $Bin

# My tested class
use BE4::Commands;

#Other BE4 Used Class
use BE4::Pyramid;

######################################################

# Commands Object Creation

my $pyramid = BE4::Pyramid->new({

    tms_path => $Bin."/../../tms",
    tms_name => "LAMB93_10cm.tms",

    dir_depth => 2,

    pyr_data_path => $Bin."/../../pyramid",
    pyr_desc_path => $Bin."/../../pyramid",
    pyr_name_new => "newPyramid",

    dir_image => "IMAGE",
    dir_nodata => "NODATA",
    dir_metadata => "METADATA",

    pyr_level_bottom => "19",

    compression => "raw",
    image_width => 16,
    image_height => 16,
    bitspersample => 8,
    sampleformat => "uint",
    photometric => "rgb",
    samplesperpixel => 3,
    interpolation => "bicubic",

    color => "FFFFFF"
});

my $commands = BE4::Commands->new($pyramid);

ok (defined $commands, "Commands Object created");

######################################################

# Testing Split Header Creation
my $header = $commands->configureFunctions();
ok (defined $header && $header ne "", "Header created with configureFunctions method.");
ok ($header =~ m/Wms2work/, "Header contains Wms2work function.");
ok ($header =~ m/Cache2work/, "Header contains Cache2work function.");
ok ($header =~ m/MergeNtiff/, "Header contains MergeNtiff function.");
ok ($header =~ m/Merge4tiff/, "Header contains Merge4tiff function.");
ok ($header =~ m/Work2cache/, "Header contains Work2cache function.");

done_testing();
