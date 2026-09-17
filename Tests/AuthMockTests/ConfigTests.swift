import Testing

@testable import AuthMock

@Suite("Config")
struct ConfigTests {
    @Test("valores por defecto cuando no hay entorno")
    func defaults() {
        let config = Config(environment: [:])
        #expect(config.port == 8090)
        #expect(config.status == 200)
        #expect(config.issuer == "http://127.0.0.1:8090")
        #expect(config.audience == "authmock-audience")
        #expect(config.expiresIn == 3600)
    }

    @Test("el issuer por defecto usa el puerto configurado, no el puerto por defecto")
    func issuerDefaultFollowsPort() {
        let config = Config(environment: ["AUTHMOCK_PORT": "9999"])
        #expect(config.port == 9999)
        #expect(config.issuer == "http://127.0.0.1:9999")
    }

    @Test("cada variable de entorno sobreescribe su valor por defecto")
    func explicitValuesOverrideDefaults() {
        let config = Config(environment: [
            "AUTHMOCK_PORT": "1234",
            "AUTHMOCK_STATUS": "401",
            "AUTHMOCK_ISSUER": "http://issuer.invalid",
            "AUTHMOCK_AUDIENCE": "my-audience",
            "AUTHMOCK_EXPIRES_IN": "60",
        ])
        #expect(config.port == 1234)
        #expect(config.status == 401)
        #expect(config.issuer == "http://issuer.invalid")
        #expect(config.audience == "my-audience")
        #expect(config.expiresIn == 60)
    }

    @Test("un valor no numérico cae al valor por defecto en vez de crashear")
    func nonNumericValueFallsBackToDefault() {
        let config = Config(environment: ["AUTHMOCK_PORT": "not-a-number"])
        #expect(config.port == 8090)
    }
}
