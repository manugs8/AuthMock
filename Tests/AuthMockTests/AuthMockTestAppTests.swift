import Foundation
import JWTKit
import Testing
import VaporTesting

@testable import AuthMockServer

/// `AuthMockTestApp` itself, as opposed to `RoutesTests` (which exercises `routes(...)`
/// directly against a hand-built `Config`) — specifically the `audience`/`expiresIn`
/// overrides a consumer passes to its `init`, since those aren't read from the process
/// environment the way the standalone `AuthMock` executable's own `Config` is.
@Suite("AuthMockTestApp")
struct AuthMockTestAppTests {
    @Test("start() signs tokens with the audience/expiresIn passed to init, not Config's defaults")
    func startHonorsAudienceAndExpiresInOverrides() async throws {
        let instance = try await AuthMockTestApp(
            port: 0, audience: "https://e2e.invalid/custom-resource", expiresIn: 5
        )
        do {
            try await instance.start()

            var issuedToken: String?
            try await instance.app.testing().test(.POST, "token", afterResponse: { res async in
                #expect(res.status == .ok)
                expectContent(TokenResponse.self, res) { body in
                    #expect(body.expiresIn == 5)
                    issuedToken = body.accessToken
                }
            })

            try await instance.app.testing().test(.GET, "oauth2/jwks", afterResponse: { res async throws in
                let verifier = JWTKeyCollection()
                _ = try await verifier.add(jwksJSON: res.body.string)

                let token = try #require(issuedToken)
                let claims = try await verifier.verify(token, as: TokenSigner.Claims.self)
                #expect(claims.aud.value == ["https://e2e.invalid/custom-resource"])
                let secondsUntilExpiry = claims.exp.value.timeIntervalSinceNow
                #expect(secondsUntilExpiry > 0 && secondsUntilExpiry <= 5)
            })
        } catch {
            try? await instance.stop()
            throw error
        }
        try await instance.stop()
    }

    @Test("start() without audience/expiresIn keeps Config's own defaults")
    func startWithoutOverridesKeepsConfigDefaults() async throws {
        let instance = try await AuthMockTestApp(port: 0)
        do {
            try await instance.start()

            try await instance.app.testing().test(.POST, "token", afterResponse: { res async in
                #expect(res.status == .ok)
                expectContent(TokenResponse.self, res) { body in
                    #expect(body.expiresIn == 3_600)
                }
            })
        } catch {
            try? await instance.stop()
            throw error
        }
        try await instance.stop()
    }
}
