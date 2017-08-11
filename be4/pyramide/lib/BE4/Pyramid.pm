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
File: Pyramid.pm

Class: BE4::Pyramid

Store all informations about a pyramid.

Using:
    (start code)
    use BE4::Pyramid;

    # 1. a new pyramid

    my $params_options = {
        #
        pyr_name_new => "ORTHO_RAW_LAMB93_D075-O",
        pyr_desc_path => "/home/ign/DATA",
        pyr_data_path => "/home/ign/DATA",
        #
        tms_name     => "LAMB93_10cm.tms",
        tms_path     => "/home/ign/TMS",
        #
        #
        dir_depth    => 2,
        dir_image    => "IMAGE",
        dir_nodata   => "NODATA",
        dir_mask     => "MASK",
        #
        image_width  => 16,
        image_height => 16,
        #
        color         => "255,255,255", # white
        #
        compression         => "raw",
        bitspersample       => 8,
        sampleformat        => "uint",
        photometric         => "rgb",
        samplesperpixel     => 3,
        interpolation       => "bicubic",
    };

    my $objPyr = BE4::Pyramid->new($params_options,$path_temp);

    $objPyr->writeConfPyramid(); # write pyramid's descriptor in /home/ign/ORTHO_RAW_LAMB93_D075-O.pyr

    $objP->writeCachePyramid($objForest);  # root directory is "/home/ign/ORTHO_RAW_LAMB93_D075-O/"

    # 2. a update pyramid, with an ancestor

    my $params_options  = {
        #
        pyr_name_old        => "ORTHO_RAW_LAMB93_D075-O",
        pyr_data_path_old   => "/home/ign/DATA",
        pyr_desc_path_old   => "/home/ign/DATA",
        #
        pyr_name_new        => "ORTHO_RAW_LAMB93_D075-E",
        pyr_desc_path       => "/home/ign/DATA",
        pyr_data_path       => "/home/ign/DATA",
        #
        update_mode      => "slink"
    };

    my $objPyr = BE4::Pyramid->new($params_options,"/home/ign/TMP");

    $objPyr->writeConfPyramid(); # write pyramid's descriptor in /home/ign/ORTHO_RAW_LAMB93_D075-E.pyr

    $objPyr->writeCachePyramid($objForest);  # root directory is "/home/ign/ORTHO_RAW_LAMB93_D075-E/"
    (end code)

Attributes:
    new_pyramid - hash - Name and paths for the new pyramid
|               name - string - Pyramid's name
|               desc_path - string - Directory in which we write the pyramid's descriptor
|               data_path - string - Directory in which we write the pyramid's data
|               content_path - string - Path to the content's list

    old_pyramid - hash - Name and paths for the ancestor pyramid
|               name - string - Pyramid's name
|               desc_path - string - Directory in which we write the pyramid's descriptor
|               data_path - string - Directory in which we write the pyramid's data
|               update_mode - string - type of updating the old pyramid.
|                   |   Possible values are : 'slink' (soft link - default), 'hlink' (hard link), 'copy' (hard copy), 'inject' (no new pyramid, we update the old pyramid directly). 
|               content_path - string - Path to the content's list

    dir_depth - integer - Number of subdirectories from the level root to the image : depth = 2 => /.../LevelID/SUB1/SUB2/IMG.tif
    dir_image - string - Name of images' directory
    dir_nodata - string - Name of nodata's directory
    dir_mask - string - Name of masks' directory
    own_masks - boolean - If TRUE, masks generated by tools will be written in the final pyramid. If we want to export them, we have to use them in tools.
    dir_metadata - string - Name of metadats' directory (NOT IMPLEMENTED)
    image_width - integer - Number of tile in an pyramid's image, widthwise.
    image_height - integer - Number of tile in an pyramid's image, heightwise.

    pyrImgSpec - <PyrImageSpec> - New pyramid's image's components
    tms - <TileMatrixSet> - Pyramid's images will be cutted according to this TMS grid.
    nodata - <NoData> - Informations about nodata
    levels - <Level> hash - Key is the level ID, the value is the <Level> object. Define levels present in this new pyramid.

Limitations:

File name of pyramid must be with extension : pyr or PYR.
=cut

################################################################################

package BE4::Pyramid;

use strict;
use warnings;

use Log::Log4perl qw(:easy);
use XML::LibXML;

use Geo::OSR;

use File::Spec::Link;
use File::Basename;
use File::Spec;
use File::Path;
use File::Copy;
use Tie::File;

use Data::Dumper;

use BE4::TileMatrixSet;
use BE4::Level;
use BE4::NoData;
use BE4::PyrImageSpec;
use BE4::Pixel;
use BE4::Forest;
use BE4::Base36;

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

# Constant: STRPYRTMPLT
# Define the template XML for the pyramid's descriptor.
my $STRPYRTMPLT   = <<"TPYR";
<?xml version='1.0' encoding='UTF-8'?>
<Pyramid>
    <tileMatrixSet>__TMSNAME__</tileMatrixSet>
    <format>__FORMATIMG__</format>
    <channels>__CHANNEL__</channels>
    <nodataValue>__NODATAVALUE__</nodataValue>
    <interpolation>__INTERPOLATION__</interpolation>
    <photometric>__PHOTOMETRIC__</photometric>
<!-- __LEVELS__ -->
</Pyramid>
TPYR

# Constant: DEFAULT
# Define default values for directories' names.
my %DEFAULT;

# Constant: UPDATE_MODES
# Defines possibles values for the 'update_mode' parameter.
my @UPDATE_MODES;

################################################################################

BEGIN {}

INIT {
    %DEFAULT = (
        dir_image => 'IMAGE',
        dir_nodata => 'NODATA',
        dir_mask => 'MASK',
        dir_metadata => 'METADATA',
        update_mode => 'slink'
    );
    @UPDATE_MODES = (
        'slink', # symbolic link to ancestor's images
        'hlink', # hard link to ancestor's images.
        'copy',   # real copy of ancestor's images.
        'inject' # no new pyramid : we update the old pyramid
    );
}

END {}

####################################################################################################
#                                        Group: Constructors                                       #
####################################################################################################

=begin nd
Constructor: new

Pyramid constructor. Bless an instance.

Parameters (list):
    params - hash - All parameters about the new pyramid, "pyramid" section of the be4 configuration file
    pathfile - string - Path to the Tile Matrix File (with extension .tms or .TMS)

See also:
    <_init>, <_load>
=cut
sub new {
    my $this = shift;
    my $params = shift;
    my $path_temp = shift;

    my $class= ref($this) || $this;
    # IMPORTANT : if modification, think to update natural documentation (just above)
    my $self = {
        # NOTE
        # 2 options possible with parameters :
        #   - a new pyramid configuration
        #   - a existing pyramid configuration
        #        - update (copy, slink, hlink)
        #        - inject (inject)
        # > in a HASH entry only (no ref) !
        # the choice is on the parameter 'pyr_name_old'
        #   1) if param is null, it's a new pyramid only !
        #   2) if param is not null, it's an existing pyramid !

        new_pyramid => { 
            name          => undef,
            desc_path     => undef,
            data_path     => undef,
            content_path  => undef,
        },
        old_pyramid => { 
            name          => undef,
            desc_path     => undef,
            data_path     => undef,
            content_path  => undef,
            update_mode  => undef,
        },
        #
        dir_depth    => undef,
        dir_image    => undef,
        dir_nodata   => undef,
        dir_mask     => undef,
        dir_metadata => undef,
        image_width  => undef,
        image_height => undef,
        own_masks    => FALSE,

        # OUT
        pyrImgSpec => undef,
        tms        => undef,
        nodata     => undef,
        levels     => {},
    };

    bless($self, $class);

    TRACE;

    # init. parameters
    if (! $self->_init($params)) {return undef;}

    # a new pyramid or from existing pyramid !
    if (! $self->_load($params,$path_temp)) {return undef;};
    
    return $self;   
}

=begin nd
Function: _init

We detect missing parameters and define default values for pyramids' name and path (for the new one and the ancestor). Store data directories' names

Parameters (list):
    params - hash - All parameters about pyramid's format, pyramid section of the be4 configuration file
