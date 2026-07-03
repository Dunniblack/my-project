# Step 1: Delete the immutable K8s Secret. ESO will detect the binding is broken.
kubectl delete secret keycloak-pgpass -n auth

# Step 2: Force ESO to re-evaluate immediately (don't wait for the next reconcile cycle).
kubectl annotate externalsecret keycloak-pgpass -n auth force-sync="$(date +%s)" --overwrite

# Step 3: Wait for ESO to regenerate the Secret (usually < 30 seconds).
#   The status condition flips to SecretSynced when done.
until kubectl get secret keycloak-pgpass -n auth >/dev/null 2>&1; do
  echo "Waiting for ESO to regenerate keycloak-pgpass..."
  sleep 2
done
# Verify the new Secret is immutable and has a different value
kubectl get secret keycloak-pgpass -n auth -o jsonpath='{.immutable}'   # should print true
kubectl get secret keycloak-pgpass -n auth -o jsonpath='{.data.keycloak-pgpass}' | base64 -d
# Compare with /tmp/kc-pgpass-old.txt — they should DIFFER

# Step 4: Restart the keycloak-db StatefulSet pod.
#   On startup, the entrypoint will ALTER USER keycloak PASSWORD '<new>' via local socket.
kubectl delete pod keycloak-db-0 -n auth
# Wait for it to come back Ready
kubectl wait pod -n auth keycloak-db-0 --for=condition=Ready --timeout=300s

# Step 5: Restart the keycloak Deployment so it picks up the new Secret mount
#   and reads the new password in startup.sh.
kubectl rollout restart deployment keycloak -n auth
kubectl rollout status deployment keycloak -n auth --timeout=600s
