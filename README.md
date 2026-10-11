# AuthMock

Servidor OAuth falso, mínimo y genérico — no emula WorkOS ni ningún proveedor concreto,
solo la interfaz de comunicación que cualquier app o API espera de un Authorization
Server: un endpoint que da un token, y un JWKS para verificar su firma. Sirve para probar,
sin credenciales reales, un servidor que verifique tokens (p. ej. con `WorkOSBearerAuth`) y
las apps que los piden.

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
  de un servidor real, `AuthMock` nunca se despliega a producción, así que no protege nada
  que necesite estar detrás de una variable de entorno.

## Uso típico

- **Un servidor que verifique tokens con `WorkOSBearerAuth`** usa
  `.local(port:resourceIndicatorsRaw:)` apuntando al puerto de este mock: el issuer es siempre
  `http://127.0.0.1:<puerto>` (`WorkOSBearerAuth` descubre `oauth2/jwks` a partir de él) y el
  resource indicator debe ser un valor `https://` que coincida con `AUTHMOCK_AUDIENCE` (nunca se
  dereferencia por red, así que su scheme no tiene por qué coincidir con el del issuer). Esa
  configuración se rechaza en producción. Ver «Las tres configuraciones» en los docs de
  `WorkOSBearerAuth`.
- **Una suite de tests** puede arrancar el mock en el propio proceso con `AuthMockTestApp`
  (producto `AuthMockServer`: `start()`, `stop()`, `simulate(status:)`, `simulate(claims:)`,
  `listeningPort`) en vez de lanzar el ejecutable.
- **Una app cliente**, en modo de pruebas, puede llamar a `POST /token` directamente en vez de
  hacer el flujo OAuth completo y guardar el token como si viniera de un login real: este
  servidor no valida ningún `code` ni `codeVerifier`.
- **Postman, o cualquier cliente HTTP manual**: llama a `POST /token`, coge el
  `access_token` de la respuesta, y lo usa como Bearer contra un servidor local cuyo issuer
  apunte aquí — funciona ya, sin ningún cambio en ningún otro repo.

## Regenerar la clave de prueba

No hace falta salvo que la actual se filtre o se quiera rotar por rutina — no protege
nada real, así que no hay urgencia:

```bash
cd Sources/AuthMockServer/Fixtures
openssl genrsa -out test-private-key.pem 2048
# recalcular test-jwks.json a partir de la nueva clave, con el mismo formato que el actual:
# `n` = módulo RSA en base64url (`openssl rsa -in test-private-key.pem -noout -modulus`),
# `e` = "AQAB", `kid` = "authmock-key-1"
```
