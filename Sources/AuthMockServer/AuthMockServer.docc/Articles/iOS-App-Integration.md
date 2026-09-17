# Uso en una App iOS (Frontend)

Cómo configurar en tu equipo local y en tus tests automatizados (UI o Unitarios) el uso de AuthMock para resolver el inicio de sesión falso.

## Resumen de la Aproximación

`AuthMock` puede integrarse de manera completamente nativa en tus **Tests de iOS** (gracias a que compila en iOS 16+) importando el módulo `AuthMockServer`. Esto evita tener que lanzar scripts externos o luchar contra "servidores huérfanos" (Zombies) al ejecutar tus tests automatizados.

Para pruebas manuales en tu equipo, también puedes levantarlo desde tu terminal como un proceso independiente.

## Paso 1: Pruebas Automáticas Embedidas (XCTest / Swift Testing)

En lugar de levantar un proceso externo en segundo plano, tu capa de tests puede levantar el Mock Server bajo demanda, para cada test o suite, de forma local al motor de testing. Esto es especialmente útil tanto para *Unit Tests* como para *XCUI Tests*.

Añade `AuthMock` como dependencia en `Package.swift` o Xcode, **enlaza `AuthMockServer` únicamente en el target de tus Tests de iOS**, y arranca el entorno:

```swift
import XCTest
import AuthMockServer

final class LoginUITests: XCTestCase {
    var authMock: AuthMockTestApp!
    
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        
        // Arrancar silenciosamente en background en el hilo de test
        authMock = try await AuthMockTestApp(port: 8090)
        try await authMock.start()
    }
    
    override func tearDown() async throws {
        // Aseguramos que se libere el puerto para el próximo test
        try await authMock.stop()
        try await super.tearDown()
    }
    
    func test_cuandoElLoginFalla_MuestraAlertaError() async throws {
        let app = XCUIApplication()
        
        // 1. Altera el mock por código Swift (sin peticiones HTTP manuales crudas)
        await authMock.simulate(status: 401)
        
        // 2. Ejecutar Acción en la App
        app.launch()
        app.buttons["Login with Single Sign On"].tap()
        
        // 3. Resultado observable
        XCTAssertTrue(app.alerts["Credenciales incorrectas"].waitForExistence(timeout: 2.0))
    }
}
```

La app en ejecución en el Simulador compartirá el entorno de red de tu Mac, por lo que las peticiones a `http://127.0.0.1:8090` llegarán exitosamente al runner del Test.

## Paso 2: Levantar el Ejecutable en terminal (Desarrollo Manual)

Para poder realizar el login manual en tu Simulador iOS para experimentar (fuera de la suite de testing), asegúrate de levantar el servidor local en la terminal (fuera de Xcode):

```bash
cd /ruta/a/tu/Package/AuthMock
swift run AuthMock
```

Por defecto, esto levanta el servidor web en el puerto `8090`. Recuerda que tu app debe estar configurada en desarrollo para apuntar al endpoint *issuer* o host a `http://127.0.0.1:8090`. (Y autorizar `NSExceptionAllowsInsecureHTTPLoads` o usar configuraciones locales si fuera necesario en iOS).

## Paso 3: Automatizar el arranque del Mock en tu esquema de Xcode (Recomendado)

Si estás usando Xcode y has enlazado este paquete vía Swift Package Manager, puedes hacer que Xcode arranque el servidor de pruebas en segundo plano **automáticamente** justo antes de lanzar el simulador pulsando "Play", y lo cierre al hacer "Stop". Además, forzaremos a que Xcode pause el arranque de tu App hasta que el servidor local de Vapor confirme apertura de puerto.

1. Selecciona en Xcode tu esquema principal de iOS (e.g. `TuApp`).
2. Haz clic en **Edit Scheme...** 
3. En la barra lateral, expande la sección **Build** > **Pre-actions**. Da al `+` y selecciona "New Run Script Action".
4. En "Provide build settings from" elige el target de tu app principal.
5. Copia y pega el siguiente Shell Script:

```bash
# Limpiar entorno para aislar el compilador Swift (macOS) del SDK iOS
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# 1. Asegurar que no quede ninguno colgando de ejecuciones previas
lsof -n -iTCP:8090 -sTCP:LISTEN -t | xargs kill -9 2>/dev/null || true

# 2. Carpeta de DerivedData donde estan los SourcePackages de Xcode
CHECKOUT_DIR=$(find ~/Library/Developer/Xcode/DerivedData -maxdepth 5 -type d -path "*/SourcePackages/checkouts/AuthMock" 2>/dev/null | head -n 1)

if [ -n "$CHECKOUT_DIR" ]; then
    echo "Arrancando AuthMock en $CHECKOUT_DIR..." > /tmp/authmock_server.log
    cd "$CHECKOUT_DIR"
    
    # Arrancamos silenciosamente el backend
    nohup env -i PATH="$PATH" HOME="$HOME" /usr/bin/xcrun swift run AuthMock >> /tmp/authmock_server.log 2>&1 &
    
    # 3. Bloqueamos (pausamos) el build de Xcode hasta confirmar conexión de Vapor
    MAX_WAIT=240 # Timeout max en segundos (los cold-build de SPM pueden tardar más de un minuto)
    COUNT=0
    while ! nc -z localhost 8090; do
        sleep 0.5
        COUNT=$((COUNT+1))
        if [ $COUNT -ge $MAX_WAIT ]; then
            echo "Timeout esperando al servidor Mock." >> /tmp/authmock_server.log
            break
        fi
    done
else
    echo "AuthMock no encontrado en el DerivedData." > /tmp/authmock_server.log
fi
```

### Limpiar al detener

De la misma manera, para apagar el servidor backend y liberar puertos cuando pulses sobre "Stop" en Xcode, expande **Run** > **Post-actions** en el mismo panel de Esquemas y añade el siguiente comando rápido:

```bash
lsof -n -iTCP:8090 -sTCP:LISTEN -t | xargs kill -9 2>/dev/null || true
```