=cut
sub _init {
    my $self   = shift;
    my $params = shift;

    TRACE;

    if (! defined $params ) {
        ERROR ("Parameters argument required (null) !");
        return FALSE;
    }
    
    # Always mandatory :
    #   - pyr_name_new, pyr_desc_path, pyr_data_path
    #   - tms_path
    if (! exists $params->{pyr_name_new} || ! defined $params->{pyr_name_new}) {
        ERROR ("The parameter 'pyr_name_new' is required!");
        return FALSE;
    }
    $params->{pyr_name_new} =~ s/\.(pyr|PYR)$//;
    $self->{new_pyramid}->{name} = $params->{pyr_name_new};
    
    if (! exists $params->{pyr_desc_path} || ! defined $params->{pyr_desc_path}) {
        ERROR ("The parameter 'pyr_desc_path' is required!");
        return FALSE;
    }
    $self->{new_pyramid}->{desc_path} = $params->{pyr_desc_path};
    
    if (! exists $params->{pyr_data_path} || ! defined $params->{pyr_data_path}) {
        ERROR ("The parameter 'pyr_data_path' is required!");
        return FALSE;
    }
    $self->{new_pyramid}->{data_path} = $params->{pyr_data_path};
    
    if (! exists $params->{tms_path} || ! defined $params->{tms_path}) {
        ERROR ("The parameter 'tms_path' is required!");
        return FALSE;
    }
    $self->{tms_path} = $params->{tms_path};
    
    
    # Different treatment for a new or an update pyramid
    if (exists $params->{pyr_name_old} && defined $params->{pyr_name_old}) {
        # With an ancestor
        $params->{pyr_name_old} =~ s/\.(pyr|PYR)$//;
        $self->{old_pyramid}->{name} = $params->{pyr_name_old};
        #
        if (! exists $params->{pyr_desc_path_old} || ! defined $params->{pyr_desc_path_old}) {
            WARN ("Parameter 'pyr_desc_path_old' has not been set, 'pyr_desc_path' is used.");
            $params->{pyr_desc_path_old} = $params->{pyr_desc_path};
        }
        $self->{old_pyramid}->{desc_path} = $params->{pyr_desc_path_old};
        #
        if (! exists $params->{pyr_data_path_old} || ! defined $params->{pyr_data_path_old}) {
            WARN ("Parameter 'pyr_data_path_old' has not been set, 'pyr_data_path' is used.");
            $params->{pyr_data_path_old} = $params->{pyr_data_path};
        }
        $self->{old_pyramid}->{data_path} = $params->{pyr_data_path_old};
        
        # checking the way to reference the ancestor's cache
        if (! exists $params->{update_mode} || ! defined $params->{update_mode}) {
            INFO (sprintf "Parameter 'update_mode' has not been set. Default value ('%s') is used.",$DEFAULT{update_mode});
            $params->{update_mode} = $DEFAULT{update_mode};
        } elsif ( ! isUpdateMode($params->{update_mode}) ) {
            ERROR (sprintf "'%s' is not a valid value for parameter 'update_mode'.",$params->{update_mode});
            return FALSE;
        }
        $self->{old_pyramid}->{update_mode} = $params->{update_mode};
        
        if ($self->getUpdateMode() eq "inject") {
            INFO("CAUTION : You use update mode 'inject' at your own risk : old pyramid will be modified irreversibly. If an error occured, no rollback will be done.");
            # La nouvelle pyramide est en fait l'ancienne
            $self->{new_pyramid}->{data_path} = $self->{old_pyramid}->{data_path};
            $self->{new_pyramid}->{desc_path} = $self->{old_pyramid}->{desc_path};
            $self->{new_pyramid}->{name} = $self->{old_pyramid}->{name};
            $self->{new_pyramid}->{content_path} = $self->{old_pyramid}->{content_path};
        }
        
    } else {
        # For a new pyramid, are mandatory (and controlled in this class):
        #   - image_width, image_height
        #   - dir_depth
        
        if (! exists $params->{image_width} || ! defined $params->{image_width}) {
            ERROR ("The parameter 'image_width' is required!");
            return FALSE;
        }
        $self->{image_width} = $params->{image_width};

        if (! exists $params->{image_height} || ! defined $params->{image_height}) {
            ERROR ("The parameter 'image_height' is required!");
            return FALSE;
        }
        $self->{image_height} = $params->{image_height};

        if (! exists $params->{dir_depth} || ! defined $params->{dir_depth}) {
            ERROR ("The parameter 'dir_depth' is required!");
            return FALSE;
        }
        $self->{dir_depth} = $params->{dir_depth};
    }
    
    ### Images' directory
    if (! exists $params->{dir_image} || ! defined $params->{dir_image}) {
        $params->{dir_image} = $DEFAULT{dir_image};
        INFO(sprintf "Default value for 'dir_image' : %s", $params->{dir_image});
    }
    $self->{dir_image} = $params->{dir_image};

    ### Nodata's directory
    if (! exists $params->{dir_nodata} || ! defined $params->{dir_nodata}) {
        $params->{dir_nodata} = $DEFAULT{dir_nodata};
        INFO(sprintf "Default value for 'dir_nodata' : %s", $params->{dir_nodata});
    }
    $self->{dir_nodata} = $params->{dir_nodata}; 

    ### Mask's directory
    if (! exists $params->{dir_mask} || ! defined $params->{dir_mask}) {
        $params->{dir_mask} = $DEFAULT{dir_mask};
        INFO(sprintf "Default value for 'dir_mask' : %s", $params->{dir_mask});
    }
    $self->{dir_mask} = $params->{dir_mask};

    ### We want masks in the final pyramid ?
    if ( exists $params->{export_masks} && defined $params->{export_masks} && uc($params->{export_masks}) eq "TRUE" ) {
        $self->{own_masks} = TRUE;
    }
    
    ### Metadatas' directory
    if (exists $params->{dir_metadata} && defined $params->{dir_metadata}) {
        WARN ("We want to generate metadatas, but it is not implemented !");
    }
    
    return TRUE;
}

=begin nd
Function: _load

We have to collect pyramid's attributes' values
    - for a new pyramid : all informations must be present in configuration.
    - for an updated pyramid (with ancestor) : informations are collected in the ancestor pyramid's descriptor, <fillFromAncestor> is called.

Informations are checked, using perl classes like <NoData>, <Level>, <PyrImageSpec>...

Parameters (list):
    params - All parameters about a pyramid's format (new or update).
    path_temp - string - Directory path, where to write the temporary old cache list, if not exist.
=cut
sub _load {
    my $self = shift;
    my $params = shift;
    my $path_temp = shift;

    TRACE;

    if ($self->isNewPyramid) {
        ##### create TileMatrixSet !
        my $objTMS = BE4::TileMatrixSet->new(File::Spec->catfile($params->{tms_path},$params->{tms_name}));

        if (! defined $objTMS) {
            ERROR ("Can not load TMS !");
            return FALSE;
        }

        $self->{tms} = $objTMS;
        DEBUG (sprintf "TMS = %s", $objTMS->exportForDebug);
    } else {
        # A pyramid with ancestor
        # init. process hasn't checked all parameters,
        # so, we must read file pyramid to initialyze them...
        return FALSE if (! $self->fillFromAncestor($params,$path_temp));
    }

    ##### create PyrImageSpec !
    my $pyrImgSpec = BE4::PyrImageSpec->new({
        formatCode => $params->{formatCode},
        bitspersample => $params->{bitspersample},
        sampleformat => $params->{sampleformat},
        photometric => $params->{photometric},
        samplesperpixel => $params->{samplesperpixel},
        interpolation => $params->{interpolation},
        compression => $params->{compression},
        compressionoption => $params->{compressionoption},
        gamma => $params->{gamma},
    });

    if (! defined $pyrImgSpec) {
        ERROR ("Can not load specification of pyramid's images !");
        return FALSE;
    }

    $self->{pyrImgSpec} = $pyrImgSpec;
    DEBUG(sprintf "PYRIMAGESSPEC (debug export) = %s", $pyrImgSpec->exportForDebug());

    ##### create NoData !
    my $objNodata = BE4::NoData->new({
        pixel   => $self->getPixel(),
        value   => $params->{color},
    });

    if (! defined $objNodata) {
        ERROR ("Can not load NoData !");
        return FALSE;
    }
    $self->{nodata} = $objNodata;
    
    DEBUG (sprintf "NODATA (debug export) = %s", $objNodata->exportForDebug());

    return TRUE;
}

####################################################################################################
#                                 Group: Ancestor informations extracter                           #
####################################################################################################

#
=begin nd
Function: fillFromAncestor

We want to update an old pyramid with new data. We have to collect attributes' value in old pyramid descriptor and old cache. They have priority to parameters. If the old cache doesn't have a list, we create temporary one.

Parameters (list):
    params - hash - Used to store extracted informations.
    path_temp - string - Directory path, where to write the temporary old cache list, if not exist.

See Also:
    <readConfPyramid>, <readCachePyramid>
