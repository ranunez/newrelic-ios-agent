#!/usr/bin/env bash
xcodebuild -create-xcframework \
	-framework build/iphoneos/NewRelic.framework \
	-framework build/iphonesimulator/NewRelic.framework \
	-framework build/appletvsimulator/NewRelic.framework/ \
	-framework build/appletvos/NewRelic.framework \
	-framework build/macosx/NewRelic.framework 	\
	-output build/NewRelic.xcframework