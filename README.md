# AuthMock

Servidor OAuth falso, mínimo y genérico — no emula WorkOS ni ningún proveedor concreto,
solo la interfaz de comunicación que cualquier app o API espera de un Authorization
Server: un endpoint que da un token, y un JWKS para verificar su firma. Compartido entre
[`FinanceCore`](../FinanceCore) y [`FinanceiOS`](../FinanceiOS) — ver
[ADR 0009](../FinanceCore/FinanceCore-MDs/Documentation/ADRs/0009-authmock-shared-fake-oauth-server.md)
y [ADR 0010](../FinanceCore/FinanceCore-MDs/Documentation/ADRs/0010-http-issuer-exception-for-loopback-in-test.md)
de `FinanceCore` para el porqué.

Deliberadamente simple: un único proceso nativo, sin Docker, sin túnel — HTTP plano en
`localhost`. No hace falta que sea seguro ni completo: la clave privada de prueba está
comiteada en este mismo repo (`Sources/AuthMockServer/Fixtures/test-private-key.pem`) y no
protege nada real. No simula `/oauth2/authorize` ni `/oauth2/register` — solo lo que hace
falta para obtener y verificar un token.

## Arrancar

```bash
swift run AuthMock
```

Configuración por variable de entorno (todas opcionales):

| Variable | Por defecto | Qué hace |
|---|---|---|
| `AUTHMOCK_PORT` | `8090` | Puerto HTTP |
| `AUTHMOCK_STATUS` | `200` | Código con el que responde `POST /token` — un 2xx firma y devuelve un token válido; cualquier otro código responde igual, con un cuerpo de error, sin firmar nada |
| `AUTHMOCK_ISSUER` | `http://127.0.0.1:<puerto>` | El `iss` de los tokens firmados — debe coincidir con lo que espere quien los verifique |
| `AUTHMOCK_AUDIENCE` | `authmock-audience` | El `aud` (resource indicator) de los tokens firmados |
| `AUTHMOCK_EXPIRES_IN` | `3600` | Segundos de vigencia del token, desde que se emite |

Ejemplo, simulando un fallo de autenticación:

```bash
AUTHMOCK_STATUS=401 swift run AuthMock
```

## Endpoints

- `GET /health` — `"ok"`, para scripts que esperan a que el proceso esté listo.
- `GET /oauth2/jwks` — la clave pública, en formato JWKS estándar (RFC 7517), en la misma
  ruta que serviría un Authorization Server real de WorkOS — `WorkOSBearerAuth` siempre
  pide `{issuer}/oauth2/jwks`, no una ruta configurable.
- `POST /token` — sin cuerpo ni parámetros: responde con `AUTHMOCK_STATUS` por defecto, o
  con el próximo valor armado vía `POST /_test/status` si hay uno pendiente (se consume al
  primer uso — ver más abajo). Éxito:
  ```json
  {"access_token": "...", "token_type": "Bearer", "expires_in": 3600}
  ```
  Fallo (status fuera de 2xx), con ese mismo código HTTP:
  ```json
  {"error": "mock_error", "error_description": "AuthMock configured with AUTHMOCK_STATUS=401"}
  ```
- `POST /_test/status` — `{"status": 401}`. Arma, una sola vez, el status que devolverá el
  próximo `POST /token`; después de consumirse, `/token` vuelve a `AUTHMOCK_STATUS`. Deja
  que un mismo test reproduzca "el primer intento de login falla, el segundo funciona" sin
  reiniciar el proceso a mitad de flujo. Endpoint de test, no forma parte de la interfaz
  OAuth que este servidor simula — no hace falta ningún flag para activarlo: a diferencia
  de `FinanceCore`, `AuthMock` nunca se despliega a producción, así que no protege nada
  que necesite estar detrás de una variable de entorno.

## Uso típico

- **`FinanceCore`** apunta `WORKOS_ISSUER` a `http://127.0.0.1:<puerto>` (el issuer, no la
  URL del JWKS — `WorkOSBearerAuth` descubre `oauth2/jwks` a partir de él) y
  `WORKOS_RESOURCE_INDICATORS` a un valor `https://` que coincida con `AUTHMOCK_AUDIENCE`
  (nunca se dereferencia por red, así que su scheme no tiene por qué coincidir con el del
  issuer — ver ADR 0004), para que `BearerAuthMiddleware` verifique tokens reales emitidos
  por este mock. Necesita `OAUTH_ALLOW_HTTP_LOOPBACK_ISSUER=true`, la excepción de issuer
  `http://` en loopback de
  [ADR 0010](../FinanceCore/FinanceCore-MDs/Documentation/ADRs/0010-http-issuer-exception-for-loopback-in-test.md).
- **`FinanceiOS`**, en `.local`/`.ci`, llama a `POST /token` directamente vía
  `AuthMockAPIClient` (no `AuthAPIClient`, que asume el contrato completo de WorkOS) y
  guarda el token como si viniera de un login real — `MockWebAuthPresenter` fabrica el
  `code` de callback sin abrir `ASWebAuthenticationSession`, y `AuthMockAPIClient` ignora
  ese `code`/`codeVerifier` al llamar aquí, ya que este servidor tampoco los valida (ver
  `Diseño CI - Estrategia de pruebas local.md` de `FinanceiOS`, §4).
- **Postman, o cualquier cliente HTTP manual**: llama a `POST /token`, coge el
  `access_token` de la respuesta, y lo usa como Bearer contra un `FinanceCore` local que
  tenga `WORKOS_ISSUER` apuntando aquí — funciona ya, sin ningún cambio en ningún otro
  repo.

## Regenerar la clave de prueba

No hace falta salvo que la actual se filtre o se quiera rotar por rutina — no protege
nada real, así que no hay urgencia:

```bash
cd Sources/AuthMockServer/Fixtures
openssl genrsa -out test-private-key.pem 2048
# recalcular test-jwks.json a partir de la nueva clave — ver el script equivalente en
# FinanceCore/scripts/e2e-local.sh (sección "Generating a local-only test signing key")
```
