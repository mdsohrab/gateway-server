# Gateway Server – Changes (2026-10-14)

## Summary

One problem was fixed: the health endpoint was blocked by the security rules.
All 5 tests pass (`mvnw.cmd test`): the 1 existing test plus 4 new ones.

## What was changed

### 1. `src/main/java/com/sohrab/gateway_server/Config/SecurityConfig.java`

**Problem:** `application.yml` exposes the `health` actuator endpoint, but the
security rules end in `.anyExchange().denyAll()`, so `/actuator/health` returned
401 for everyone. A Docker or Kubernetes health check on the gateway would
always mark it unhealthy.

**Change:** added one rule, after the `/api/notifications/ws/**` rule:

```java
// health only, for container probes; every other actuator endpoint stays denied
.pathMatchers("/actuator/health/**").permitAll()
```

Every other actuator endpoint (including `/actuator/gateway`, which can edit
routes) is still denied.

### 2. `src/main/resources/application.yml`

**Change:** enabled the health probes, so `/actuator/health/liveness` and
`/actuator/health/readiness` exist:

```yaml
management:
  endpoints:
    web:
      exposure:
        include: gateway,health,info
  endpoint:
    health:
      probes:
        enabled: true
```

### 3. `src/test/java/com/sohrab/gateway_server/SecurityConfigTests.java` (new file)

Four tests that guard the security rules:

| Test | Request | Expected |
|---|---|---|
| `healthIsOpen` | `GET /actuator/health/liveness` | 200 |
| `otherActuatorEndpointsNeedAToken` | `GET /actuator/gateway/routes` | 401 |
| `apiNeedsAToken` | `GET /api/users/profile` | 401 |
| `unknownPathNeedsAToken` | `GET /user-service/api/users` | 401 |

## What was not changed (needs a decision)

### 1. Admin routes are unreachable

`/api/admin/salons/**`, `/api/admin/users/**` and `/salons/**` are routed in
`application.yml` but have no security rule, so they hit `denyAll`.

If those endpoints exist in the salon and user services, add this line in
`SecurityConfig.java` before the `/api/users` rule:

```java
.pathMatchers("/api/admin/**").hasRole("ADMIN")
```

Not added because it opens access, and the salon and user services were not
available to confirm the endpoints.

### 2. WebSocket path is open but has no target

`/api/notifications/ws/**` is `permitAll`, but the `Notification` project has
no WebSocket endpoint. Harmless today; remove the rule if no WebSocket is
planned.

### 3. Category path to confirm

The gateway routes `/api/category/**`. The original tutorial code uses
`/api/categories`. Confirm which one the category service uses; a mismatch
means 404s.

## Minor notes (no action needed now)

- `spring.cloud.gateway.discovery.locator.enabled: true` creates extra
  `/service-name/**` routes that security denies anyway. It can be removed.
- The Keycloak default points at the `master` realm. Fine locally; use a
  dedicated realm through `KEYCLOAK_JWK_SET_URI` in production.
- The Jib image name is `codecaptcha/gateway-server-yt:v1`. Change it to your
  own Docker Hub account before pushing.

## How to verify

```
mvnw.cmd test
```

Expected: `Tests run: 5, Failures: 0, Errors: 0` and `BUILD SUCCESS`.
The Eureka "Connection refused" messages in the log only mean Eureka is not
running locally; they do not fail the tests.
