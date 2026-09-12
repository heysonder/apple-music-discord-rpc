import Foundation
import Testing

@testable import AppleMusicDiscordRPCCore

@Suite
struct ResolutionCacheTests {
    @Test
    func retriesMissingImagesAfterFiveMinutes() {
        var cache = ResolutionCache<String, String>()
        let start = Date(timeIntervalSince1970: 100)
        #expect(cache.value(for: "song", at: start) { nil } == nil)
        #expect(cache.value(for: "song", at: start.addingTimeInterval(299)) { "too early" } == nil)
        #expect(
            cache.value(for: "song", at: start.addingTimeInterval(300)) { "recovered" } == "recovered")
        #expect(
            cache.value(for: "song", at: start.addingTimeInterval(1000)) { "unexpected" } == "recovered")
    }

    @Test
    func evictsOldestEntryWhenCapacityIsReached() {
        var cache = ResolutionCache<String, String>(capacity: 2)
        let now = Date()
        _ = cache.value(for: "a", at: now) { "first" }
        _ = cache.value(for: "b", at: now) { "second" }
        _ = cache.value(for: "c", at: now) { "third" }
        #expect(cache.value(for: "b", at: now) { "unexpected" } == "second")
        #expect(cache.value(for: "a", at: now) { "resolved again" } == "resolved again")
    }

    @Test
    func refreshingExpiredMissDoesNotEvictUnrelatedEntry() {
        var cache = ResolutionCache<String, String>(capacity: 2, missLifetime: 1)
        let now = Date()
        _ = cache.value(for: "a", at: now) { nil }
        _ = cache.value(for: "b", at: now) { "second" }
        _ = cache.value(for: "a", at: now.addingTimeInterval(1)) { "recovered" }
        #expect(cache.value(for: "b", at: now.addingTimeInterval(1)) { "unexpected" } == "second")
    }
}
