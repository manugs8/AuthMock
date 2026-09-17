import Foundation
import JWTKit
import Testing
import VaporTesting

@testable import AuthMock

@Suite("Routes")
struct RoutesTests {
    @Test("GET /health responde ok")
    func health() async throws {
        try await withApp(configure: { app in try routes(app, config: Config(environment: [:]), statusOverride: StatusOverrideBox(), claimsOverride: ClaimsOverrideBox()) }) { app in
            try await app.testing().test(.GET, "health", afterResponse: { res async in
                #expect(res.status == .ok)
                #expect(res.body.string == "ok")
            })
        }
    }

    @Test("GET /oauth2/jwks sirve la clave pública en formato JWKS")
    func jwks() async throws {
        try await withApp(configure: { app in try routes(app, config: Config(environment: [:]), statusOverride: StatusOverrideBox(), claimsOverride: ClaimsOverrideBox()) }) { app in
            try await app.testing().test(.GET, "oauth2/jwks", afterResponse: { res async in
                #expect(res.status == .ok)
                #expect(res.headers.contentType?.description.contains("json") == true)
                expectContent(AuthMockJWKSResponse.self, res) { jwks in
                    #expect(jwks.keys.count == 1)
                    #expect(jwks.keys[0].kty == "RSA")
                    #expect(jwks.keys[0].alg == "RS256")
                    #expect(jwks.keys[0].kid == TokenSigner.keyID)
                }
            })
        }
    }

    @Test("POST /token con status de éxito devuelve un token que verifica contra /jwks")
    func tokenSuccessRoundTrips() async throws {
        let config = Config(environment: [
            "AUTHMOCK_STATUS": "200",
            "AUTHMOCK_ISSUER": "http://routes-test.invalid",
            "AUTHMOCK_AUDIENCE": "routes-test-audience",
        ])
        try await withApp(configure: { app in try routes(app, config: config, statusOverride: StatusOverrideBox(), claimsOverride: ClaimsOverrideBox()) }) { app in
            var issuedToken: String?

            try await app.testing().test(.POST, "token", afterResponse: { res async in
                #expect(res.status == .ok)
                expectContent(TokenResponse.self, res) { body in
                    #expect(body.tokenType == "Bearer")
                    #expect(body.expiresIn == config.expiresIn)
                    issuedToken = body.accessToken
                }
            })

            try await app.testing().test(.GET, "oauth2/jwks", afterResponse: { res async throws in
                let jwksJSON = res.body.string
                let verifier = JWTKeyCollection()
                _ = try await verifier.add(jwksJSON: jwksJSON)

                let token = try #require(issuedToken)
                let claims = try await verifier.verify(token, as: TokenSigner.Claims.self)
                #expect(claims.iss.value == "http://routes-test.invalid")
                #expect(claims.aud.value == ["routes-test-audience"])
                #expect(claims.sub.value == "authmock-user")
                #expect(claims.permissions == nil)
            })
        }
    }

    @Test("POST /token con status de fallo responde ese mismo código sin firmar nada")
    func tokenFailureRespondsWithConfiguredStatus() async throws {
        let config = Config(environment: ["AUTHMOCK_STATUS": "401"])
        try await withApp(configure: { app in try routes(app, config: config, statusOverride: StatusOverrideBox(), claimsOverride: ClaimsOverrideBox()) }) { app in
            try await app.testing().test(.POST, "token", afterResponse: { res async in
                #expect(res.status == .unauthorized)
                expectContent(ErrorResponse.self, res) { body in
                    #expect(body.error == "mock_error")
                    #expect(body.errorDescription.contains("401"))
                }
            })
        }
    }

    @Test("POST /token con un status 2xx distinto de 200 también firma y usa ese código")
    func tokenSuccessWithNonDefault2xxStatus() async throws {
        let config = Config(environment: ["AUTHMOCK_STATUS": "201"])
        try await withApp(configure: { app in try routes(app, config: config, statusOverride: StatusOverrideBox(), claimsOverride: ClaimsOverrideBox()) }) { app in
            try await app.testing().test(.POST, "token", afterResponse: { res async in
                #expect(res.status == .created)
                expectContent(TokenResponse.self, res) { body in
                    #expect(!body.accessToken.isEmpty)
                }
            })
        }
    }

