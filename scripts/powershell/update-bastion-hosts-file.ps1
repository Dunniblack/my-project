kubectl get configmap keycloak-bootstrap-script -n auth -o yaml

kubectl get configmap keycloak-db-pgstartup -n auth -o yaml

kubectl get configmap keycloak-config -n auth -o yaml | head -100

kubectl get clustersecretstore azure-key-vault -o yaml

kubectl get generators.external-secrets.io password-gen -A -o yaml

kubectl get externalsecret -n auth -o yaml | Select-String -A5 "keycloak-admin-password\|keycloak-pgpass"

kubectl describe pod -n auth keycloak-68ddf45744-x97n7 | tail -60
kubectl get events -n auth --field-selector involvedObject.name=keycloak-68ddf45744-x97n7 --sort-by='.lastTimestamp' | tail -30

kubectl logs -n auth keycloak-68ddf45744-x97n7 --previous --tail=200