=cut
sub fillFromAncestor {
    my $self  = shift;
    my $params = shift;
    my $path_temp = shift;

    TRACE;

    # Old pyramid's descriptor reading
    my $filepyramid = $self->getOldDescriptorFile();
    if (! $self->readConfPyramid($filepyramid,$params)) {
        ERROR (sprintf "Can not read the XML file Pyramid : %s !", $filepyramid);
        return FALSE;
    }

    # Old pyramid's cache list test : if it doesn't exist, we create a temporary one.
    my $listpyramid = $self->getOldListFile();
    if (! -f $listpyramid) {
        my $cachepyramid = $self->getOldDataDir();
        
        if (! defined $path_temp) {
            ERROR("'path_temp' must be defined to write the file list if it doesn't exist.");
            return FALSE;
        }
        $listpyramid = File::Spec->catfile($path_temp,$self->getNewName(),$self->getOldName().".list");
        $self->{old_pyramid}->{content_path} = $listpyramid;
        
        WARN(sprintf "Cache list file does not exist. We browse the old cache to create it (%s).",$listpyramid);
        
        if (! $self->readCachePyramid($cachepyramid,$listpyramid)) {
            ERROR (sprintf "Can not read the Directory Cache Pyramid : %s !", $cachepyramid);
            return FALSE;
        }
    }
    
    return TRUE;
}

=begin nd
Function: readConfPyramid

Parse an XML file, a pyramid's descriptor (file.pyr) to pick up informations. We identify levels which are present in the old pyramid (not necessaraly the same in the new pyramid).

Parameters (list):
    filepyramid - string - Complete absolute descriptor path.
    params - hash - Used to store extracted informations.
=cut
sub readConfPyramid {
    my $self   = shift;
    my $filepyramid = shift;
    my $params = shift;

    TRACE;

    if (! -f $filepyramid) {
        ERROR (sprintf "Can not find the XML file Pyramid : %s !", $filepyramid);
        return FALSE;
    }

    # read xml pyramid
    my $parser  = XML::LibXML->new();
    my $xmltree =  eval { $parser->parse_file($filepyramid); };

    if (! defined ($xmltree) || $@) {
        ERROR (sprintf "Can not read the XML file Pyramid : %s !", $@);
        return FALSE;
    }

    my $root = $xmltree->getDocumentElement;

    # read tag value of nodata value, photometric and interpolation (not obligatory)

    # NODATA
    my $tagnodata = $root->findnodes('nodataValue')->to_literal;
    if ($tagnodata eq '') {
        WARN (sprintf "Can not extract 'nodata' from the XML file Pyramid ! Value from parameters kept");
    } else {
        INFO (sprintf "Nodata value ('%s') in the XML file Pyramid is used",$tagnodata);
        $params->{color} = $tagnodata;
    }
    
    # PHOTOMETRIC
    my $tagphotometric = $root->findnodes('photometric')->to_literal;
    if ($tagphotometric eq '') {
        WARN (sprintf "Can not extract 'photometric' from the XML file Pyramid ! Value from parameters kept");
    } else {
        INFO (sprintf "Photometric value ('%s') in the XML file Pyramid is used",$tagphotometric);
        $params->{photometric} = $tagphotometric;
    }

    # INTERPOLATION    
    my $taginterpolation = $root->findnodes('interpolation')->to_literal;
    if ($taginterpolation eq '') {
        WARN (sprintf "Can not extract 'interpolation' from the XML file Pyramid ! Value from parameters kept");
    } else {
        INFO (sprintf "Interpolation value ('%s') in the XML file Pyramid is used",$taginterpolation);
        $params->{interpolation} = $taginterpolation;
    }

    # Read tag value of tileMatrixSet, format and channel, MANDATORY

    # TMS
    my $tagtmsname = $root->findnodes('tileMatrixSet')->to_literal;
    if ($tagtmsname eq '') {
        ERROR (sprintf "Can not extract 'tileMatrixSet' from the XML file Pyramid !");
        return FALSE;
    } else {
        INFO (sprintf "TMS's name value ('%s') in the XML file Pyramid is used",$tagtmsname);
        $params->{tms_name} = $tagtmsname.".tms";
    }

    ##### create TileMatrixSet !
    my $objTMS = BE4::TileMatrixSet->new(File::Spec->catfile($params->{tms_path},$params->{tms_name}));

    if (! defined $objTMS) {
      ERROR ("Can not load TMS !");
      return FALSE;
    }

    $self->{tms} = $objTMS;
    DEBUG (sprintf "TMS = %s", $objTMS->exportForDebug);

    # FORMAT
    my $tagformat = $root->findnodes('format')->to_literal;
    if ($tagformat eq '') {
        ERROR (sprintf "Can not extract 'format' in the XML file Pyramid !");
        return FALSE;
    } else {
        INFO (sprintf "Format value ('%s') in the XML file Pyramid is used",$taginterpolation);
        $params->{formatCode} = $tagformat;
    }

    # SAMPLESPERPIXEL  
    my $tagsamplesperpixel = $root->findnodes('channels')->to_literal;
    if ($tagsamplesperpixel eq '') {
        ERROR (sprintf "Can not extract 'channels' in the XML file Pyramid !");
        return FALSE;
    } else {
        INFO (sprintf "Samples per pixel value ('%s') in the XML file Pyramid is used",$tagsamplesperpixel);
        $params->{samplesperpixel} = $tagsamplesperpixel;
    }

    # load pyramid level
    my @levels = $root->getElementsByTagName('level');
    
    # read image directory name in the old pyramid, using a level
    my $level = $levels[0];
    my @directories = File::Spec->splitdir($level->findvalue('baseDir'));
    # <baseDir> : rel_datapath_from_desc/dir_image/level
    #                                       -2      -1
    $self->{dir_image} = $directories[-2];

    # read mask directory name in the old pyramid, using a level, if exists
    my $maskPath = $level->findvalue('mask/baseDir');
    if ($maskPath ne '') {
        @directories = File::Spec->splitdir($maskPath);
        # <baseDir> : rel_datapath_from_desc/dir_mask/level
        #                                       -2      -1
        $self->{dir_mask} = $directories[-2];
        INFO("Updated pyramid contains masks, new one will use them and generate masks too");
    }
    
    # read nodata directory name in the old pyramid, using a level
    @directories = File::Spec->splitdir($level->findvalue('nodata/filePath'));
    # <filePath> : rel_datapath_from_desc/dir_nodata/level/nd.tif
    #                                        -3       -2     -1
    $self->{dir_nodata} = $directories[-3];

    foreach my $v (@levels) {

        my $tagtm       = $v->findvalue('tileMatrix');
        my @tagsize     =  (
                             $v->findvalue('tilesPerWidth'),
                             $v->findvalue('tilesPerHeight')
                           );
        my $tagdirdepth = $v->findvalue('pathDepth');
        my @taglimit    = (
                            $v->findvalue('TMSLimits/minTileRow'),
                            $v->findvalue('TMSLimits/maxTileRow'),
                            $v->findvalue('TMSLimits/minTileCol'),
                            $v->findvalue('TMSLimits/maxTileCol')
                          );
        #
        my $imageDir = File::Spec->catdir($self->getNewDataDir(), $self->getDirImage(), $tagtm );
        #
        my $nodataDir = File::Spec->catdir($self->getNewDataDir(), $self->getDirNodata(), $tagtm );
        #
        my $maskDir = undef;
        if ($self->ownMasks()) {
            $maskDir = File::Spec->catdir($self->getNewDataDir(), $self->getDirMask(), $tagtm );
        }
        #
        my $levelOrder = $self->getOrderfromID($tagtm);
        if (! defined $levelOrder) {
            ERROR ("Level ID in the old pyramid's descriptor unknown by the TMS");
            return FALSE;
        }
        my $objLevel = BE4::Level->new({
            id                => $tagtm,
            order             => $levelOrder,
            dir_image         => $imageDir,
            dir_nodata        => $nodataDir,
            dir_mask          => $maskDir, # Can be undefined
            size              => [$tagsize[0],$tagsize[1]],
            dir_depth         => $tagdirdepth,
            limits            => [$taglimit[0],$taglimit[1],$taglimit[2],$taglimit[3]],
        });
            

        if (! defined $objLevel) {
            ERROR(sprintf "Can not load the pyramid level : '%s'", $tagtm);
            return FALSE;
        }

        $self->addLevel($tagtm,$objLevel);

        # same for each level
        $self->{dir_depth}  = $tagdirdepth;
        $self->{image_width}  = $tagsize[0];
        $self->{image_height} = $tagsize[1];
    }

    #
    if (! scalar %{$self->{levels}}) {
        ERROR ("List of Level Pyramid is empty !");
        return FALSE;
    }

    return TRUE;
}

=begin nd
Function: readCachePyramid

Browse old cache. We store images (data and nodata) in a file and broken symbolic links in an array. This function is needed if the ancestor pyramid doesn't own a content list.

Parameters (list):
    cachedir - string - Root directory to browse.
    listpyramid - string - File path, where to write files' list.
    
See Also:
    <findImages> 