    @Test("POST /_test/status arma el siguiente POST /token una sola vez, luego revierte a AUTHMOCK_STATUS")
    func statusOverrideFiresOnceThenReverts() async throws {
        let config = Config(environment: ["AUTHMOCK_STATUS": "200"])
        try await withApp(configure: { app in try routes(app, config: config, statusOverride: StatusOverrideBox(), claimsOverride: ClaimsOverrideBox()) }) { app in
            try await app.testing().test(
                .POST, "_test/status",
                beforeRequest: { req in try req.content.encode(StatusOverrideRequest(status: 401)) },
                afterResponse: { res async in #expect(res.status == .ok) }
            )

            try await app.testing().test(.POST, "token", afterResponse: { res async in
                #expect(res.status == .unauthorized)
            })

            // Se consumió al primer uso — el siguiente POST /token revierte a AUTHMOCK_STATUS.
            try await app.testing().test(.POST, "token", afterResponse: { res async in
                #expect(res.status == .ok)
            })
        }
    }
    
    @Test("POST /_test/claims arma claims personalizados para el siguiente POST /token una sola vez")
    func claimsOverrideFiresOnceThenReverts() async throws {
        let config = Config(environment: [
            "AUTHMOCK_STATUS": "200",
            "AUTHMOCK_ISSUER": "http://routes-test.invalid",
            "AUTHMOCK_AUDIENCE": "routes-test-audience",
        ])
        
        try await withApp(configure: { app in try routes(app, config: config, statusOverride: StatusOverrideBox(), claimsOverride: ClaimsOverrideBox()) }) { app in
            
            // 1. Armamos los custom claims
            try await app.testing().test(
                .POST, "_test/claims",
                beforeRequest: { req in 
                    try req.content.encode(ClaimsOverride(sub: "custom-user-id", permissions: ["read", "write"]))
                },
                afterResponse: { res async in #expect(res.status == .ok) }
            )
            
            // 2. Pedimos el token
            var customToken: String?
            try await app.testing().test(.POST, "token", afterResponse: { res async in
                #expect(res.status == .ok)
                expectContent(TokenResponse.self, res) { body in
                    customToken = body.accessToken
                }
            })
            
            // 3. Verificamos que tenga los custom claims
            try await app.testing().test(.GET, "oauth2/jwks", afterResponse: { res async throws in
                let jwksJSON = res.body.string
                let verifier = JWTKeyCollection()
                _ = try await verifier.add(jwksJSON: jwksJSON)

                let token = try #require(customToken)
                let claims = try await verifier.verify(token, as: TokenSigner.Claims.self)
                #expect(claims.sub.value == "custom-user-id")
                #expect(claims.permissions == ["read", "write"])
            })
            
            // 4. Se consumió, el siguiente token tiene valores por defecto
            var defaultToken: String?
            try await app.testing().test(.POST, "token", afterResponse: { res async in
                expectContent(TokenResponse.self, res) { body in
                    defaultToken = body.accessToken
                }
            })
            
            try await app.testing().test(.GET, "oauth2/jwks", afterResponse: { res async throws in
                let verifier = JWTKeyCollection()
                _ = try await verifier.add(jwksJSON: res.body.string)
                let token = try #require(defaultToken)
                let claims = try await verifier.verify(token, as: TokenSigner.Claims.self)
                #expect(claims.sub.value == "authmock-user")
                #expect(claims.permissions == nil)
            })
        }
    }
}

/// Forma mínima del JWKS solo para decodificar en el test — el tipo real (`JWTKit.JWKS`)
/// también sirve, pero declarar aquí lo justo que se comprueba evita acoplar el test a la
/// forma completa de ese tipo.
private struct AuthMockJWKSResponse: Decodable {
    struct Key: Decodable {
        let kty: String
        let alg: String
        let kid: String
    }

    let keys: [Key]
}
