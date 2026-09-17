import Foundation
import JWTKit
import Testing

@testable import AuthMockServer

@Suite("TokenSigner")
struct TokenSignerTests {
    /// Un verificador que solo conoce la clave PÚBLICA — igual que cualquier verificador
    /// real (`WorkOSBearerAuth`/`RemoteJWKS` incluido), que nunca ve la clave privada,
    /// solo el JWKS servido por `GET /jwks`. Firmar y verificar con la misma clave
    /// privada no probaría nada — esto sí prueba que un tercero, con solo lo público,
    /// recupera exactamente lo que se firmó.
    private func publicKeyVerifier() async throws -> JWTKeyCollection {
        let jwksURL = Bundle.module.url(forResource: "test-jwks", withExtension: "json", subdirectory: "Fixtures")!
        let jwksJSON = try String(contentsOf: jwksURL, encoding: .utf8)
        let keys = JWTKeyCollection()
        _ = try await keys.add(jwksJSON: jwksJSON)
        return keys
    }

    @Test("el token firmado verifica con la clave pública y lleva los claims esperados")
    func signedTokenVerifiesAndCarriesExpectedClaims() async throws {
        let config = Config(environment: [
            "AUTHMOCK_ISSUER": "http://issuer.example",
            "AUTHMOCK_AUDIENCE": "my-api",
            "AUTHMOCK_EXPIRES_IN": "120",
        ])
        let token = try await TokenSigner.sign(config: config)

        let claims = try await publicKeyVerifier().verify(token, as: TokenSigner.Claims.self)

        #expect(claims.iss.value == "http://issuer.example")
        #expect(claims.aud.value == ["my-api"])
        #expect(claims.sub.value == "authmock-user")

        let expiresIn = claims.exp.value.timeIntervalSinceNow
        #expect(expiresIn > 100 && expiresIn <= 120)
    }

    @Test("dos firmas seguidas producen tokens distintos (exp cambia) pero ambas verifican")
    func consecutiveSignaturesBothVerify() async throws {
        let config = Config(environment: [:])
        let first = try await TokenSigner.sign(config: config)
        let second = try await TokenSigner.sign(config: config)

        let verifier = try await publicKeyVerifier()
        _ = try await verifier.verify(first, as: TokenSigner.Claims.self)
        _ = try await verifier.verify(second, as: TokenSigner.Claims.self)
    }

    @Test("un verificador con una audiencia distinta rechaza el token")
    func verifierWithWrongAudienceRejectsToken() async throws {
        let config = Config(environment: ["AUTHMOCK_AUDIENCE": "expected-audience"])
        let token = try await TokenSigner.sign(config: config)

        let claims = try await publicKeyVerifier().verify(token, as: TokenSigner.Claims.self)
        #expect(claims.aud.value != ["some-other-audience"])
    }
}
