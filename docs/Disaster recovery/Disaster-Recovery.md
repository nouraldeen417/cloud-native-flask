# Cross-Cloud Disaster Recovery (Azure → AWS)

## Purpose

This project runs the same application on two independent clouds (Azure AKS + Azure MySQL, AWS EKS + RDS MySQL). Beyond demonstrating multi-cloud deployment, it demonstrates a **realistic DR posture**: if Azure's database became unavailable, the AWS deployment could be brought current from a recent backup and serve as a fallback — without either cloud depending on the other's credentials, network, or uptime to make that possible.

**Target RPO: ~24 hours** (one nightly backup cycle). **RTO: manual, on the order of minutes** — restore is a single Kubernetes Job run against already-provisioned AWS infrastructure, not a from-scratch environment build.

---

## Why this design, specifically

Three constraints shaped the architecture, each deliberate:

1. **Azure must never hold AWS credentials.** A compromised Azure identity should not be able to read or write anything in the AWS account.
2. **RDS must never be reachable from the public internet.** No inbound rule for "my laptop's IP," no public accessibility flag — the security group only trusts the EKS cluster's own security group, same as the application's normal DB traffic.
3. **The backup destination (S3) must not be publicly writable or listable**, despite Azure needing to upload to it.

The design that satisfies all three: **Azure requests a short-lived, single-use, write-only presigned S3 URL from a small AWS Lambda function, uses it once, and never holds a standing AWS credential at all.**

---

## Architecture

```
Azure Container App Job (nightly, 2:00 AM UTC cron)
   │
   ├─ 1. Calls Lambda Function URL (public HTTPS endpoint, no auth required to invoke)
   │
   ▼
AWS Lambda (generate-presigned-url)
   │
   ├─ 2. Generates a PUT-only presigned S3 URL, expires in 30 minutes
   │
   ▼
Azure Container App Job
   │
   ├─ 3. mysqldump | gzip  (Azure MySQL Flexible Server)
   ├─ 4. curl -X PUT <presigned-url> --upload-file backup.sql.gz
   │
   ▼
S3 bucket (private, versioned, no public access)
   │
   │   ... time passes, potential fail-over triggered manually ...
   │
   ▼
Kubernetes Job on EKS (run manually during a fail-over drill)
   │
   ├─ 5. aws s3 cp s3://.../backup.sql.gz   (uses EKS node's LabRole — in-VPC, no public path)
   ├─ 6. mysql < backup.sql                 (RDS, reachable only from inside the VPC)
   │
   ▼
RDS MySQL — now current as of the last nightly backup
```

**Why each hop is secure by construction, not by convention:**
- Lambda's Function URL is public, but it does no data access itself — it only *mints a permission*, scoped to one object key, one HTTP verb (`PUT`), expiring in 30 minutes. Even if the URL leaked, it grants nothing beyond "upload one file, once, soon."
- Azure never has an AWS access key, secret key, or session token anywhere in its config — the presigned URL *is* the only credential involved, and it's ephemeral by design.
- The restore path runs **inside the EKS cluster's VPC**, using the same security-group trust relationship already validated by the application's normal DB connection and the schema-load PreSync hook — no new network exposure introduced for DR specifically.
- S3 bucket has no public access, no public listing — only reachable via the presigned URL (upload direction) or from inside the VPC via the node's IAM role (download direction).

---

## Prerequisites

### 1. S3 bucket — private, versioned

```bash
aws s3api create-bucket --bucket dr-mysql-backups-<account-id> --region us-east-1

aws s3api put-bucket-versioning \
  --bucket dr-mysql-backups-<account-id> \
  --versioning-configuration Status=Enabled

aws s3api put-public-access-block \
  --bucket dr-mysql-backups-<account-id> \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

Versioning means an accidental overwrite doesn't destroy the previous night's backup — every version stays recoverable, cheap insurance for close to no cost at this data size.

### 2. Lambda function — presigned URL generator

```python
import json
import os
import boto3
from datetime import datetime

s3_client = boto3.client('s3')

def lambda_handler(event, context):
    bucket_name = os.environ['S3_BUCKET_NAME']
    timestamp = datetime.utcnow().strftime('%Y-%m-%d_%H-%M-%S')
    object_key = f"mysql-backups/backup_{timestamp}.sql.gz"

    presigned_url = s3_client.generate_presigned_url(
        'put_object',
        Params={
            'Bucket': bucket_name,
            'Key': object_key,
            'ContentType': 'application/x-gzip'
        },
        ExpiresIn=1800
    )

    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({'upload_url': presigned_url, 'object_key': object_key})
    }
