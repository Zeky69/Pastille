#!/bin/zsh
# Compile et assemble Pastille.app (signature ad-hoc).
#   ./build.sh           compile dans build/Pastille.app
#   ./build.sh install   compile, installe dans /Applications et relance Pastille depuis là
#   ./build.sh debug     compile en mode debug
#   ./build.sh release   compile, archive et signe build/Pastille-<version>.zip (+ .sig)
#   ./build.sh publish   idem, puis crée la release v<version> sur GitHub (gh) avec docs/releases/<version>.md
# La signature utilise la clé privée ~/.config/pastille/update-signing-key (voir Support/Release/sign-update.swift) :
# Pastille n'installe une mise à jour que si elle est signée par cette clé.
# Les tests (Tests/PastilleTests) passent d'abord : s'ils échouent, rien n'est compilé ni installé.
#   SKIP_TESTS=1 ./build.sh install   pour les sauter exceptionnellement
set -e -o pipefail
cd "$(dirname "$0")"
INSTALL=0
RELEASE=0
PUBLISH=0
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Support/Info.plist)
if [[ $PUBLISH == 1 || "${1:-}" == publish ]]; then
    # Publier ce qui est dans le dépôt, rien d'autre : modifications commitées et envoyées, notes écrites.
    [[ -z "$(git status --porcelain)" ]] || { echo "❌ Des modifications ne sont pas commitées."; exit 1; }
    git fetch --quiet origin
    [[ "$(git rev-parse HEAD)" == "$(git rev-parse @{u})" ]] || { echo "❌ Le commit n'est pas envoyé sur GitHub (git push)."; exit 1; }
    [[ -f docs/releases/$VERSION.md ]] || { echo "❌ Notes de version manquantes : docs/releases/$VERSION.md"; exit 1; }
    ! gh release view "v$VERSION" >/dev/null 2>&1 || { echo "❌ La release v$VERSION existe déjà : change la version dans Support/Info.plist."; exit 1; }
fi
CONFIG=release
case "${1:-}" in
    install) INSTALL=1 ;;
    release) RELEASE=1 ;;
    publish) RELEASE=1; PUBLISH=1 ;;
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

if [[ $RELEASE == 1 ]]; then
    # Archive comme le Finder (attributs et liens conservés), nommée d'après la version de Info.plist.
    ZIP=build/Pastille-$VERSION.zip
    rm -f $ZIP $ZIP.sig
    ditto -c -k --sequesterRsrc --keepParent $APP $ZIP
    swift Support/Release/sign-update.swift sign $ZIP >/dev/null
    # La clé qui signe doit être celle dont l'app connaît la partie publique.
    [[ "$(swift Support/Release/sign-update.swift public-key)" == \
       "$(/usr/libexec/PlistBuddy -c 'Print :PastilleUpdatePublicKey' Support/Info.plist)" ]] \
        || { echo "❌ La clé de signature ne correspond pas à PastilleUpdatePublicKey (Info.plist)."; exit 1; }
    echo "✅ $ZIP ($(du -h $ZIP | cut -f1 | tr -d ' ')) et sa signature $ZIP.sig"
    echo "   SHA-256 : $(shasum -a 256 $ZIP | cut -d' ' -f1)"
fi

if [[ $PUBLISH == 1 ]]; then
    gh release create "v$VERSION" $ZIP $ZIP.sig --title "Pastille $VERSION" \
        --notes-file docs/releases/$VERSION.md --target "$(git rev-parse HEAD)"
    echo "✅ Release v$VERSION publiée"
fi

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
