#!/usr/bin/env bash
# Runs every gateway route and role rule and prints PASS / FAIL for each.
# Everything goes through the gateway, the way the frontend calls the backend.
# Tokens and ids are passed along automatically; both test accounts are deleted
# at the end (straight through user-service, which the gateway does not route
# for deletes).
#
#   Git Bash:          bash curl/run-all.sh
#   Show answers too:  SHOW=1 bash curl/run-all.sh
#
# Left behind: the test salon, category and service, the cancelled booking and
# one Razorpay TEST-mode payment link.

GATEWAY_URL="${GATEWAY_URL:-http://localhost:5002}"
USER_URL="${USER_URL:-http://localhost:5009}"          # only for the final deletes
KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:8080}"
CLIENT_SECRET="${KEYCLOAK_CLIENT_SECRET:?set KEYCLOAK_CLIENT_SECRET first}"
ADMIN_USER="${KEYCLOAK_ADMIN_USERNAME:?set KEYCLOAK_ADMIN_USERNAME first}"
ADMIN_PASS="${KEYCLOAK_ADMIN_PASSWORD:?set KEYCLOAK_ADMIN_PASSWORD first}"
PASSWORD="Passw0rd-123"

N=$(date +%s | tail -c 7)
OWNER="gwowner$N"; CUSTOMER="gwcustomer$N"
DAY=$(date -d "+1 day" +%F 2>/dev/null || date -v+1d +%F)

PASSED=0; FAILED=0

request() {
  local expect="$1" title="$2"; shift 2
  local out code
  out=$(curl --silent --location --write-out $'\n%{http_code}' "$@")
  code="${out##*$'\n'}"; BODY="${out%$'\n'*}"
  if [ "$code" = "$expect" ]; then
    PASSED=$((PASSED+1)); printf '  PASS  %-50s %s\n' "$title" "$code"
  else
    FAILED=$((FAILED+1)); printf '  FAIL  %-50s %s (expected %s)\n         %s\n' "$title" "$code" "$expect" "${BODY:0:200}"
  fi
  [ -n "$SHOW" ] && printf '         %s\n' "${BODY:0:300}"
}

field() {
  printf '%s' "$BODY" | grep -o "\"$1\":\"\?[^\",}]*" | head -1 | sed 's/^"[^"]*":"\{0,1\}//'
}

JSON='Content-Type: application/json'
G="$GATEWAY_URL"

echo "gateway at $G"
if ! curl --silent --max-time 5 --output /dev/null "$G/actuator/health"; then
  echo "The gateway is not answering at $G. Start it first."; exit 1
fi

echo; echo "Open routes (no token)"
request 200 "Gateway health" "$G/actuator/health"
request 200 "Sign up customer ($CUSTOMER)" -X POST "$G/auth/signup" -H "$JSON" \
  --data "{\"email\":\"$CUSTOMER@example.com\",\"username\":\"$CUSTOMER\",\"password\":\"$PASSWORD\",\"fullName\":\"Gateway Customer\",\"role\":\"CUSTOMER\"}"
CUSTOMER_TOKEN=$(field jwt)
request 200 "Sign up salon owner ($OWNER)" -X POST "$G/auth/signup" -H "$JSON" \
  --data "{\"email\":\"$OWNER@example.com\",\"username\":\"$OWNER\",\"password\":\"$PASSWORD\",\"fullName\":\"Gateway Owner\",\"role\":\"SALON_OWNER\"}"
OWNER_TOKEN=$(field jwt)
request 200 "Admin token from Keycloak" -X POST "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
  --data-urlencode "client_id=salon-booking-client" --data-urlencode "client_secret=$CLIENT_SECRET" \
  --data-urlencode "grant_type=password" --data-urlencode "username=$ADMIN_USER" --data-urlencode "password=$ADMIN_PASS"
ADMIN=$(field access_token)

C=(-H "Authorization: Bearer $CUSTOMER_TOKEN")
O=(-H "Authorization: Bearer $OWNER_TOKEN")

echo; echo "user-service"
request 200 "My profile" "$G/api/users/profile" "${C[@]}"
CUSTOMER_ID=$(field id)
request 200 "All users (admin)" "$G/api/users" -H "Authorization: Bearer $ADMIN"