```

**IAM role for the Lambda** — needs only `s3:PutObject` scoped to this one bucket, nothing broader:
```bash
aws iam create-role --role-name lambda-presign-role \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
```
> If `iam:CreateRole` is blocked in your environment (e.g. Learner Lab), reuse `LabRole` for the Lambda's execution role instead — it already has broad S3 access per the Learner Lab guide, and the Lambda itself only ever *generates a URL*, never touches S3 directly, so the actual blast radius of the role's permissions is unused here anyway.

```bash
aws lambda create-function \
  --function-name generate-presigned-url \
  --runtime python3.12 \
  --role <lambda-execution-role-arn> \
  --handler lambda_function.lambda_handler \
  --zip-file fileb://lambda_function.zip \
  --environment "Variables={S3_BUCKET_NAME=dr-mysql-backups-<account-id>}"

aws lambda create-function-url-config \
  --function-name generate-presigned-url \
  --auth-type NONE
```
`auth-type NONE` is intentional and safe here — the function itself has no destructive capability; it only issues a scoped, time-limited permission. Restricting invocation further (e.g. `AWS_IAM` auth) would require Azure to hold an AWS credential to call it, defeating the entire point of this design.

### 3. RDS security — confirm no public path exists

```bash
aws rds describe-db-instances --db-instance-identifier rds-flaskapp-dev \
  --query "DBInstances[0].PubliclyAccessible"
```
Should return `false`. The security group (`aws_security_group.mysql` in `terraform/aws/rds.tf`) only allows inbound from the EKS cluster's own security group — confirmed and unchanged by anything in this DR setup.

---

## Backup — Azure Container App Job

```hcl
resource "azurerm_container_app_environment" "main" {
  name                       = "cae-${var.project_name}-${var.environment}"
  location                   = var.location
  resource_group_name        = data.azurerm_resource_group.rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
}

resource "azurerm_container_app_job" "mysql_s3_backup" {
  name                         = "job-mysql-s3-dr-backup"
  location                     = var.location
  resource_group_name          = data.azurerm_resource_group.rg.name
  container_app_environment_id = azurerm_container_app_environment.main.id
  replica_timeout_in_seconds   = 1800
  replica_retry_limit          = 1

  schedule_trigger_config {
    cron_expression = "30 2 * * *"   # nightly, 2:00 AM UTC
    parallelism     = 1
  }

  secret {
    name  = "mysql-password"
    value = var.mysql_admin_password
  }

  template {
    container {
      name   = "dr-backup-runner"
      image  = "alpine:3.20"
      cpu    = 0.5
      memory = "1Gi"

      command = [
        "/bin/sh", "-c",
        <<-EOF
          apk add --no-cache mysql-client curl jq gzip
          export MYSQL_PWD="$DB_PASS"

          RESPONSE=$(curl -s "$LAMBDA_FUNCTION_URL")
          UPLOAD_URL=$(echo "$RESPONSE" | jq -r .upload_url)

          if [ -z "$UPLOAD_URL" ] || [ "$UPLOAD_URL" = "null" ]; then
            echo "Error: Failed to fetch pre-signed URL from AWS Lambda."
            exit 1
          fi

          BACKUP_FILE="backup.sql.gz"
          mysqldump -h $DB_HOST -u $DB_USER --ssl \
                    --single-transaction --quick --routines \
                    $DB_NAME | gzip > $BACKUP_FILE

          curl -X PUT -H "Content-Type: application/x-gzip" \
               --upload-file $BACKUP_FILE "$UPLOAD_URL"

          echo "Database backup successfully uploaded to AWS S3!"
        EOF
      ]

      env { name = "LAMBDA_FUNCTION_URL" value = var.aws_lambda_function_url }
      env { name = "DB_HOST" value = azurerm_mysql_flexible_server.mysql.fqdn }
      env { name = "DB_USER" value = var.mysql_admin_username }
      env { name = "DB_NAME" value = var.mysql_database_name }
      env { name = "DB_PASS" secret_name = "mysql-password" }
    }
  }
}
```

**Note `MYSQL_PWD` env var, not `-p` flag** — passing the password via `mysqldump -p"$DB_PASS"` leaks it into process listings (`ps aux`) visible to anything else in the same container; `MYSQL_PWD` avoids that. `--routines` added so stored procedures are included in the dump — without it, only tables/data are captured, not `sp_createUser` etc., which the fresh RDS database wouldn't otherwise have after a restore.

**Verify a run manually before trusting the schedule:**
```bash
az containerapp job start --name job-mysql-s3-dr-backup --resource-group rg-flaskapp-dev
az containerapp job execution list --name job-mysql-s3-dr-backup --resource-group rg-flaskapp-dev -o table
aws s3 ls s3://dr-mysql-backups-<account-id>/mysql-backups/ --recursive --human-readable
```

---

## Restore — fail-over drill procedure

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: mysql-restore-from-s3
  namespace: default
spec:
  template:
    spec:
      restartPolicy: Never
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      containers:
        - name: restore-runner
          image: alpine:3.20
          command:
            - /bin/sh
            - -c
            - |
              set -e
              apk add --no-cache mysql-client aws-cli gzip
              aws s3 cp s3://dr-mysql-backups-<account-id>/mysql-backups/<backup-filename>.sql.gz /tmp/backup.sql.gz
              gunzip /tmp/backup.sql.gz
              mysql -h $MYSQL_DATABASE_HOST -u $MYSQL_DATABASE_USER -p"$DB_PASS" $MYSQL_DATABASE_DB < /tmp/backup.sql
              echo "Restore complete."
          envFrom:
            - configMapRef:
                name: flask-config
          env:
            - name: DB_PASS
              valueFrom:
                secretKeyRef:
                  name: mysql-secret
                  key: MYSQL_DATABASE_PASSWORD
```

