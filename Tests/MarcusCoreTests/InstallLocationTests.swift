import XCTest
@testable import MarcusCore

final class InstallLocationTests: XCTestCase {

    private let home = "/Users/ana"

    func testApplicationsAndItsSubfoldersCountAsInstalled() {
        XCTAssertTrue(InstallLocation.isInsideApplications("/Applications/Marcus.app", home: home))
        XCTAssertTrue(InstallLocation.isInsideApplications("/Applications/Escritura/Marcus.app", home: home))
        XCTAssertTrue(InstallLocation.isInsideApplications("/Users/ana/Applications/Marcus.app", home: home))
        XCTAssertTrue(InstallLocation.isInsideApplications("/Applications/../Applications/Marcus.app", home: home))
    }

    func testOtherPlacesDoNot() {
        XCTAssertFalse(InstallLocation.isInsideApplications("/Users/ana/Downloads/Marcus.app", home: home))
        XCTAssertFalse(InstallLocation.isInsideApplications("/Users/ana/Desktop/Marcus.app", home: home))
        XCTAssertFalse(InstallLocation.isInsideApplications("/Volumes/Marcus/Marcus.app", home: home))
        XCTAssertFalse(InstallLocation.isInsideApplications("/ApplicationsBackup/Marcus.app", home: home))
        XCTAssertFalse(InstallLocation.isInsideApplications("/Users/otro/Applications/Marcus.app", home: home))
    }

    func testOfferRules() {
        XCTAssertTrue(InstallLocation.shouldOffer(bundlePath: "/Users/ana/Downloads/Marcus.app", home: home, suppressed: false))
        XCTAssertFalse(InstallLocation.shouldOffer(bundlePath: "/Users/ana/Downloads/Marcus.app", home: home, suppressed: true))
        XCTAssertFalse(InstallLocation.shouldOffer(bundlePath: "/Applications/Marcus.app", home: home, suppressed: false))
        // The bare executable (swift build) and build products stay quiet.
        XCTAssertFalse(InstallLocation.shouldOffer(bundlePath: "/Users/ana/marcus/.build/debug/Marcus", home: home, suppressed: false))
        XCTAssertFalse(InstallLocation.shouldOffer(bundlePath: "/Users/ana/marcus/.build/x/Marcus.app", home: home, suppressed: false))
        // dist/ in the repo is a real bundle outside Applications: offered,
        // which is what a tester sees too.
        XCTAssertTrue(InstallLocation.shouldOffer(bundlePath: "/Users/ana/marcus/dist/Marcus.app", home: home, suppressed: false))
    }

    func testTranslocatedAndExternalVolumes() {
        XCTAssertTrue(InstallLocation.isTranslocated("/private/var/folders/1f/T/AppTranslocation/ABC/d/Marcus.app"))
        XCTAssertFalse(InstallLocation.isTranslocated("/Users/ana/Downloads/Marcus.app"))
        XCTAssertTrue(InstallLocation.isOnExternalVolume("/Volumes/Marcus/Marcus.app"))
        XCTAssertFalse(InstallLocation.isOnExternalVolume("/Users/ana/Downloads/Marcus.app"))
    }

    func testDestinationPrefersSystemApplicationsWhenWritable() {
        XCTAssertEqual(InstallLocation.destination(for: "/Users/ana/Downloads/Marcus.app", home: home, systemApplicationsWritable: true),
                       "/Applications/Marcus.app")
        XCTAssertEqual(InstallLocation.destination(for: "/Volumes/Marcus/Marcus.app", home: home, systemApplicationsWritable: false),
                       "/Users/ana/Applications/Marcus.app")
    }
}
