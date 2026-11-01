# Charge la bibliothèque de Pastille et appelle le mode demandé :
#   now-playing.pl <bibliothèque>                  instantané en JSON
#   now-playing.pl <bibliothèque> stream           une ligne JSON à chaque changement
#   now-playing.pl <bibliothèque> command <ordre>  toggle, next, previous ou seek:<secondes>
use DynaLoader;
my ($path, $mode, $argument) = @ARGV;
my %symbols = (stream => "pastille_stream", command => "pastille_command");
my $name = $symbols{$mode // ""} // "pastille_now_playing";
$ENV{PASTILLE_ARG} = $argument if defined $argument;
my $lib = DynaLoader::dl_load_file($path, 0) or die DynaLoader::dl_error();
my $sym = DynaLoader::dl_find_symbol($lib, $name) or die DynaLoader::dl_error();
&{DynaLoader::dl_install_xsub("main::run", $sym)}();
