import Foundation
import JWTKit

/// Firma tokens con la clave RSA fija de `Fixtures/test-private-key.pem` — su mitad
/// pública, ya calculada, es la que sirve `GET /jwks` (`Fixtures/test-jwks.json`).
/// Deliberadamente genérico: sin ninguna forma de claims específica de un proveedor —
/// solo lo mínimo (`iss`/`aud`/`sub`/`exp`) que cualquier verificador OAuth/OIDC estándar
/// espera. No protege nada real: la clave privada está comiteada en este mismo repo.
public enum TokenSigner {
    static let keyID = "authmock-key-1"

    /// `internal`, no `private` — los tests decodifican contra este mismo tipo para
    /// comprobar que un verificador real (que solo ve la clave pública) recupera
    /// exactamente los claims que se firmaron.
    struct Claims: JWTPayload, Equatable {
        let iss: IssuerClaim
        let aud: AudienceClaim
        var sub: SubjectClaim
        let exp: ExpirationClaim
        var permissions: [String]?

        func verify(using key: some JWTAlgorithm) throws {
            try exp.verifyNotExpired()
        }
    }

    /// Un token firmado, válido desde ahora durante `config.expiresIn` segundos.
    public static func sign(config: Config, claimsOverride: ClaimsOverride? = nil) async throws -> String {
        guard let url = Bundle.module.url(
            forResource: "test-private-key", withExtension: "pem", subdirectory: "Fixtures"
        ) else {
            throw AuthMockError.missingFixture("Fixtures/test-private-key.pem")
        }
        let pem = try String(contentsOf: url, encoding: .utf8)

        let keys = JWTKeyCollection()
        try await keys.add(
            rsa: Insecure.RSA.PrivateKey(pem: pem), digestAlgorithm: .sha256, kid: JWKIdentifier(string: keyID)
        )

        let sub = claimsOverride?.sub ?? "authmock-user"
        let permissions = claimsOverride?.permissions

        let claims = Claims(
            iss: IssuerClaim(value: config.issuer),
            aud: AudienceClaim(value: [config.audience]),
            sub: SubjectClaim(value: sub),
            exp: ExpirationClaim(value: Date().addingTimeInterval(TimeInterval(config.expiresIn))),
            permissions: permissions
        )
        return try await keys.sign(claims, kid: JWKIdentifier(string: keyID))
    }
}

enum AuthMockError: Error, CustomStringConvertible {
    case missingFixture(String)

    var description: String {
        switch self {
        case .missingFixture(let path):
            "\(path) no está en el bundle — revisa Package.swift (resources: [.copy(\"Fixtures\")])"
        }
    }
}
