# Shadow: zsign (MIT, github.com/zhlynn/zsign via khcrysalis/Zsign-Package,
# commit c4ba9da) for on-device re-signing of Shadow updates. Only the Mach-O,
# bundle and code-signature parts are vendored; openssl.cpp is replaced by
# Sources/openssl_apple.mm (Security.framework), SHA comes from CommonCrypto
# through Sources/shim/openssl/sha.h.

objc_library(
    name = "Zsign",
    enable_modules = True,
    module_name = "Zsign",
    srcs = glob([
        "Sources/*.cpp",
        "Sources/*.mm",
        "Sources/*.h",
        "Sources/common/*.cpp",
        "Sources/common/*.h",
        "Sources/shim/openssl/*.h",
    ]),
    hdrs = glob([
        "PublicHeaders/**/*.h",
    ]),
    includes = [
        "PublicHeaders",
    ],
    copts = [
        "-w",
        "-iquote{}/Sources".format(package_name()),
        "-iquote{}/Sources/common".format(package_name()),
        "-I{}/Sources/shim".format(package_name()),
    ],
    cxxopts = [
        "-std=c++17",
    ],
    sdk_frameworks = [
        "Foundation",
        "Security",
    ],
    visibility = [
        "//visibility:public",
    ],
)
