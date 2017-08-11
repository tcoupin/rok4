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

################################################################################

=begin nd
File: Base36.pm

Class: BE4::Base36

Base 36 converting tools. Do not instanciate.

Using:
    (start code)
    use BE4::Base36;
    my ($i) = BE4::Base36::b36PathToIndices("E21") ; # returns 18217
    my ($i,$j) = BE4::Base36::b36PathToIndices("3E/42/01") ; # returns [4032,18217]
    my $b36 = BE4::Base36::encodeB10toB36(32674) ; # returns "P7M"
    my $b36Path = BE4::Base36::indicesToB36Path(4032, 18217, 2) ; # returns "3E/42/01"
    (end code)
=cut

################################################################################

package BE4::Base36;

use strict;
use warnings;

use Data::Dumper;

require Exporter;
use AutoLoader qw(AUTOLOAD);

our @ISA = qw(Exporter);

our %EXPORT_TAGS = ( 'all' => [ qw() ] );
our @EXPORT_OK   = ( @{$EXPORT_TAGS{'all'}} );
our @EXPORT      = qw();

################################################################################
# Constantes
use constant TRUE  => 1;
use constant FALSE => 0;

####################################################################################################
#                               Group: B36 returning functions                                     #
####################################################################################################

=begin nd
Function: encodeB10toB36

Convert a base-10 number into base-36 (string).

Parameters (list):
    number - integer - The base-10 integer to convert.
    length - integer - Optionnal, to force the minimum number of character.
    
Examples:
    - BE4::Base36::encodeB10toB36(32674) returns "P7M".
    - BE4::Base36::encodeB10toB36(156,4) returns "004C".
    - BE4::Base36::encodeB10toB36(156,1) returns "4C".
=cut
sub encodeB10toB36 {
    my $number = shift; # in base 10 !
    my $length = shift;
    
    my $b36 = ""; # in base 36 !
    
    while ( $number ) {
        my $v = $number % 36;
        if($v <= 9) {
            $b36 .= $v;
        } else {
            $b36 .= chr(55 + $v); # Assume that 'A' is 65
        }
        $number = int $number / 36;
    }
    
    $b36 = reverse($b36);
    
    # fill with 0 !
    if (defined $length && $length > length $b36) {
        $b36 = "0"x($length - length $b36).$b36;
    }

    $b36 = "0" if ($b36 eq "");
    
    return $b36;
}

=begin nd
Function: indicesToB36Path

Convert base-10 indices into a base-36 path (string). If the base-36 indices are (ABC,123), the base-36 path is "A1/B2/C3".

Parameters (list):
    i,j - integers - The base-10 indices to convert into a path.
    pathlength - integer - Number of subdirectories + the file.
    
Examples:
    BE4::Base36::indicesToB36Path(4032, 18217, 3) returns "3E/42/01".
    
See also:
    <encodeB10toB36>
=cut
sub indicesToB36Path {
    my $i = shift ;
    my $j = shift ;
    my $pathlength = shift ;
    
    my $xb36 = BE4::Base36::encodeB10toB36($i,$pathlength);
    my $yb36 = BE4::Base36::encodeB10toB36($j,$pathlength);
    
    if (length ($xb36) > length ($yb36)) {
        $yb36 = "0"x(length ($xb36) - length ($yb36)).$yb36;
    }
    
    if (length ($xb36) < length ($yb36)) {
        $xb36 = "0"x(length ($yb36) - length ($xb36)).$xb36;
    }
    
    my $B36Path = "";
    
    for(my $i=1; $i < $pathlength; $i++) {
        $B36Path = chop($yb36).$B36Path;
        $B36Path = chop($xb36).$B36Path;
        $B36Path = '/'.$B36Path;
    }
    
    # We add what are left
    $B36Path = $yb36.$B36Path;
    $B36Path = $xb36.$B36Path;
        
    return $B36Path ;
}

####################################################################################################
#                               Group: B10 returning functions                                     #
####################################################################################################

=begin nd
Function: encodeB36toB10

Convert a base-36 number into base-10 (int).

Parameters (list):
    b36 - string - The base-36 integer to convert.
    
Example:
    BE4::Base36::encodeB10toB36("F4S6") returns 706038.
=cut
sub encodeB36toB10 {
    my $b36  = shift; # idx in base 36 !
    
    my $number = 0;
    my $i = 0;
    foreach(split //, reverse uc $b36) {
        $_ = ord($_) - 55 unless /\d/; # Assume that 'A' is 65
        $number += $_ * (36 ** $i++);
    }
    
    return $number;
}

=begin nd
Function: b36PathToIndices

Converts a base-36 path into base-10 indices (x,y). If the base-36 indices are (ABC,123), the base-36 path is "A1/B2/C3".

Parameters (list):
    path - string - The base-36 path to convert into 2 base-10 indices

Returns:
    An integer list, (col,row).
    
Example:
    BE4::Base36::b36PathToIndices("3E/42/01") returns (4032,18217).
        
See also:
    <encodeB36toB10>
=cut
sub b36PathToIndices {
    my $path = shift;
    
    my $xB36 = "";
    my $yB36 = "";
    
    my @dirs = split(/\//,$path);
    for (my $i = 0; $i < scalar @dirs; $i++) {
        my $part = $dirs[$i];
        $xB36 .= substr($part,0,length($part)/2);
        $yB36 .= substr($part,length($part)/2);
    }
    
    my $x = BE4::Base36::encodeB36toB10($xB36);
    my $y = BE4::Base36::encodeB36toB10($yB36);
    
    return ($x, $y);
}


1;
__END__