=cut
sub readCachePyramid {
    my $self     = shift;
    my $cachedir = shift; # old cache directory by default !
    my $listpyramid = shift;
    
    TRACE("Reading cache of pyramid...");
  
    if (-f $listpyramid) {
        WARN(sprintf "Cache list ('%s') exists in temporary directory, overwrite it !", $listpyramid);
    }
    
    if (! -d dirname($listpyramid)) {
        eval { mkpath([dirname($listpyramid)]); };
        if ($@) {
            ERROR(sprintf "Can not create the old cache list directory '%s' : %s !",dirname($listpyramid), $@);
            return FALSE;
        }
    }
    
    # We list:
    #   - old cache files (write in the file $LIST)
    #   - old caches' roots (store in %cacheRoots)
    #   - old cache broken links (store in @brokenlinks)
    
    my $LIST;

    if (! open $LIST, ">", $listpyramid) {
        ERROR(sprintf "Cannot open (to write) old cache list file : %s",$listpyramid);
        return FALSE;
    }

    my $dir = File::Spec->catdir($cachedir);
    my @brokenlinks;
    my %cacheRoots;
    
    if (! $self->findImages($dir, $LIST, \@brokenlinks, \%cacheRoots)) {
        ERROR("An error on searching into the cache structure !");
        return FALSE;
    }
    
    close $LIST;
    
    # Have we broken links ?
    if (scalar @brokenlinks) {
        ERROR("Some links are broken in directory cache !");
        return FALSE;
    }

    
    # We write at the top of the list file, caches' roots, using Tie library
    
    my @list;
    if (! tie @list, 'Tie::File', $listpyramid) {
        ERROR(sprintf "Cannot write the header of old cache list file : %s",$listpyramid);
        return FALSE;
    }
    
    unshift @list,"#";
    
    while( my ($root,$rootID) = each(%cacheRoots) ) {
        unshift @list,(sprintf "%s=%s",$rootID,$root);
    }
    
    untie @list;
  
    return TRUE;
}

=begin nd
Function: findImages

Recursive method to browse a file tree structure. Store directories, images (data and nodata) and broken symbolic links.

Parameters (list):
    directory - string - Root directory to browse.
    LIST - stream - Stream to the file, in which we write old cache list (target files, no link).
    brokenlinks - string array reference -  Filled with broken links.
    cacheroots - string hash reference - Filled with different pyramids' roots and the corresponding identifiant.
=cut
sub findImages {
    my $self      = shift;
    my $directory = shift;
    my $LIST = shift;
    my $brokenlinks = shift;
    my $cacheroots = shift;
    
    TRACE(sprintf "Searching node in %s\n", $directory);
    
    my $pyr_datapath = $self->getNewDataDir();
    
    if (! opendir (DIR, $directory)) {
        ERROR("Can not open directory cache (%s) ?",$directory);
        return FALSE;
    }
    
    foreach my $entry (readdir DIR) {
        
        next if ($entry =~ m/^\.{1,2}$/);
        
        my $pathentry = File::Spec->catfile($directory, $entry);
        
        my $realName;
        
        if ( -d $pathentry) {
            TRACE(sprintf "DIR:%s\n",$pathentry);
            # recursif
            if (! $self->findImages($pathentry, $LIST, $brokenlinks, $cacheroots)) {
                ERROR("Can not search in directory cache (%s) ?",$pathentry);
                return FALSE;
            }
            next;
        }
        
        elsif( -f $pathentry && ! -l $pathentry) {
            TRACE(sprintf "%s\n",$pathentry);
            # It's the real file, not a link
            $realName = $pathentry;
        }
        
        elsif (  -f $pathentry && -l $pathentry) {
            TRACE(sprintf "%s\n",$pathentry);
            # It's a link
            
            my $linked   = File::Spec::Link->linked($pathentry);
            $realName = File::Spec::Link->full_resolve($linked);
            
            if (! defined $realName) {
                # FIXME : on fait le choix de mettre en erreur le traitement dès le premier lien cassé
                # ou liste exaustive des liens cassés ?
                WARN(sprintf "This tile '%s' may be a broken link in %s !\n",$entry, $directory);
                push @$brokenlinks,$entry;
                return TRUE;
            }         
        }
        
        # We extract from the old tile path, the cache name (without the old cache root path)
        my @directories = File::Spec->splitdir($realName);
        # $realName : abs_datapath/dir_image/level/XY/XY/XY.tif
        #                             -5      -4  -3 -2   -1
        #                     => -(3 + dir_depth)
        #    OR
        # $realName : abs_datapath/dir_nodata/level/nd.tif
        #                              -3      -2     -1
        #                           => - 3
        my $deb = -3;
            
        $deb -= $self->{dir_depth} if ($directories[-3] ne $self->{dir_nodata});
        
        my @indexName = ($deb..-1);
        my @indexRoot = (0..@directories+$deb-1);
        
        my $name = File::Spec->catdir(@directories[@indexName]);
        my $root = File::Spec->catdir(@directories[@indexRoot]);
        
        my $rootID;
        if (exists $cacheroots->{$root}) {
            $rootID = $cacheroots->{$root};
        } else {
            $rootID = scalar (keys %{$cacheroots});
            $cacheroots->{$root} = $rootID;
        }

        printf $LIST "%s\n", File::Spec->catdir($rootID,$name);
    }
    
    return TRUE;
}

=begin nd
Function: isUpdateMode

Tests if the value for parameter 'update_mode' is allowed.

Parameters (list):
    updateModeValue - string - chosen value for the mode of reference to the old pyrammid cache files
=cut
sub isUpdateMode {
    my $updateModeValue = shift;

    TRACE;
    
    if (! defined $updateModeValue) {
        ERROR(sprintf "Checking the validity of update_mode value : the value is not defined inside the test !");
        return FALSE;
    }

    foreach (@{UPDATE_MODES}) {
        if ($updateModeValue eq $_) {
            return TRUE;
        }
    }
    return FALSE;
}

####################################################################################################
#                              Group: Level and limits methods                                     #
####################################################################################################

=begin nd
Function: updateLevels

Determine top and bottom for the new pyramid and create Level objects.

Parameters (list):
    DSL - <DataSourceLoader> - Data sources, to determine extrem levels.
    topID - string - Optionnal, top level ID from the 'pyramid' section in the configuration file
=cut
sub updateLevels {
    my $self = shift;
    my $DSL = shift;
    my $topID = shift;
    
    # update datasources top/bottom levels !
    my ($bottomOrder,$topOrder) = $DSL->updateDataSources($self->getTileMatrixSet, $topID);
    if ($bottomOrder == -1) {
        ERROR("Cannot determine top and bottom levels, from data sources.");
        return FALSE;
    }
    
    INFO (sprintf "Bottom level order : %s, top level order : %s", $bottomOrder, $topOrder);

    if (! $self->createLevels($bottomOrder,$topOrder)) {
        ERROR("Cannot create Level objects for the new pyramid.");
        return FALSE;
    }
    
    return TRUE
}

=begin nd
Function: createLevels

Create all objects Level between the global top and the bottom levels (from data sources) for the new pyramid.

If there are an old pyramid, some levels already exist. We don't create twice the same level.

Parameters (list):
    bottomOrder - integer - Bottom level order
    topOrder - integer - Top level order
=cut
sub createLevels {
    my $self = shift;
    my $bottomOrder = shift;
    my $topOrder = shift;

    TRACE();
    
    my $objTMS = $self->getTileMatrixSet;
    if (! defined $objTMS) {
        ERROR("We need a TMS to create levels.");
        return FALSE;
    }

    my $tilesperwidth = $self->getTilesPerWidth();
    my $tilesperheight = $self->getTilesPerHeight();
    
    # Create all level between the bottom and the top
    for (my $order = $bottomOrder; $order <= $topOrder; $order++) {

        my $ID = $self->getIDfromOrder($order);
        if (! defined $ID) {
            ERROR(sprintf "Cannot identify ID for the order %s !",$order);
            return FALSE;
        }

        if (exists $self->{levels}->{$ID}) {
            # this level already exists (from the old pyramid). We have not to remove informations (like extrem tiles)
            next;
        }

        # base dir image
        my $imageDir = File::Spec->catdir($self->getNewDataDir(), $self->getDirImage(), $ID);

        # base dir nodata
        my $nodataDir = File::Spec->catdir($self->getNewDataDir(), $self->getDirNodata(), $ID);

        # base dir mask
        my $maskDir = undef;
        if ($self->ownMasks()) {
            $maskDir = File::Spec->catdir($self->getNewDataDir(), $self->getDirMask(), $ID );
        }

        # params to level
        my $params = {
            id                => $ID,
            order             => $order,
            dir_image         => $imageDir,
            dir_nodata        => $nodataDir,
            dir_mask          => $maskDir,
            size              => [$tilesperwidth, $tilesperheight],
            dir_depth         => $self->getDirDepth(),
        };
        my $objLevel = BE4::Level->new($params);

        if(! defined  $objLevel) {
            ERROR("Can not create the level '$ID' !");
            return FALSE;
        }

        if (! $self->addLevel($ID, $objLevel)) {
            ERROR("Can not add the level '$ID' !");
            return FALSE;
        }
    }

    return TRUE;
}

=begin nd
Function: addLevel

Store the Level object in the Pyramid object. Return an error if the level already exists.

