import Foundation
import Testing
@testable import SeawallCore

/// The test-only unlock. What these prove: the gate logic (only a debug build, only exactly "1"),
/// and that the release gate (`LicenseGate`) never reads the environment. What they can't prove:
/// that release builds leave `DevLicense` out, since tests always build in debug. That is checked
/// on the built binary instead: scripts/build-app.sh fails a release build whose executable
/// contains "SEAWALL_DEV_LICENSE".
struct DevLicenseTests {
    #if DEBUG
    @Test func onlyExactlyOneTurnsItOn() {
        #expect(DevLicense.isOn(environment: ["SEAWALL_DEV_LICENSE": "1"]))
        for value in ["", "0", "true", "yes", " 1", "11"] {
            #expect(!DevLicense.isOn(environment: ["SEAWALL_DEV_LICENSE": value]))
        }
        #expect(!DevLicense.isOn(environment: [:]))
    }

    @Test func aDebugBuildWithTheVariableStartsBlocksWithoutAKey() {
        #expect(DevLicense.mayStartBlock(.unlicensed, isDebugBuild: true, environment: ["SEAWALL_DEV_LICENSE": "1"]))
        #expect(!DevLicense.mayStartBlock(.unlicensed, isDebugBuild: true, environment: [:]))
    }

    @Test func aReleaseBuildIgnoresTheVariable() {
        #expect(!DevLicense.mayStartBlock(.unlicensed, isDebugBuild: false, environment: ["SEAWALL_DEV_LICENSE": "1"]))
    }
    #endif

    /// The gate release builds use takes no environment; with the variable set in this very
    /// process, an unlicensed Mac still can't start a block.
    @Test func theReleaseGateNeverReadsTheEnvironment() {
        setenv("SEAWALL_DEV_LICENSE", "1", 1)
        defer { unsetenv("SEAWALL_DEV_LICENSE") }
        #expect(!LicenseGate.mayStartBlock(.unlicensed))
    }
}
