all: adb-mobile libsdl ffmpeg scrcpy scrcpy-server ish

scrcpy-config:
	cd ../scrcpy && meson setup x --reconfigure --buildtype=release --strip -Db_lto=true -Dusb=false

mkdir-output:
	[[ ! -d libs ]] && mkdir -pv libs || echo ""

adb-mobile: mkdir-output
	make -C ../external/adb-mobile
	cp -av ../external/adb-mobile/output/iphoneos/arm64/libadb-full.a ./libs/iphoneos/arm64
	cp -av ../external/adb-mobile/output/iphonesimulator/arm64/libadb-full.a ./libs/iphonesimulator/arm64
	cp -av ../external/adb-mobile/output/iphonesimulator/x86_64/libadb-full.a ./libs/iphonesimulator/x86_64
	cp -av ../external/adb-mobile/output/include/adb_public.h ./libs/include

libsdl: mkdir-output
	OUTPUT=libs bash ./scripts/make-libsdl.sh

ffmpeg: mkdir-output
	OUTPUT=libs bash ./scripts/make-ffmpeg.sh

vncclient: mkdir-output
	for target in iphoneos/arm64:OS64 iphonesimulator/arm64:SIMULATORARM64 iphonesimulator/x86_64:SIMULATOR64; do \
		target=$$target output_dir=./libs bash scripts/make-vncclient.sh; \
	done