```bash
# pick the backup to restore
aws s3 ls s3://dr-mysql-backups-<account-id>/mysql-backups/ --recursive
# edit the filename in restore-job.yml to match, then:
kubectl apply -f restore-job.yml
kubectl logs -f job/mysql-restore-from-s3 -n default
kubectl delete job mysql-restore-from-s3 -n default
```

**Why `hostNetwork: true` + `dnsPolicy: ClusterFirstWithHostNet` are required here too:** same IMDS hop-limit issue documented in `docs/aws/OPERATIONS.md` — the `aws s3 cp` step needs to reach instance metadata to authenticate via the node's `LabRole`, which requires the pod to share the host's network namespace; the DNS policy override keeps in-cluster name resolution (for `$MYSQL_DATABASE_HOST`, resolved via the `flask-config` ConfigMap, not DNS — but the policy is included defensively in case future versions of this Job add any in-cluster lookups).

### Known post-restore step: collation mismatch

Azure MySQL Flexible Server and RDS MySQL 8.0 have different **default collations** (`utf8mb4_unicode_ci` vs. `utf8mb4_0900_ai_ci`). A schema created without an explicit `COLLATE` clause inherits whichever server's default it was created under — restoring across clouds means the collation embedded in the dump may not match the target server's default, causing `Illegal mix of collations` errors on any query comparing values across that boundary.

**Fixed two ways in this project:**
1. **Forward-looking** — `terraform/aws/rds.tf`'s parameter group explicitly pins `collation_server = utf8mb4_unicode_ci` to match Azure, so future restores land collation-matched automatically.
2. **One-time correction for already-restored data:**
```sql
ALTER TABLE tbl_user CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
ALTER TABLE tbl_wish CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
```

---

## Limitations, stated honestly

- **RPO is ~24h, not lower** — accepted tradeoff for zero ongoing cost and minimal complexity, appropriate for this project's scope.
- **Restore is manual, not automatic fail-over** — this is backup-and-restore DR, not hot/warm standby. No traffic automatically shifts to AWS if Azure goes down; a human runs the restore Job deliberately.
- **The nightly backup schedule itself is not validated to survive Learner Lab session expiration on the AWS side** — the *backup* runs entirely from Azure (ACA + Lambda + S3), so it's unaffected by AWS Learner Lab session credentials expiring. The *restore* step, however, requires an active `kubectl` connection to EKS, which does depend on Learner Lab session validity at the time of the drill — refresh credentials (`./refresh-aws-lab-creds.sh`) before attempting a restore if it's been a while since the last session.
- **No automated testing of the restore path** — validated manually once during this project's build (including discovering and fixing the collation issue); not re-verified on every backup cycle.