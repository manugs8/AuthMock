import Vapor

/// Envoltorio diseñado específicamente para instanciar el servidor mock 
/// desde entornos de test (tanto tests de iOS como tests E2E de Vapor).
/// Ejecuta el servidor Vapor en el hilo de testing, permitiéndote controlar el status por código.
public class AuthMockTestApp {
    /// La instancia real de la Aplicación de Vapor, expuesta por si 
    /// necesitas hacer aserciones in-memory con XCTVapor mediante `app.testing()`.
    public let app: Application
    
    private let port: Int
    private let statusOverride = StatusOverrideBox()
    private let claimsOverride = ClaimsOverrideBox()
    
    public init(port: Int = 8090) async throws {
        self.port = port
        // Configuramos un entorno "testing" para Vapor
        let env = Environment(name: "testing", arguments: ["vapor"])
        self.app = try await Application.make(env)
    }
    
    /// Configura las rutas y arranca el servidor HTTP de forma asíncrona en el puerto 
    /// parametrizado (no bloquea el hilo). Usado comúnmente para End-to-End por socket real.
    public func start() async throws {
        app.http.server.configuration.port = port
        
        let config = Config(environment: ["AUTHMOCK_PORT": "\(port)"])
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
    public func simule(status: Int) async {
        await statusOverride.arm(status)
    }
    
    /// Prepara el mock para inyectar claims particulares en 
    /// el token la próxima vez que se consuma `/token`.
    public func simule(claims: ClaimsOverride) async {
        await claimsOverride.arm(claims)
    }
}