openssl:
	cd ../external/OpenSSL-for-iPhone && \
		./build-libssl.sh --disable-bitcode --targets="ios-sim-cross-x86_64 ios-sim-cross-arm64 ios-cross-arm64" && \
		cp -av ./bin/iPhoneSimulator*-x86_64.sdk/lib/*.a ../../porting/libs/iphonesimulator/x86_64 && \
		cp -av ./bin/iPhoneSimulator*-arm64.sdk/lib/*.a ../../porting/libs/iphonesimulator/arm64 && \
		cp -av ./bin/iPhoneOS*-arm64.sdk/lib/*.a ../../porting/libs/iphoneos/arm64;
	cp -av ../external/OpenSSL-for-iPhone/include/openssl ./libs/include;

scrcpy: scrcpy-config mkdir-output
	for target in iphoneos/arm64:OS64 iphonesimulator/arm64:SIMULATORARM64 iphonesimulator/x86_64:SIMULATOR64; do \
		target=$$target output_dir=./libs bash scripts/make-scrcpy.sh; \
	done
	cp -v include/*.h ./libs/include

scrcpy-server:
	set -x && \
	export SCRCPY_VERSION=3.1 && \
	export ANDROID_SDK_ROOT=~/Library/Android/sdk && \
	export JAVA_HOME="/opt/homebrew/opt/openjdk@17" && \
	export PATH="$$JAVA_HOME/bin:$$PATH" && \
	cd server && rm -rf scrcpy-* && \
	curl -o scrcpy.zip -L https://github.com/Genymobile/scrcpy/archive/refs/tags/v$$SCRCPY_VERSION.zip && \
	unzip scrcpy.zip && find src -name "*.java" -exec cp -v {} scrcpy-$$SCRCPY_VERSION/server/{} \; && \
	cd scrcpy-$$SCRCPY_VERSION && \
	meson setup x --buildtype=release --strip -Db_lto=true -Dcompile_app=false -Dcompile_server=true && \
	sed -ibak 's/exit/echo/g' server/scripts/build-wrapper.sh && \
	ninja -Cx -v && \
	find . -type f -name "scrcpy-server" -exec cp -v {} ../../../scrcpy-app/ADBClient/scrcpy-server \;

ish: mkdir-output
	# Create build directories
	mkdir -p build/ish/iphoneos-arm64
	mkdir -p build/ish/iphonesimulator-arm64
	mkdir -p build/ish/iphonesimulator-x86_64
	
	# Build for iphoneos/arm64
	xcodebuild -project ../external/ish/iSH.xcodeproj -target "iSH pre" -sdk iphoneos -arch arm64 CONFIGURATION_BUILD_DIR=$(PWD)/build/ish/iphoneos-arm64 ONLY_ACTIVE_ARCH=NO build
	xcodebuild -project ../external/ish/iSH.xcodeproj -target libiSHApp -sdk iphoneos -arch arm64 CONFIGURATION_BUILD_DIR=$(PWD)/build/ish/iphoneos-arm64 ONLY_ACTIVE_ARCH=NO build
	xcodebuild -project ../external/ish/iSH.xcodeproj -target libish -sdk iphoneos -arch arm64 CONFIGURATION_BUILD_DIR=$(PWD)/build/ish/iphoneos-arm64 ONLY_ACTIVE_ARCH=NO build
	xcodebuild -project ../external/ish/iSH.xcodeproj -target libfakefs -sdk iphoneos -arch arm64 CONFIGURATION_BUILD_DIR=$(PWD)/build/ish/iphoneos-arm64 ONLY_ACTIVE_ARCH=NO build
	xcodebuild -project ../external/ish/iSH.xcodeproj -target libish_emu -sdk iphoneos -arch arm64 CONFIGURATION_BUILD_DIR=$(PWD)/build/ish/iphoneos-arm64 ONLY_ACTIVE_ARCH=NO build
	xcodebuild -project ../external/ish/deps/libarchive.xcodeproj -target libarchive -sdk iphoneos -arch arm64 CONFIGURATION_BUILD_DIR=$(PWD)/build/ish/iphoneos-arm64 ONLY_ACTIVE_ARCH=NO build
	mkdir -p ./libs/iphoneos/arm64
	find build/ish/iphoneos-arm64 -name "*.a" -exec cp -v {} ./libs/iphoneos/arm64 \;
	
	# Build for iphonesimulator/arm64
	xcodebuild -project ../external/ish/iSH.xcodeproj -target "iSH pre" -sdk iphonesimulator -arch arm64 CONFIGURATION_BUILD_DIR=$(PWD)/build/ish/iphonesimulator-arm64 ONLY_ACTIVE_ARCH=NO build
	xcodebuild -project ../external/ish/iSH.xcodeproj -target libiSHApp -sdk iphonesimulator -arch arm64 CONFIGURATION_BUILD_DIR=$(PWD)/build/ish/iphonesimulator-arm64 ONLY_ACTIVE_ARCH=NO build
	xcodebuild -project ../external/ish/iSH.xcodeproj -target libish -sdk iphonesimulator -arch arm64 CONFIGURATION_BUILD_DIR=$(PWD)/build/ish/iphonesimulator-arm64 ONLY_ACTIVE_ARCH=NO build
	xcodebuild -project ../external/ish/iSH.xcodeproj -target libfakefs -sdk iphonesimulator -arch arm64 CONFIGURATION_BUILD_DIR=$(PWD)/build/ish/iphonesimulator-arm64 ONLY_ACTIVE_ARCH=NO build
	xcodebuild -project ../external/ish/iSH.xcodeproj -target libish_emu -sdk iphonesimulator -arch arm64 CONFIGURATION_BUILD_DIR=$(PWD)/build/ish/iphonesimulator-arm64 ONLY_ACTIVE_ARCH=NO build
	xcodebuild -project ../external/ish/deps/libarchive.xcodeproj -target libarchive -sdk iphonesimulator -arch arm64 CONFIGURATION_BUILD_DIR=$(PWD)/build/ish/iphonesimulator-arm64 ONLY_ACTIVE_ARCH=NO build
	mkdir -p ./libs/iphonesimulator/arm64
	find build/ish/iphonesimulator-arm64 -name "*.a" -exec cp -v {} ./libs/iphonesimulator/arm64 \;
	
	# Build for iphonesimulator/x86_64
	xcodebuild -project ../external/ish/iSH.xcodeproj -target "iSH pre" -sdk iphonesimulator -arch x86_64 CONFIGURATION_BUILD_DIR=$(PWD)/build/ish/iphonesimulator-x86_64 ONLY_ACTIVE_ARCH=NO build
	xcodebuild -project ../external/ish/iSH.xcodeproj -target libiSHApp -sdk iphonesimulator -arch x86_64 CONFIGURATION_BUILD_DIR=$(PWD)/build/ish/iphonesimulator-x86_64 ONLY_ACTIVE_ARCH=NO build
	xcodebuild -project ../external/ish/iSH.xcodeproj -target libish -sdk iphonesimulator -arch x86_64 CONFIGURATION_BUILD_DIR=$(PWD)/build/ish/iphonesimulator-x86_64 ONLY_ACTIVE_ARCH=NO build
	xcodebuild -project ../external/ish/iSH.xcodeproj -target libfakefs -sdk iphonesimulator -arch x86_64 CONFIGURATION_BUILD_DIR=$(PWD)/build/ish/iphonesimulator-x86_64 ONLY_ACTIVE_ARCH=NO build
	xcodebuild -project ../external/ish/iSH.xcodeproj -target libish_emu -sdk iphonesimulator -arch x86_64 CONFIGURATION_BUILD_DIR=$(PWD)/build/ish/iphonesimulator-x86_64 ONLY_ACTIVE_ARCH=NO build
	xcodebuild -project ../external/ish/deps/libarchive.xcodeproj -target libarchive -sdk iphonesimulator -arch x86_64 CONFIGURATION_BUILD_DIR=$(PWD)/build/ish/iphonesimulator-x86_64 ONLY_ACTIVE_ARCH=NO build
	mkdir -p ./libs/iphonesimulator/x86_64
	find build/ish/iphonesimulator-x86_64 -name "*.a" -exec cp -v {} ./libs/iphonesimulator/x86_64 \;

	# Copy headers
	mkdir -p ./libs/include/ish/{fs,kernel,util,emu}
	cp -av ../external/ish/fs/*.h ./libs/include/ish/fs
	cp -av ../external/ish/kernel/*.h ./libs/include/ish/kernel
	cp -av ../external/ish/util/*.h ./libs/include/ish/util
	cp -av ../external/ish/emu/*.h ./libs/include/ish/emu
	cp -av ../external/ish/misc.h ./libs/include/ish
	cp -av ../external/ish/debug.h ./libs/include/ish