Parameters
    level - string - TM identifiant
    objLevel - <Level> - Level object to store
=cut
sub addLevel {
    my $self = shift;
    my $level = shift;
    my $objLevel = shift;

    TRACE();
    
    if(! defined  $level || ! defined  $objLevel) {
        ERROR (sprintf "Level ID or Level object is undefined.");
        return FALSE;
    }
    
    if (ref ($objLevel) ne "BE4::Level") {
        ERROR (sprintf "We must have a Level object for the level $level.");
        return FALSE;
    }
    
    if (exists $self->{levels}->{$level}) {
        ERROR (sprintf "We have already a Level object for the level $level.");
        return FALSE;
    }

    $self->{levels}->{$level} = $objLevel;

    return TRUE;
}

=begin nd
Function: updateTMLimits

Compare old extrems rows/columns of the given level with the news and update values.

Parameters (list):
    level - string - Level ID whose extrems have to be updated with following bbox
    bbox - double array - [xmin,ymin,xmax,ymax], to update TM limits
=cut
sub updateTMLimits {
    my $self = shift;
    my ($level,@bbox) = @_;

    TRACE();
    
    # We calculate extrem TILES. x -> i = column; y -> j = row
    my $tm = $self->getTileMatrixSet->getTileMatrix($level);
    
    my $iMin = $tm->xToColumn($bbox[0]);
    my $iMax = $tm->xToColumn($bbox[2]);
    my $jMin = $tm->yToRow($bbox[3]);
    my $jMax = $tm->yToRow($bbox[1]);
    
    # order in updateExtremTiles : row min, row max, col min, col max
    $self->getLevel($level)->updateExtremTiles($jMin,$jMax,$iMin,$iMax);

}

####################################################################################################
#                                  Group: Pyramid's elements writers                               #
####################################################################################################

=begin nd
Function: writeConfPyramid

Export the Pyramid object to XML format, write the pyramid's descriptor (pyr_desc_path/pyr_name_new.pyr). Use Level XML export. Levels are written in descending order, from worst to best resolution.

=cut
sub writeConfPyramid {
    my $self = shift;

    TRACE;
    
    # parsing template
    my $parser = XML::LibXML->new();

    my $doctpl = eval { $parser->parse_string($STRPYRTMPLT); };
    if (!defined($doctpl) || $@) {
        ERROR(sprintf "Can not parse template file of pyramid : %s !", $@);
        return FALSE;
    }
    my $strpyrtmplt = $doctpl->toString(0);
  
    my $descriptorFile = $self->getNewDescriptorFile();
    my $descriptorDir = dirname($descriptorFile);
  
    #
    my $tmsname = $self->getTmsName();
    $strpyrtmplt =~ s/__TMSNAME__/$tmsname/;
    #
    my $formatimg = $self->getFormatCode; # ie TIFF_RAW_INT8 !
    $strpyrtmplt  =~ s/__FORMATIMG__/$formatimg/;
    #  
    my $channel = $self->getSamplesPerPixel();
    $strpyrtmplt =~ s/__CHANNEL__/$channel/;
    #  
    my $nodata = $self->getNodataValue();
    $strpyrtmplt =~ s/__NODATAVALUE__/$nodata/;
    #  
    my $interpolation = $self->getInterpolation();
    $strpyrtmplt =~ s/__INTERPOLATION__/$interpolation/;
    #  
    my $photometric = $self->getPhotometric;
    $strpyrtmplt =~ s/__PHOTOMETRIC__/$photometric/;
    
    my @levels = sort {$a->getOrder <=> $b->getOrder} ( values %{$self->getLevels});

    for (my $i = scalar @levels -1; $i >= 0; $i--) {
        # we write levels in pyramid's descriptor from the top to the bottom
        my $levelXML = $levels[$i]->exportToXML($descriptorDir);
        $strpyrtmplt =~ s/<!-- __LEVELS__ -->\n/$levelXML/;
    }
    
    $strpyrtmplt =~ s/<!-- __LEVELS__ -->\n//;
    $strpyrtmplt =~ s/^$//g;
    $strpyrtmplt =~ s/^\n$//g;
    
    if (! $self->isNewPyramid && $self->getUpdateMode() eq "inject") {
        INFO("File Pyramid ('$descriptorFile') is (over)write : injection mode !");
    } elsif (-f $descriptorFile) {
        ERROR(sprintf "File Pyramid ('%s') exist, can not overwrite it ! ", $descriptorFile);
        return FALSE;
    }

    if (! -d $descriptorDir) {
        DEBUG (sprintf "Create the pyramid's descriptor directory '%s' !", $descriptorDir);
        eval { mkpath([$descriptorDir]); };
        if ($@) {
            ERROR(sprintf "Can not create the pyramid's descriptor directory '%s' : %s !", $descriptorDir , $@);
            return FALSE;
        }
    }
    
    if ( ! open(PYRAMID, ">", $descriptorFile) ) {
        ERROR("Cannot open $descriptorFile to write it : $!");
        return FALSE;
    }
    #
    print PYRAMID $strpyrtmplt;
    #
    close(PYRAMID);

    return TRUE;
}

=begin nd
Function: writeListPyramid

Write the pyramid list.

If ancestor:
    - transpose old pyramid directories in the new pyramid (using the pyramid list).
    - create symbolic links toward old pyramid tiles.
    - create the new pyramid list (just with unchanged images).
    - remove roots which are no longer used

If new pyramid:
    - create the new pyramid list : just the root 0.

Parameters (list):
    forest - <Forest> - Forest linked to the pyramid, to test if an image is present in the new pyramid.
