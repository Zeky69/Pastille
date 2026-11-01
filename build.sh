#!/bin/zsh
# Compile et assemble Pastille.app (signature ad-hoc).
set -e
cd "$(dirname "$0")"
CONFIG=${1:-release}
swift build -c $CONFIG
APP=build/Pastille.app
rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp .build/$CONFIG/Pastille $APP/Contents/MacOS/Pastille
cp Support/Info.plist $APP/Contents/Info.plist
# Lecteur « À l'écoute » (pochettes Apple Music), chargé par /usr/bin/perl.
clang -dynamiclib -fobjc-arc -O2 -framework Foundation -arch arm64 -arch x86_64 \
    -o $APP/Contents/Resources/NowPlaying.dylib Support/NowPlaying/NowPlaying.m
cp Support/NowPlaying/now-playing.pl $APP/Contents/Resources/
codesign --force --sign - $APP/Contents/Resources/NowPlaying.dylib
# Exigence fixe : macOS reconnaît la même app d'une compilation à l'autre et garde ses autorisations.
codesign --force --sign - -r='designated => identifier "com.macky.pastille"' $APP
echo "✅ $APP"
