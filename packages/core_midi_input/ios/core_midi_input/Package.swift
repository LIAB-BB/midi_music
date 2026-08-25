// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "core_midi_input",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "core-midi-input", targets: ["core_midi_input"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "core_midi_input",
            dependencies: [],
            path: "../Classes",
            resources: [
                .process("../Resources/PrivacyInfo.xcprivacy")
            ],
            linkerSettings: [
                .linkedFramework("CoreMIDI")
            ]
        )
    ]
)
