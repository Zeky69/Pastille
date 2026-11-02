#!/bin/zsh
# Compile et assemble Pastille.app (signature ad-hoc).
#   ./build.sh           compile dans build/Pastille.app
#   ./build.sh install   compile, installe dans /Applications et relance Pastille depuis là
#   ./build.sh debug     compile en mode debug
# Les tests (Tests/PastilleTests) passent d'abord : s'ils échouent, rien n'est compilé ni installé.
#   SKIP_TESTS=1 ./build.sh install   pour les sauter exceptionnellement
set -e -o pipefail
cd "$(dirname "$0")"
INSTALL=0
CONFIG=release
case "${1:-}" in
    install) INSTALL=1 ;;
    debug) CONFIG=debug ;;
esac
if [[ "${SKIP_TESTS:-0}" != 1 ]]; then
    echo "🧪 Tests…"
    if ! swift test --quiet 2>&1 | tail -n 25; then
        echo "❌ Tests en échec : rien n'est installé."
        exit 1
    fi
fi
swift build -c $CONFIG
APP=build/Pastille.app
rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp .build/$CONFIG/Pastille $APP/Contents/MacOS/Pastille
cp Support/Info.plist $APP/Contents/Info.plist
# Icône (générée par Support/Icon/make-icon.swift).
cp Support/AppIcon.icns $APP/Contents/Resources/
# Lecteur « À l'écoute » (musique de n'importe quelle app), chargé par /usr/bin/perl.
clang -dynamiclib -fobjc-arc -O2 -framework Foundation -framework AppKit -arch arm64 -arch x86_64 \
    -o $APP/Contents/Resources/NowPlaying.dylib Support/NowPlaying/NowPlaying.m
cp Support/NowPlaying/now-playing.pl $APP/Contents/Resources/
codesign --force --sign - $APP/Contents/Resources/NowPlaying.dylib
# Exigence fixe : macOS reconnaît la même app d'une compilation à l'autre et garde ses autorisations.
codesign --force --sign - -r='designated => identifier "com.macky.pastille"' $APP
echo "✅ $APP"

if [[ $INSTALL == 1 ]]; then
    # On arrête la version qui tourne (et son lecteur « À l'écoute »), on remplace, on relance.
    pkill -x Pastille || true
    pkill -f "now-playing.pl.*stream" || true
    sleep 1
    rm -rf /Applications/Pastille.app
    ditto $APP /Applications/Pastille.app
    open /Applications/Pastille.app
    echo "✅ installée dans /Applications et relancée"
fi