=cut
sub writeListPyramid {
    my $self = shift;
    my $forest = shift;
    my $path_temp = shift;

    TRACE;

    my $newcachepyramid = $self->getNewDataDir;
    
    my $newcachelisttmp = File::Spec->catfile($path_temp,$self->getNewName(),$self->getNewName()."_tmp.list");;
    
    my $newcachelist = $self->getNewListFile;
    if (-f $newcachelist && ($self->isNewPyramid() || $self->getUpdateMode() ne "inject")) {
        ERROR(sprintf "New pyramid list ('%s') exist, can not overwrite it ! ", $newcachelist);
        return FALSE;
    }
    
    my $dir = dirname($newcachelist);
    if (! -d $dir) {
        DEBUG (sprintf "Create the pyramid list directory '%s' !", $dir);
        eval { mkpath([$dir]); };
        if ($@) {
            ERROR(sprintf "Can not create the pyramid list directory '%s' : %s !", $dir , $@);
            return FALSE;
        }
    }
    
    my $dirtmp = dirname($newcachelisttmp);
    if (! -d $dir) {
        DEBUG (sprintf "Create the temporary pyramid list directory '%s' !", $dirtmp);
        eval { mkpath([$dirtmp]); };
        if ($@) {
            ERROR(sprintf "Can not create the temporary pyramid list directory '%s' : %s !", $dirtmp , $@);
            return FALSE;
        }
    }
    
    my $NEWLISTTMP;

    if (! open $NEWLISTTMP, ">", $newcachelisttmp) {
        ERROR(sprintf "Cannot open temporary new pyramid list file : %s",$newcachelisttmp);
        return FALSE;
    }
    
    printf $NEWLISTTMP "#\n";
    
    # Hash to bind ID and root directory
    my %newCacheRoots;
    
    # Hash to count root's uses (to remove useless roots)
    my %newCacheRootsUse;
    
    # search and create link for only new pyramid tile
    if (! $self->isNewPyramid) {
        
        my $OLDLIST;
        
        if (! open $OLDLIST, "<", $self->getOldListFile) {
            ERROR(sprintf "Cannot open old pyramid list file : %s",$self->getOldListFile);
            return FALSE;
        }
        
        while( my $cacheRoot = <$OLDLIST> ) {
            chomp $cacheRoot;
            if ($cacheRoot eq "#") {
                # separator between caches' roots and images
                last;
            }
            
            $cacheRoot =~ s/\s+//g; # we remove all spaces
            my @Root = split(/=/,$cacheRoot,-1);
            
            if (scalar @Root != 2) {
                ERROR(sprintf "Wrong formatted pyramid list (root definition) : %s",$cacheRoot);
                return FALSE;
            }
            
            # ID 0 is kept for the new pyramid root, all ID are incremented
            $newCacheRoots{$Root[0]+1} = $Root[1];
            $newCacheRootsUse{$Root[0]+1} = 0;
        }
        
        while( my $oldtile = <$OLDLIST> ) {
            chomp $oldtile;
                        
            # old tile path is split. Afterwards, only array will be used to compose paths
            my @directories = File::Spec->splitdir($oldtile);
            # @directories = [ RootID, dir_name, levelID, ..., XY.tif]
            #                    0        1        2      3  ... n
            
            # ID 0 is kept for the new pyramid root, ID is incremented
            $directories[0]++;
            
            my ($level,$x,$y);

            if (! $self->ownMasks() && $directories[1] eq $self->{dir_mask}) {
                # On ne veut pas des masques dans la pyramide finale, donc on ne lie pas ceux de l'ancienne pyramide
                next;
            }            
            
            if ($directories[1] ne $self->{dir_nodata}) {
                $level = $directories[2];

                my $b36path = "";
                for (my $i = 3; $i < scalar @directories; $i++) {
                    $b36path .= $directories[$i]."/";
                }

                # Extension is removed
                $b36path =~ s/(\.tif|\.tiff|\.TIF|\.TIFF)//;
                ($x,$y) = BE4::Base36::b36PathToIndices($b36path);
            }
            
            if (! $forest->containsNode($level,$x,$y)) {
                # This image is not in the forest, it won't be modified by this generation.
                # We add it now to the list (real file path)
                my $newTileFileName = File::Spec->catdir(@directories);
                if ($self->getUpdateMode() eq 'hlink' || $self->getUpdateMode() eq 'copy' || $self->getUpdateMode() eq 'inject') {
                    $newTileFileName =~ s/^[0-9]+\//0\//;
                }
                printf $NEWLISTTMP "%s\n", $newTileFileName;
                # Root is used : we incremente its counter
                $newCacheRootsUse{$directories[0]}++;
            }
            
            if ($self->getUpdateMode() ne 'inject') {
                # In injection case, we don't create a new pyramid version : no link, no copy, nothing to do
            
                # We replace root ID with the root path, to obtain a real path.
                if (! exists $newCacheRoots{$directories[0]}) {
                    ERROR(sprintf "Old pyramid list uses an undefined root ID : %s",$directories[0]);
                    return FALSE;
                }
                $directories[0] = $newCacheRoots{$directories[0]};
                $oldtile = File::Spec->catdir(@directories);
                
                # We remove the root to replace it by the new pyramid root
                shift @directories;
                my $newtile = File::Spec->catdir($newcachepyramid,@directories);

                #create folders
                my $dir = dirname($newtile);
                
                if (! -d $dir) {
                    eval { mkpath([$dir]); };
                    if ($@) {
                        ERROR(sprintf "Can not create the pyramid directory '%s' : %s !",$dir, $@);
                        return FALSE;
                    }
                }

                if (! -f $oldtile || -l $oldtile) {
                    ERROR(sprintf "File path in the pyramid list does not exist or is a link : %s",$oldtile);
                    return FALSE;
                }
                
                my $reloldtile = File::Spec->abs2rel($oldtile, $dir);

                if ($self->getUpdateMode() eq 'slink') {
                    DEBUG(sprintf "Creating symbolic link from %s to %s", $oldtile, $newtile);
                    my $result = eval { symlink ($reloldtile, $newtile); };
                    if (! $result) {
                        ERROR (sprintf "The tile '%s' can not be soft linked to '%s' (%s)",$reloldtile,$newtile,$!);
                        return FALSE;
                    }
                } elsif ($self->getUpdateMode() eq 'hlink') {
                    DEBUG(sprintf "Creating hard link from %s to %s", $oldtile, $newtile);
                    my $result = eval { link ($oldtile, $newtile); };
                    if (! $result) {
                        ERROR (sprintf "The tile '%s' can not be hard linked to '%s' (%s)",$oldtile,$newtile,$!);
                        return FALSE;
                    }
                } elsif ($self->getUpdateMode() eq 'copy') {
                    DEBUG(sprintf "Copying tile from %s to %s", $newtile, $oldtile);
                    my $result = eval { copy($oldtile, $newtile); };
                    if (! $result) {
                        ERROR (sprintf "The tile '%s' can not be copied to '%s' (%s)",$oldtile,$newtile,$!);
                        return FALSE;
                    }
                } else {
                    ERROR (sprintf "Unknown update mode : '%s'",$self->getUpdateMode());
                    return FALSE;
                }
            }
            
        }
        
        close $OLDLIST;
    }
    
    close $NEWLISTTMP;
    
    # Now, we can write binding between ID and root, testing counter.
    # We write at the top of the list file, caches' roots, using Tie library
    my @NEWLISTTMP;
    if (! tie @NEWLISTTMP, 'Tie::File', $newcachelisttmp) {
        ERROR(sprintf "Cannot write the header of temporary new pyramid list file : %s",$newcachelisttmp);
        return FALSE;
    }
    
    if (! $self->isNewPyramid && $self->getUpdateMode() eq 'slink') {
        while( my ($rootID,$root) = each(%newCacheRoots) ) {
            if ($newCacheRootsUse{$rootID} > 0) {
                # Used roots are written in the header
                
                INFO (sprintf "%s is used %d times", $root, $newCacheRootsUse{$rootID});
                
                unshift @NEWLISTTMP,(sprintf "%s=%s",$rootID,$root);
            } else {
                INFO (sprintf "The old pyramid '%s' is no longer used.", $root)
            }
        }
    }
    
    # Root of the new pyramid (first position)
    unshift @NEWLISTTMP,"0=$newcachepyramid\n";
    
    untie @NEWLISTTMP;
    
    # On copie notre descripteur de pyramide temporaire au bon endroit
    my $return = `mv $newcachelisttmp $newcachelist`;
    if ($? != 0) {
        ERROR("Cannot move $newcachelisttmp -> $newcachelist : $!");
        return FALSE;
    }    

    return TRUE;
}

=begin nd
Function: writeCachePyramid

Write the Cache Directory Structure (CDS).

    - create an image directory for each level.
    - create a mask directory for each level, if asked.
    - create the nodata tile for each level, if not exists (add in the list).
=cut
sub writeCachePyramid {
    my $self = shift;

    TRACE;
    
    my $newcachelist = $self->getNewListFile;
    
    if (! -f $newcachelist) {
        ERROR(sprintf "New pyramid list ('%s') doesn't exist. We have to write list (header and links) before write pyramid.", $newcachelist);
        return FALSE;
    }
    
    my $NEWLIST;

    if (! open $NEWLIST, ">>", $newcachelist) {
        ERROR(sprintf "Cannot open new pyramid list file : %s",$newcachelist);
        return FALSE;
    }
    
    my %levels = %{$self->getLevels};
    foreach my $objLevel (values %levels) {
        # Create folders for data and nodata (metadata not implemented) if they don't exist
        ### DATA
        my $dataDir = $objLevel->getDirImage;
        if (! -d $dataDir) {
            eval { mkpath([$dataDir]); };
            if ($@) {
                ERROR(sprintf "Can not create the data directory '%s' : %s !", $dataDir , $@);
                return FALSE;
            }
        }
        ### MASK
        if ( $self->ownMasks() ) {
            my $maskDir = $objLevel->getDirMask;
            if (! -d $maskDir) {
                eval { mkpath([$maskDir]); };
                if ($@) {
                    ERROR(sprintf "Can not create the mask directory '%s' : %s !", $maskDir , $@);
                    return FALSE;
                }
            }
        }

        ### NODATA
        my $nodataDir = $objLevel->getDirNodata;
        my $nodataTilePath = File::Spec->catfile($nodataDir,$self->{nodata}->getNodataFilename);
        if (! -e $nodataTilePath) {

            my $width = $self->getTileMatrixSet->getTileWidth($objLevel->getID);
            my $height = $self->getTileMatrixSet->getTileHeight($objLevel->getID);

            if (! $self->{nodata}->createNodata($nodataDir,$width,$height,$self->getCompression)) {
                ERROR (sprintf "Impossible to create the nodata tile for the level %i !",$objLevel->getID);
                return FALSE;
            }
            
            printf $NEWLIST "%s\n", File::Spec->catdir("0",$self->getDirNodata,$objLevel->getID,$self->{nodata}->getNodataFilename);
        }
    }
    
    close $NEWLIST;

    return TRUE;
  
}

####################################################################################################
#                                Group: Getters - Setters                                          #
####################################################################################################

###################### Outputs ######################

# Function: ownMasks
sub ownMasks {
    my $self = shift;
    return $self->{own_masks};
}

# Function: ownMetadata
sub ownMetadata {
    my $self = shift;
    return (defined $self->{dir_metadata});
}

#################### New pyramid ####################

# Function: isNewPyramid
sub isNewPyramid {
    my $self = shift;
    return (! defined $self->getOldName);
}

# Function: getNewName
sub getNewName {
    my $self = shift;    
    return $self->{new_pyramid}->{name};
}

# Function: getNewDescriptorFile
sub getNewDescriptorFile {
    my $self = shift;    
    return File::Spec->catfile($self->{new_pyramid}->{desc_path}, $self->{new_pyramid}->{name}.".pyr");
}

# Function: getNewDescriptorDir
sub getNewDescriptorDir {
    my $self = shift;    
    return $self->{new_pyramid}->{desc_path};
}

