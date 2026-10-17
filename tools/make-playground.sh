#!/bin/sh
# Builds MeasurePlan.swiftpm, a Swift Playgrounds app you can open and run on an iPad (no Mac needed),
# by combining the app and PlanCore sources into one module. Output: build/MeasurePlan.swiftpm.zip
set -e
cd "$(dirname "$0")/.."
out=build/MeasurePlan.swiftpm
rm -rf "$out" "$out.zip"
mkdir -p "$out/Core" "$out/App"
cp Packages/PlanCore/Sources/PlanCore/*.swift "$out/Core/"
for f in MeasurePlan/*.swift; do
  grep -v '^import PlanCore$' "$f" > "$out/App/$(basename "$f")"
done
cat > "$out/Package.swift" <<'PKG'
// swift-tools-version: 5.9
import PackageDescription
import AppleProductTypes

let package = Package(
    name: "MeasurePlan",
    platforms: [.iOS("17.0")],
    products: [
        .iOSApplication(
            name: "MeasurePlan",
            targets: ["AppModule"],
            bundleIdentifier: "com.example.measureplan",
            teamIdentifier: "",
            displayVersion: "0.1",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .camera),
            accentColor: .presetColor(.blue),
            supportedDeviceFamilies: [.pad, .phone],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad])),
            ],
            capabilities: [
                .camera(purposeString: "MeasurePlan uses the camera and LiDAR scanner to measure your room."),
            ]
        ),
    ],
    targets: [
        .executableTarget(name: "AppModule", path: "."),
    ]
)
PKG
(cd build && zip -qr MeasurePlan.swiftpm.zip MeasurePlan.swiftpm)
echo "Wrote $out.zip"
