import Photos
import Testing
@testable import Caffy

/// Tests for when `PhotoThumbnailLoader` asks PhotoKit for a photo at all.
struct PhotoThumbnailLoaderTests {
    private static let realID = "9F983DBA-EC35-42B8-8773-B597CF782EDD/L0/001"

    @Test(arguments: [PHAuthorizationStatus.authorized, .limited])
    func realPhotosLoadWithAccess(access: PHAuthorizationStatus) {
        #expect(PhotoThumbnailLoader.canLoad(Self.realID, access: access))
    }

    @Test(arguments: [PHAuthorizationStatus.notDetermined, .denied, .restricted])
    func nothingLoadsWithoutAccess(access: PHAuthorizationStatus) {
        #expect(!PhotoThumbnailLoader.canLoad(Self.realID, access: access))
    }

    @Test func missingAndSamplePhotosNeverLoad() {
        #expect(!PhotoThumbnailLoader.canLoad(nil, access: .authorized))
        #expect(!PhotoThumbnailLoader.canLoad("", access: .authorized))
        #expect(!PhotoThumbnailLoader.canLoad("\(SampleData.idPrefix)m0001-p1", access: .authorized))
    }

    @Test func samplePhotoIDsUseThePrefix() {
        let library = SampleData.library(endingOn: .now, calendar: Scenario().calendar)
        #expect(library.moments.allSatisfy { !PhotoThumbnailLoader.canLoad($0.coverID, access: .authorized) })
    }
}
