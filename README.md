# Highly Confidential

kubectl delete password.generators.external-secrets.io password-gen -n auth


Investigation into Prisma Cloud Compute Credential Rotation 

Starting Point: 

High impact for local admin sign-in and service account API keys.

Current State & Risks: 

Service account keys are often long-lived. Prisma Cloud allows up to two keys simultaneously, facilitating zero-downtime rotation.

Proposed Implementation:

Method: Automated (Dual-Key Strategy).
Process: Use Azure Key Vault and a Function App triggered by "SecretNearExpiry" events to generate a new key via API and rotate the inactive key.

Testing and Verification: Verify automated key updates in AKV and successful authentication for dependent security pipelines.

Proposed Rotation Steps
Generate New Key: Via Prisma API.
Update K8s Secret via ESO/AKV: Sync dual keys.
Update Prisma: Rotate inactive key.
References
Logging into Prisma Cloud - https://docs.prismacloud.io/en/compute-edition/30/admin-guide/authentication/login
Operate Efficiently and Securely: Rotating Prisma Cloud Access ... - https://www.paloaltonetworks.com/blog/cloud-security/operate-efficiently-and-securely-rotating-prisma-cloud-access-keys/