# Function: getNewListFile
sub getNewListFile {
    my $self = shift;
    
    if (! defined $self->{new_pyramid}->{content_path}) {
        $self->{new_pyramid}->{content_path} =
            File::Spec->catfile($self->{new_pyramid}->{desc_path}, $self->{new_pyramid}->{name}.".list");
    }
    
    return $self->{new_pyramid}->{content_path};
}


# Function: getNewDataDir
sub getNewDataDir {
    my $self = shift;    
    return File::Spec->catfile($self->{new_pyramid}->{data_path}, $self->{new_pyramid}->{name});
}

#################### Old pyramid ####################

# Function: getOldName
sub getOldName {
    my $self = shift;    
    return $self->{old_pyramid}->{name};
}

# Function: getOldDescriptorFile
sub getOldDescriptorFile {
    my $self = shift;
    return File::Spec->catfile($self->{old_pyramid}->{desc_path}, $self->{old_pyramid}->{name}.".pyr");
}

# Function: getOldListFile
sub getOldListFile {
    my $self = shift;
    
    if (! defined $self->{old_pyramid}->{content_path}) {
        $self->{old_pyramid}->{content_path} =
            File::Spec->catfile($self->{old_pyramid}->{desc_path}, $self->{old_pyramid}->{name}.".list");
    }
    
    return $self->{old_pyramid}->{content_path};
}

# Function: getOldDataDir
sub getOldDataDir {
    my $self = shift;
    return File::Spec->catfile($self->{old_pyramid}->{data_path}, $self->{old_pyramid}->{name});
}

# Function: getUpdateMode
sub getUpdateMode {
    my $self = shift;    
    return $self->{old_pyramid}->{update_mode};
}

#################### TMS ####################

# Function: getTmsName
sub getTmsName {
    my $self = shift;
    return $self->{tms}->getName();
}

# Function: getSRS
sub getSRS {
    my $self = shift;
    return $self->{tms}->getSRS();
}

# Function: getTileMatrixSet
sub getTileMatrixSet {
    my $self = shift;
    return $self->{tms};
}

############## Directories #############

=begin nd
Function: getDirImage

Returns image directory, just ethe name or the complete path

Examples:
    - $objPyr->getDirImage() returns "IMAGE"
    - $objPyr->getDirImage(FALSE) returns "IMAGE"
    - $objPyr->getDirImage(TRUE) returns "/home/ign/PYRAMID/IMAGE"

Parameters (list):
    absolute - boolean - If we want complete directory path. Optionnal, FALSE by default.
=cut
sub getDirImage {
    my $self = shift;
    my $complete = shift;
    
    return $self->{dir_image} if (! defined $complete || ! $complete);
    return File::Spec->catfile($self->getNewDataDir, $self->{dir_image});
}

=begin nd
Function: getDirMask

Returns mask directory, just the name or the complete path

Examples:
    - $objPyr->getDirMask() returns "MASK"
    - $objPyr->getDirMask(FALSE) returns "MASK"
    - $objPyr->getDirMask(TRUE) returns "/home/ign/PYRAMID/MASK"

Parameters (list):
    absolute - boolean - If we want complete directory path. Optionnal, FALSE by default.
=cut
sub getDirMask {
    my $self = shift;
    my $complete = shift;
    
    return $self->{dir_mask} if (! defined $complete || ! $complete);
    return File::Spec->catfile($self->getNewDataDir, $self->{dir_mask});
}

=begin nd
Function: getDirNodata

Returns nodata directory, just the name or the complete path

Examples:
    - $objPyr->getDirNodata() returns "NODATA"
    - $objPyr->getDirNodata(FALSE) returns "NODATA"
    - $objPyr->getDirNodata(TRUE) returns "/home/ign/PYRAMID/NODATA"

Parameters (list):
    absolute - boolean - If we want complete directory path. Optionnal, FALSE by default.
=cut
sub getDirNodata {
    my $self = shift;
    my $complete = shift;
    
    return $self->{dir_nodata} if (! defined $complete || ! $complete);
    return File::Spec->catfile($self->getNewDataDir, $self->{dir_nodata});
}

# Function: getDirDepth
sub getDirDepth {
    my $self = shift;
    return $self->{dir_depth};
}

##### Pyramid's images' specifications ######

# Function: getInterpolation
sub getInterpolation {
    my $self = shift;
    return $self->{pyrImgSpec}->getInterpolation;
}

# Function: getGamma
sub getGamma {
    my $self = shift;
    return $self->{pyrImgSpec}->getGamma;
}

# Function: getCompression
sub getCompression {
    my $self = shift;
    return $self->{pyrImgSpec}->getCompression;
}

# Function: getCompressionOption
sub getCompressionOption {
    my $self = shift;
    return $self->{pyrImgSpec}->getCompressionOption;
}

# Function: getFormatCode
sub getFormatCode {
    my $self = shift;
    return $self->{pyrImgSpec}->getFormatCode;
}

# Function: getPixel
sub getPixel {
    my $self = shift;
    return $self->{pyrImgSpec}->getPixel;
}

# Function: getSamplesPerPixel
sub getSamplesPerPixel {
    my $self = shift;
    return $self->{pyrImgSpec}->getPixel->getSamplesPerPixel;
}

# Function: getPhotometric
sub getPhotometric {
    my $self = shift;
    return $self->{pyrImgSpec}->getPixel->getPhotometric;
}

# Function: getBitsPerSample
sub getBitsPerSample {
    my $self = shift;
    return $self->{pyrImgSpec}->getPixel->getBitsPerSample;
}

# Function: getSampleFormat
sub getSampleFormat {
    my $self = shift;
    return $self->{pyrImgSpec}->getPixel->getSampleFormat;
}

################## Nodata ###################

# Function: getNodata
sub getNodata {
    my $self = shift;
    return $self->{nodata};
}

# Function: getNodataValue
sub getNodataValue {
    my $self = shift;
    return $self->{nodata}->getValue;
}

################### Levels ##################

# Function: getTopOrder
sub getTopOrder {
    my $self = shift;
    
    my @levels = sort {$a->getOrder <=> $b->getOrder} ( values %{$self->getLevels});
    return $levels[-1]->getOrder;
}

# Function: getBottomOrder
sub getBottomOrder {
    my $self = shift;
    
    my @levels = sort {$a->getOrder <=> $b->getOrder} ( values %{$self->getLevels});
    return $levels[0]->getOrder;
}

=begin nd
Function: getLevel

Parameters (list):
    level - string - Level ID
=cut
sub getLevel {
    my $self = shift;
    my $level = shift;
    return $self->{levels}->{$level};
}

# Function: getLevels
sub getLevels {
    my $self = shift;
    return $self->{levels};
}

=begin nd
Function: getOrderfromID

Returns the tile matrix order from the ID.
    - 0 (bottom level, smallest resolution)
    - NumberOfTM-1 (top level, biggest resolution).

Parameters (list):
    ID - string - Level identifiant, whose order we want.
=cut
sub getOrderfromID {
    my $self = shift;
    my $ID = shift;
    return $self->getTileMatrixSet()->getOrderfromID($ID);
}

=begin nd
Function: getIDfromOrder

Returns the tile matrix ID from the ascending resolution order (integer).
    - 0 (bottom level, smallest resolution)
    - NumberOfTM-1 (top level, biggest resolution).

Parameters (list):
    order - integer - Level order, whose identifiant we want.
=cut
sub getIDfromOrder {
    my $self = shift;
    my $order = shift;
    return $self->getTileMatrixSet->getIDfromOrder($order);
}

=begin nd
Function: getCacheImageSize

Returns the pyramid's image's pixel width and height as the double list (width, height), for a given level.

Parameters (list):
    level - string - Level ID
=cut
sub getCacheImageSize {
    my $self = shift;
    my $level = shift;
    return ($self->getCacheImageWidth($level), $self->getCacheImageHeight($level));
}

=begin nd
Function: getCacheImageWidth

Returns the pyramid's image's pixel width, for a given level.

Parameters (list):
    level - string - Level ID
=cut
sub getCacheImageWidth {
    my $self = shift;
    my $level = shift;
    # width of cache image in pixel for a defined level !
    return $self->getTilesPerWidth * $self->getTileWidth($level);
}

=begin nd
Function: getCacheImageHeight

Returns the pyramid's image's pixel height, for a given level.

Parameters (list):
    level - string - Level ID
=cut
sub getCacheImageHeight {
    my $self = shift;
    my $level = shift;
    # height of cache image in pixel for a defined level !
    return $self->getTilesPerHeight * $self->getTileHeight($level);
}

=begin nd
Function: getTileWidth

Returns the tile's pixel width, for a given level.

Parameters (list):
    level - string - Level ID
=cut
sub getTileWidth {
    my $self = shift;
    my $level = shift;
    return $self->getTileMatrixSet()->getTileWidth($level);
}

=begin nd
Function: getTileHeight

Returns the tile's pixel height, for a given level.

Parameters (list):
    level - string - Level ID
=cut
sub getTileHeight {
    my $self = shift;
    my $level = shift;
    return $self->getTileMatrixSet()->getTileHeight($level);
}

