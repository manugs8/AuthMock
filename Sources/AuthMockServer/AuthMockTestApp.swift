import Vapor
import Foundation

/// Envoltorio diseñado específicamente para instanciar el servidor mock 
/// desde entornos de test (tanto tests de iOS como tests E2E de Vapor).
/// Ejecuta el servidor Vapor en el hilo de testing, permitiéndote controlar el status por código.
public class AuthMockTestApp {
    /// La instancia real de la Aplicación de Vapor, expuesta por si
    /// necesitas hacer aserciones in-memory con XCTVapor mediante `app.testing()`.
    public let app: Application

    /// Devuelve el puerto en el que el servidor está configurado para escuchar (o el que está escuchando).
    /// Si usaste `port: 0` en el init para obtener un puerto efímero dinámico (ideal para tests paralelos),
    /// esta propiedad reflejará el puerto libre real que fue reservado para esta instancia.
    public let listeningPort: Int

    /// Sobreescribe `AUTHMOCK_AUDIENCE` para esta instancia — `nil` conserva el valor por
    /// defecto de `Config` (`"authmock-audience"`). Necesario cuando quien consume este
    /// mock exige que el `aud` del token sea una URL absoluta `https://` (p. ej.
    /// `WorkOSBearerAuth`, que valida sus resource indicators así "también bajo `.local`" —
    /// ver su `Configure.swift`), en vez de una etiqueta simple.
    private let audienceOverride: String?

    /// Sobreescribe `AUTHMOCK_EXPIRES_IN` para esta instancia — `nil` conserva el valor por
    /// defecto de `Config` (3600s). Necesario para un test que necesita un token
    /// genuinamente caducado en segundos, no en una hora.
    private let expiresInOverride: Int?

    private let statusOverride = StatusOverrideBox()
    private let claimsOverride = ClaimsOverrideBox()

    public init(port: Int = 8090, audience: String? = nil, expiresIn: Int? = nil) async throws {
        self.listeningPort = port == 0 ? Self.getFreePort() : port
        self.audienceOverride = audience
        self.expiresInOverride = expiresIn

        // Configuramos un entorno "testing" para Vapor
        let env = Environment(name: "testing", arguments: ["vapor"])
        self.app = try await Application.make(env)
    }

    /// Configura las rutas y arranca el servidor HTTP de forma asíncrona en el puerto
    /// parametrizado (no bloquea el hilo). Usado comúnmente para End-to-End por socket real.
    public func start() async throws {
        app.http.server.configuration.port = listeningPort

        try routes(
            app,
            config: makeConfig(),
            statusOverride: statusOverride,
            claimsOverride: claimsOverride
        )

        // Inicia el servidor HTTP sin bloquear la ejecución
        try await app.startup()
    }

    /// Configura las rutas pero NO arranca el servidor HTTP en un puerto real.
    /// Ideal para tests de Backend que usan puramente memoria (`in-memory`) con `app.testing().test(...)`.
    public func startInMemory() async throws {
        try routes(
            app,
            config: makeConfig(),
            statusOverride: statusOverride,
            claimsOverride: claimsOverride
        )
        // No llamamos a app.startup(). Las rutas ya están listas para testear sobre memoria.
    }

    /// `AUTHMOCK_PORT` siempre viene de `listeningPort` — nunca del entorno real del
    /// proceso, para que dos instancias en el mismo test no se pisen: cada una arma su
    /// propio `Config` en memoria, no vía `setenv`. `audience`/`expiresIn` solo se incluyen
    /// si el init los recibió explícitos; si no, `Config.init(environment:)` cae a sus
    /// valores por defecto exactamente igual que arrancando el ejecutable standalone sin
    /// `AUTHMOCK_AUDIENCE`/`AUTHMOCK_EXPIRES_IN`.
    private func makeConfig() -> Config {
        var environment = ["AUTHMOCK_PORT": "\(listeningPort)"]
        if let audienceOverride {
            environment["AUTHMOCK_AUDIENCE"] = audienceOverride
        }
        if let expiresInOverride {
            environment["AUTHMOCK_EXPIRES_IN"] = "\(expiresInOverride)"
        }
        return Config(environment: environment)
    }
    
    /// Detiene y limpia los recursos del servidor mock
    public func stop() async throws {
        try await app.asyncShutdown()
    }
    
    /// Prepara el mock para devolver el código de estado HTTP indicado 
    /// en la próxima llamada a `/token`. (Por ej. `401`).
    public func simulate(status: Int) async {
        await statusOverride.arm(status)
    }
    
    /// Prepara el mock para inyectar claims particulares en 
    /// el token la próxima vez que se consuma `/token`.
    public func simulate(claims: ClaimsOverride) async {
        await claimsOverride.arm(claims)
    }
    
    /// Encuentra y reserva temporalmente un puerto libre del sistema operativo
    /// para evitar colisiones de red cuando se corren tests en paralelo.
    private static func getFreePort() -> Int {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock != -1 else { return 8090 } // Fallback
        
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, len)
            }
        }
        
        guard bindResult == 0 else {
            close(sock)
            return 8090
        }
        
        _ = withUnsafeMutablePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                getsockname(sock, sockaddrPtr, &len)
            }
        }
        
        let portInNetworkOrder = addr.sin_port
        let port = Int(CUnsignedShort(bigEndian: portInNetworkOrder))
        close(sock)
        
        return port
    }
}
