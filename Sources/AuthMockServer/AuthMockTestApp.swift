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
    
    private let statusOverride = StatusOverrideBox()
    private let claimsOverride = ClaimsOverrideBox()
    
    public init(port: Int = 8090) async throws {
        self.listeningPort = port == 0 ? Self.getFreePort() : port
        
        // Configuramos un entorno "testing" para Vapor
        let env = Environment(name: "testing", arguments: ["vapor"])
        self.app = try await Application.make(env)
    }
    
    /// Configura las rutas y arranca el servidor HTTP de forma asíncrona en el puerto 
    /// parametrizado (no bloquea el hilo). Usado comúnmente para End-to-End por socket real.
    public func start() async throws {
        app.http.server.configuration.port = listeningPort
        
        let config = Config(environment: ["AUTHMOCK_PORT": "\(listeningPort)"])
        try routes(
            app,
            config: config,
            statusOverride: statusOverride,
            claimsOverride: claimsOverride
        )
        
        // Inicia el servidor HTTP sin bloquear la ejecución 
        try await app.startup()
    }
    
    /// Configura las rutas pero NO arranca el servidor HTTP en un puerto real.
    /// Ideal para tests de Backend que usan puramente memoria (`in-memory`) con `app.testing().test(...)`.
    public func startInMemory() async throws {
        let config = Config(environment: [:])
        try routes(
            app,
            config: config,
            statusOverride: statusOverride,
            claimsOverride: claimsOverride
        )
        // No llamamos a app.startup(). Las rutas ya están listas para testear sobre memoria.
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
