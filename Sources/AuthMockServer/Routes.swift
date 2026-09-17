import Vapor

struct TokenResponse: Content, Equatable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

struct ErrorResponse: Content, Equatable {
    let error: String
    let errorDescription: String

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

struct StatusOverrideRequest: Content {
    let status: Int
}

public func routes(
    _ app: Application, 
    config: Config, 
    statusOverride: StatusOverrideBox,
    claimsOverride: ClaimsOverrideBox
) throws {
    app.get("health") { _ in "ok" }

    // Arma, una sola vez, el status que devolverá el próximo POST /token — ver
    // StatusOverrideBox.swift. Endpoint de test, no forma parte de la interfaz OAuth que
    // AuthMock simula.
    app.post("_test", "status") { req async throws -> HTTPStatus in
        let body = try req.content.decode(StatusOverrideRequest.self)
        await statusOverride.arm(body.status)
        return .ok
    }

    // Arma, una sola vez, los claims personalizados que devolverá el próximo POST /token —
    // ver ClaimsOverrideBox.swift. Endpoint de test.
    app.post("_test", "claims") { req async throws -> HTTPStatus in
        let body = try req.content.decode(ClaimsOverride.self)
        await claimsOverride.arm(body)
        return .ok
    }

    // La clave pública, en formato JWKS estándar, en la misma ruta que un Authorization
    // Server real de WorkOS — WorkOSBearerAuth siempre pide {issuer}/oauth2/jwks
    // (Configure.swift), no una ruta configurable.
    app.get("oauth2", "jwks") { req async throws -> Response in
        guard let url = Bundle.module.url(
            forResource: "test-jwks", withExtension: "json", subdirectory: "Fixtures"
        ) else {
            throw Abort(.internalServerError, reason: "Fixtures/test-jwks.json no está en el bundle")
        }
        let data = try Data(contentsOf: url)
        return Response(status: .ok, headers: ["Content-Type": "application/json"], body: .init(data: data))
    }

    // El endpoint que "hace" algo: responde éxito con un token firmado, o ese mismo status
    // como fallo. Controlado por `config.status` por defecto, o por el próximo valor
    // armado vía POST /_test/status (un solo uso — ver StatusOverrideBox.swift).
    // También firma con los claims por defecto o los overrideados.
    app.post("token") { req async throws -> Response in
        let status = await statusOverride.consume() ?? config.status
        guard (200..<300).contains(status) else {
            let body = ErrorResponse(
                error: "mock_error",
                errorDescription: "AuthMock configured with AUTHMOCK_STATUS=\(status)"
            )
            return try await body.encodeResponse(status: HTTPResponseStatus(statusCode: status), for: req)
        }
        
        let customClaims = await claimsOverride.consume()
        let token = try await TokenSigner.sign(config: config, claimsOverride: customClaims)
        let body = TokenResponse(accessToken: token, tokenType: "Bearer", expiresIn: config.expiresIn)
        return try await body.encodeResponse(status: HTTPResponseStatus(statusCode: status), for: req)
    }
}
