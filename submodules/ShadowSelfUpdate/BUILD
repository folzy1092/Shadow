load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# Shadow: in-app update with on-device signing (p12 + mobileprovision from
# "Автообновление") and installation through a local HTTPS server and
# itms-services. Signing itself is third-party/zsign.
swift_library(
    name = "ShadowSelfUpdate",
    module_name = "ShadowSelfUpdate",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//third-party/zsign:Zsign",
        "//third-party/ZipArchive:ZipArchive",
    ],
    visibility = [
        "//visibility:public",
    ],
)