echo; echo "salon, category, service-offering"
request 200 "All salons" "$G/api/salons" "${C[@]}"
request 200 "Search salons by city" "$G/api/salons/search?city=Pune" "${C[@]}"
request 200 "Create salon (owner)" -X POST "$G/api/salons/createSalon" -H "$JSON" "${O[@]}" \
  --data "{\"name\":\"Gateway Test Salon $N\",\"address\":\"12 MG Road\",\"city\":\"Pune\",\"phoneNumber\":\"9876543210\",\"email\":\"gwsalon$N@example.com\",\"images\":[\"https://example.com/salon.jpg\"],\"openTime\":\"09:00:00\",\"closeTime\":\"20:00:00\"}"
SALON_ID=$(field id)
request 200 "One salon" "$G/api/salons/$SALON_ID" "${C[@]}"
request 200 "Create category (owner)" -X POST "$G/api/category/salon-owner" -H "$JSON" "${O[@]}" \
  --data '{"name":"Hair","image":"https://example.com/hair.jpg"}'
CATEGORY_ID=$(field id)
request 200 "Create service (owner)" -X POST "$G/api/service-offering/salon-owner" -H "$JSON" "${O[@]}" \
  --data "{\"name\":\"Haircut\",\"description\":\"Wash and cut\",\"price\":500,\"duration\":30,\"categoryId\":$CATEGORY_ID,\"image\":\"https://example.com/haircut.jpg\"}"
SERVICE_ID=$(field id)
request 200 "Categories of the salon" "$G/api/category/salonId/$SALON_ID" "${C[@]}"
request 200 "Services of the salon" "$G/api/service-offering/salon/$SALON_ID" "${C[@]}"

echo; echo "booking, notification"
request 201 "Book $DAY 10:00" -X POST "$G/api/bookings?salonId=$SALON_ID&paymentMethod=RAZORPAY" -H "$JSON" "${C[@]}" \
  --data "{\"startTime\":\"${DAY}T10:00:00\",\"servicesIds\":[$SERVICE_ID]}"
request 200 "My bookings" "$G/api/bookings/customer" "${C[@]}"
BOOKING_ID=$(field id)
request 200 "Salon report (owner)" "$G/api/bookings/report" "${O[@]}"
request 200 "My notifications" "$G/api/notifications/user/$CUSTOMER_ID" "${C[@]}"

echo; echo "What the gateway blocks (each should fail)"
request 401 "API call without a token" "$G/api/salons"
request 401 "Broken token" "$G/api/users/profile" -H "Authorization: Bearer not.a.real.token"
request 403 "Customer lists all users" "$G/api/users" "${C[@]}"
request 403 "Customer creates a salon" -X POST "$G/api/salons/createSalon" -H "$JSON" "${C[@]}" --data '{"name":"Not Allowed"}'
request 403 "Customer creates a category" -X POST "$G/api/category/salon-owner" -H "$JSON" "${C[@]}" --data '{"name":"Not Allowed"}'
request 403 "Customer asks for a salon report" "$G/api/bookings/report" "${C[@]}"
request 403 "Anyone calls /api/payments/create" -X POST "$G/api/payments/create?paymentMethod=RAZORPAY" -H "$JSON" "${C[@]}" --data '{"id":1}'
request 403 "Customer lists every notification" "$G/api/notifications" "${C[@]}"
request 403 "A path no rule allows" "$G/api/somethingelse" "${C[@]}"

echo; echo "Clean up"
request 200 "Cancel the booking" -X PUT "$G/api/bookings/$BOOKING_ID/status?status=CANCELLED" "${C[@]}"
BODY=$(curl --silent "$G/api/users/profile" "${O[@]}"); OWNER_ID=$(field id)
request 202 "Delete test customer account" -X DELETE "$USER_URL/api/deleteById/$CUSTOMER_ID" -H "Authorization: Bearer $ADMIN"
request 202 "Delete test owner account" -X DELETE "$USER_URL/api/deleteById/$OWNER_ID" -H "Authorization: Bearer $ADMIN"

echo; echo "$PASSED passed, $FAILED failed"
[ "$FAILED" = 0 ]
