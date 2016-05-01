#!/usr/bin/perl -w
# I'm assuming that you're running this on some kind of ASCII system, but
# it will generate EBCDIC too. (TODO)
use strict;
use Encode;
require 'regen/regen_lib.pl';

sub make_text {
    my ($chrmap, $letter, $unpredictable, $nocsum, $size, $condition) = @_;
    my $text = "    /* $letter */ $size";
    $text .= " | PACK_SIZE_UNPREDICTABLE" if $unpredictable;
    $text .= " | PACK_SIZE_CANNOT_CSUM"   if $nocsum;
    $text .= ",";

    if ($condition) {
        $text = "#if $condition
$text
#else
    0,
#endif";
    }
    return $text;
}

sub make_tables {
    my %arrays;

    my $chrmap = shift;
    foreach (@_) {
        my ($letter, $shriek, $unpredictable, $nocsum, $size, $condition) =
            /^([A-Za-z])(!?)\t(\S*)\t(\S*)\t([^\t\n]+)(?:\t+(.*))?$/ or
            die "Can't parse '$_'";

        $size = "sizeof($size)" unless $size =~ s/^=//;

        $arrays{$shriek ? 'shrieking' : 'normal'}{ord $chrmap->{$letter}} =
            make_text($chrmap, $letter,
                      $unpredictable, $nocsum, $size, $condition);
    }

    my $text = "STATIC const packprops_t packprops[512] = {\n";
    foreach my $arrayname (qw(normal shrieking)) {
        my $array = $arrays{$arrayname} ||
            die "No defined entries in $arrayname";
        $text .= "    /* $arrayname */\n";
        for my $ch (0..255) {
            $text .= $array->{$ch} || "    0,";
            $text .= "\n";
        }
    }
    # Join "0," entries together
    1 while $text =~ s/\b0,\s*\n\s*0,/0, 0,/g;
    # But split them up again if the sequence gets too long
    $text =~ s/((?:\b0, ){15}0,) /$1\n    /g;
    # Clean up final ,
    $text =~ s/,$//;
    $text .= "};";
    return $text;
}

my @lines = grep {
    s/#.*//;
    /\S/;
} <DATA>;

my %asciimap  = map {chr $_, chr $_} 0..255;

# Currently, all things generated by this on EBCDIC are alphabetics, whose
# positions are all the same regardless of code page, so any EBCDIC encoding
# will work; just choose one
my %ebcdicmap = map {chr $_, Encode::encode("posix-bc", chr $_)} 0..255;

my $fh = open_new('packsizetables.c', '>', { by => $0, from => 'its data'});

print $fh <<"EOC";
#if TYPE_IS_SHRIEKING != 0x100
   ++++shriek offset should be 256
#endif

typedef U8 packprops_t;
#if 'J'-'I' == 1
/* ASCII */
@{[make_tables (\%asciimap, @lines)]}
#else
/* EBCDIC (or bust) */
@{[make_tables (\%ebcdicmap, @lines)]}
#endif
EOC

read_only_bottom_close_and_rename($fh);

__DATA__
#Symbol	unpredictable
#		nocsum	size
c			char
C			unsigned char
W	*		unsigned char
U	*		char
s!			short
s			=SIZE16
S!			unsigned short
v			=SIZE16
n			=SIZE16
S			=SIZE16
v!			=SIZE16
n!			=SIZE16
i			int
i!			int
I			unsigned int
I!			unsigned int
j			=IVSIZE
J			=UVSIZE
l!			long
l			=SIZE32
L!			unsigned long
V			=SIZE32
N			=SIZE32
V!			=SIZE32
N!			=SIZE32
L			=SIZE32
p		*	char *
w	*	*	char
q			Quad_t	IVSIZE >= 8
Q			Uquad_t	IVSIZE >= 8
f			float
d			double
F			=NVSIZE
D			=LONG_DOUBLESIZE	defined(HAS_LONG_DOUBLE) && defined(USE_LONG_DOUBLE)
