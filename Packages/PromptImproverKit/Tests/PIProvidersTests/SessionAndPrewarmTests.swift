import Foundation
import Testing
@testable import PIProviders

struct ProviderSessionTests {
    @Test func theSessionKeepsNothingAndFailsFastOffline() {
        let configuration = ProviderSession.makeConfiguration()
        #expect(configuration.urlCache == nil)
        #expect(configuration.httpCookieStorage == nil)
        #expect(!configuration.httpShouldSetCookies)
        #expect(configuration.urlCredentialStorage == nil)
        #expect(!configuration.waitsForConnectivity)
        #expect(configuration.timeoutIntervalForRequest == 300)
        #expect(configuration.timeoutIntervalForResource == 600)
        #expect(configuration.httpAdditionalHeaders == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test func theStandardTimeoutsAreTheProductOnes() {
        #expect(StreamTimeouts.standard.responseHeaders == .seconds(20))
        #expect(StreamTimeouts.standard.idle == .seconds(300))
        #expect(StreamTimeouts.standard.limit(for: .idle) == .seconds(300))
        #expect(StreamTimeouts.standard.prewarm == .seconds(3))
    }
}

@Suite(.timeLimit(.minutes(1)))
struct PrewarmTests {
    @Test func aHeadWithoutCredentialsAtMostOnceAMinute() async {
        let server = StubServer()
        for _ in 0..<3 { server.enqueue([.head(status: 404, headers: [:]), .finish]) }
        let clock = TestClock()
        let provider = makeAnthropic(server, clock: clock)

        await provider.prewarm()
        await provider.prewarm()
        clock.advance(by: .seconds(59))
        await provider.prewarm()
        #expect(server.requests.count == 1)

        clock.advance(by: .seconds(1))
        await provider.prewarm()
        #expect(server.requests.count == 2)

        for request in server.requests {
            #expect(request.method == "HEAD")
            #expect(request.url.absoluteString == "https://\(server.host)/")
            #expect(request.header("x-api-key") == nil)
            #expect(request.header("authorization") == nil)
        }
    }

    @Test func failuresAreIgnored() async {
        let server = StubServer()
        server.enqueue([.fail(.notConnectedToInternet)])
        await makeOpenAI(server).prewarm()
        #expect(server.requests.count == 1)
    }

    @Test func eachProviderHasItsOwnLimit() async {
        let server = StubServer()
        for _ in 0..<2 { server.enqueue([.head(status: 200, headers: [:]), .finish]) }
        await makeAnthropic(server).prewarm()
        await makeOpenAI(server).prewarm()
        #expect(server.requests.count == 2)
    }

    @Test(arguments: [
        ("https://api.anthropic.com", "https://api.anthropic.com/"),
        ("https://proxy.example.com:8443/anthropic/v1", "https://proxy.example.com:8443/"),
    ])
    func theOriginDropsAnyPath(_ base: String, _ origin: String) {
        #expect(Prewarmer.origin(of: URL(string: base)!)?.absoluteString == origin)
    }
}
