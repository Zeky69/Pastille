# Charge la bibliothèque de Pastille et affiche « À l'écoute » en JSON.
use DynaLoader;
my $lib = DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error();
my $sym = DynaLoader::dl_find_symbol($lib, "pastille_now_playing") or die DynaLoader::dl_error();
&{DynaLoader::dl_install_xsub("main::now_playing", $sym)}();
