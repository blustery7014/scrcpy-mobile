#!/bin/bash

set -e;
set -x;

OUTPUT=$(cd $OUTPUT && pwd);
BUILD_DIR=$(mktemp -d -t SDL);
cd $BUILD_DIR;

curl -O https://www.libsdl.org/release/SDL2-2.0.22.tar.gz;
tar xzvf SDL*.tar.gz;

# Add Function SDL_UpdateCommandGeneration
echo "=> Add Function SDL_UpdateCommandGeneration"
echo "$(cat << EOF
void
SDL_UpdateCommandGeneration(SDL_Renderer *renderer) {
    renderer->render_command_generation++;
}
EOF
)" >> SDL2-*/src/render/SDL_render.c;

# Build iOS Libraries
echo "=> Building for iOS..";

xcodebuild clean build OTHER_CFLAGS="-fembed-bitcode" \
	BUILD_DIR=$BUILD_DIR/build/iphoneos/arm64 \
	ARCHS="arm64" \
	CONFIGURATION=Release \
    GCC_PREPROCESSOR_DEFINITIONS='CFRunLoopRunInMode=CFRunLoopRunInMode_fix' \
	-project SDL2-*/Xcode/SDL/SDL.xcodeproj -scheme "Static Library-iOS" -sdk iphoneos;
xcodebuild clean build OTHER_CFLAGS="-fembed-bitcode" \
	BUILD_DIR=$BUILD_DIR/build/iphonesimulator/x86_64 \
	ARCHS="x86_64" \
	CONFIGURATION=Release \
    GCC_PREPROCESSOR_DEFINITIONS='CFRunLoopRunInMode=CFRunLoopRunInMode_fix' \
	-project SDL2-*/Xcode/SDL/SDL.xcodeproj -scheme "Static Library-iOS" -sdk iphonesimulator;
xcodebuild clean build OTHER_CFLAGS="-fembed-bitcode" \
	BUILD_DIR=$BUILD_DIR/build/iphonesimulator/arm64 \
	ARCHS="arm64" \
	CONFIGURATION=Release \
    GCC_PREPROCESSOR_DEFINITIONS='CFRunLoopRunInMode=CFRunLoopRunInMode_fix' \
	-project SDL2-*/Xcode/SDL/SDL.xcodeproj -scheme "Static Library-iOS" -sdk iphonesimulator;

ls -la $BUILD_DIR/build/*/*/*/libSDL2.a;

echo "Copy staticlib...";

[[ -d $OUTPUT/iphoneos/arm64 ]] || mkdir -pv $OUTPUT/iphoneos/arm64;
cp -v $BUILD_DIR/build/iphoneos/arm64/*/libSDL2.a $OUTPUT/iphoneos/arm64/;

[[ -d $OUTPUT/iphonesimulator/arm64 ]] || mkdir -pv $OUTPUT/iphonesimulator/arm64;
cp -v $BUILD_DIR/build/iphonesimulator/arm64/*/libSDL2.a $OUTPUT/iphonesimulator/arm64/;

[[ -d $OUTPUT/iphonesimulator/x86_64 ]] || mkdir -pv $OUTPUT/iphonesimulator/x86_64;
cp -v $BUILD_DIR/build/iphonesimulator/x86_64/*/libSDL2.a $OUTPUT/iphonesimulator/x86_64/;

echo "Copy headers...";
[[ -d "$OUTPUT/include/SDL2" ]] || mkdir -pv $OUTPUT/include/SDL2;
cp -v SDL2-*/include/*.h $OUTPUT/include/SDL2;

[[ -d "$BUILD_DIR" ]] && rm -rf $BUILD_DIR;