# Function: getTilesPerWidth
sub getTilesPerWidth {
    my $self = shift;
    return $self->{image_width};
}

# Function: getTilesPerHeight
sub getTilesPerHeight {
    my $self = shift;
    return $self->{image_height};
}

####################################################################################################
#                                Group: Export methods                                             #
####################################################################################################

=begin nd
Function: exportForDebug

Returns all pyramid's information. Useful for debug.

Example:
    (start code)
    Object BE4::Pyramid :
         New cache :
                - Name : JC
                - Descriptor path : /home/ign/desc
                - Data path : /home/ign/data
         Directories' name (depth = 2):
                - Data : IMAGE
                - Nodata : NODATA
                - Mask : MASK
         Image size (in pixel):
                - width : 16
                - height : 16
         Image components :
    Object BE4::PyrImageSpec :
         Global information :
                - Compression : raw
                - Compression option : none
                - Interpolation : bicubic
                - Gamma : 1
                - Format code : TIFF_RAW_INT8
         Pixel components :
    Object BE4::Pixel :
         Bits per sample : 8
         Photometric : rgb
         Sample format : uint
         Samples per pixel : 1


         TMS : LAMB93_10cm
         Number of levels : 0
    (end code)
=cut
sub exportForDebug {
    my $self = shift ;
    
    my $export = "";
    
    $export .= "\nObject BE4::Pyramid :\n";
    $export .= "\t New cache : \n";
    $export .= sprintf "\t\t- Name : %s\n", $self->{new_pyramid}->{name};
    $export .= sprintf "\t\t- Descriptor path : %s\n", $self->{new_pyramid}->{desc_path};
    $export .= sprintf "\t\t- Data path : %s\n", $self->{new_pyramid}->{data_path};
    
    if (defined $self->{old_pyramid}->{name}) {
        $export .= "\t This pyramid is an update\n";
        $export .= "\t Old cache : \n";
        $export .= sprintf "\t\t- Name : %s\n", $self->{old_pyramid}->{name};
        $export .= sprintf "\t\t- Descriptor path : %s\n", $self->{old_pyramid}->{desc_path};
        $export .= sprintf "\t\t- Data path : %s\n", $self->{old_pyramid}->{data_path};
    }

    $export .= sprintf "\t Directories' name (depth = %s): \n", $self->{dir_depth};
    $export .= sprintf "\t\t- Data : %s\n", $self->{dir_image};
    $export .= sprintf "\t\t- Nodata : %s\n", $self->{dir_nodata};
    $export .= sprintf "\t\t- Mask : %s\n", $self->{dir_mask};
    $export .= sprintf "\t\t- Metadata : %s\n", $self->{dir_metadata} if (defined $self->{dir_metadata});
    
    $export .= "\t Image size (in pixel):\n";
    $export .= sprintf "\t\t- width : %s\n", $self->{image_width};
    $export .= sprintf "\t\t- height : %s\n", $self->{image_height};
    
    $export .= sprintf "\t Image components : %s\n", $self->{pyrImgSpec}->exportForDebug;
    
    $export .= sprintf "\t TMS : %s\n", $self->{tms}->getName;
    
    $export .= sprintf "\t Number of levels : %s\n", scalar (keys %{$self->{levels}});
    
    return $export;
}

1;
__END__

=begin nd

Group: Details

Details about pyramid's working.

Pyramid's Descriptor:

Path template: pyr_desc_path/pyr_name_new.pyr

The pyramid descriptor is written in pyr_desc_path contains global informations about the cache.
    (start code)
    <?xml version='1.0' encoding='US-ASCII'?>
    <Pyramid>
        <tileMatrixSet>LAMB93_10cm</tileMatrixSet>
        <format>TIFF_RAW_INT8</format>
        <channels>3</channels>
        <nodataValue>FFFFFF</nodataValue>
        <interpolation>bicubic</interpolation>
        <photometric>rgb</photometric>
            .
        (levels)
            .
    </Pyramid>
    (end code)

And details about each level.
    (start code)
    <level>
        <tileMatrix>level_5</tileMatrix>
        <baseDir>./BDORTHO/IMAGE/level_5/</baseDir>
        <mask>
            <baseDir>./BDORTHO/MASK/level_5/</baseDir>
        </mask>
        <tilesPerWidth>16</tilesPerWidth>
        <tilesPerHeight>16</tilesPerHeight>
        <pathDepth>2</pathDepth>
        <nodata>
            <filePath>./BDORTHO/NODATA/level_5/nd.tif</filePath>
        </nodata>
        <TMSLimits>
            <minTileRow>365</minTileRow>
            <maxTileRow>368</maxTileRow>
            <minTileCol>1026</minTileCol>
            <maxTileCol>1035</maxTileCol>
        </TMSLimits>
    </level>
    (end code)

For a new pyramid, all level between top and bottom are saved into.

For an update, all level of the existing pyramid are duplicated and we add new levels (between top and bottom levels). For levels which are present in the old and the new pyramids, we update TMS limits.

Cache's List:

Path template: pyr_desc_path/pyr_name_new.list

Header : index for caches' roots (used by paths, in the following list). 0 is always for the new cache.
    (start code)
    0=/home/theo/TEST/BE4/PYRAMIDS/ORTHO_RAW_LAMB93_D075-E
    1=/home/theo/TEST/BE4/PYRAMIDS/ORTHO_RAW_LAMB93_D075-O
    (end code)

A separator : #, necessary.
    (start code)
    #
    (end code)

Images' list : just real files, links' targets.
    (start code)
    1/NODATA/11/nd.tif
    1/NODATA/7/nd.tif
    .
    .
    .
    1/IMAGE/16/00/1A/CV.tif
    1/IMAGE/17/00/2L/PR.tif
    .
    .
    .
    0/IMAGE/0/00/00/00.tif
    0/IMAGE/1/00/00/00.tif
    0/IMAGE/2/00/00/00.tif
    0/IMAGE/3/00/00/00.tif
    (end code)

The new cache's list is written by writeCachePyramid, using the old cache's list. The file is completed by Process, to add generated images.

Cache Directory Structure:

For a new pyramid, the directory structure is empty, only the level directory for images and directory and tile for nodata are written.
    (start code)
    pyr_data_path/
            |_ pyr_name_new/
                    |__dir_image/
                            |_ ID_LEVEL0/
                            |_ ID_LEVEL1/
                            |_ ID_LEVEL2/
                    |__dir_nodata/
                            |_ ID_LEVEL0/
                                    |_ nd.tif
                            |_ ID_LEVEL1/
                                    |_ nd.tif
                            |_ ID_LEVEL2/
                                    |_ nd.tif
    (end code)

For an existing pyramid, the directory structure is duplicated to the new pyramid with all file linked, thanks to the old cache list.
The kind of linking can be chosen between symbolic link (default), hard link (does not work if the new pyramid and the old one are stored in different file systems)
 and hard copy.
    (start code)
    pyr_data_path/
            |__pyr_name_new/
                    |__dir_image/
                            |_ ID_LEVEL0/
                                |_ 00/
                                    |_ 7F/
                                    |_ 7G/
                                        |_ CV.tif
                                |__ ...
                            |__ ID_LEVEL1/
                            |__ ID_LEVEL2/
                            |__ ...
                    |__dir_nodata/
                            |_ ID_LEVEL0/
                                    |_ nd.tif
                            |__ ID_LEVEL1/
                            |__ ID_LEVEL2/
                            |__ ...

    with
        ls -l CV.tif
        CV.tif -> /pyr_data_path_old/pyr_name_old/dir_image/ID_LEVEL0/7G/CV.tif
    and
        ls -l nd.tif
        nd.tif -> /pyr_data_path_old/pyr_name_old/dir_nodata/ID_LEVEL0/nd.tif
    (end code)

So be careful when you create a new tile in an updated pyramid, you have to test if the link exists, to use image as a background.

Rule Image/Directory Naming:

We consider the upper left corner coordinates (X,Y). We know the ground size of a cache image (do not mistake for a tile) : it depends on the level (defined in the TMS).

_For the level_
    - Resolution (2 m)
    - Tile pixel size: tileWidth and tileHeight (256 * 256)
    - Origin (upper left corner): X0,Y0 (0,12000000)

_For the cache_
    - image tile size: image_width and image_height (16 * 16)

GroundWidth = tileWidth * image_width * Resolution

GroundHeight = tileHeight * image_height * Resolution

Index X = int (X-X0)/GroundWidth

Index Y = int (Y0-Y)/GroundHeight

Index X base 36 (write with 3 number) = X2X1X0 (example: 0D4)

Index Y base 36 (write with 3 number) = Y2Y1Y0 (example: 18Z)

The image path, from the data root is : dir_image/levelID/X2Y2/X1Y1/X0Y0.tif (example: IMAGE/level_15/01/D8/4Z.tif)

=cut
