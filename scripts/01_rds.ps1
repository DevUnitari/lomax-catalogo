. "$PSScriptRoot\env.ps1"
aws rds describe-db-instances --db-instance-identifier lomax-db *> $null
if ($LASTEXITCODE -ne 0) {
  aws rds create-db-instance --db-instance-identifier lomax-db `
    --db-instance-class db.t3.micro --engine postgres `
    --master-username postgres --master-user-password postgres123 `
    --allocated-storage 20 --publicly-accessible | Out-Null
  "RDS creada"
} else { "RDS ya existe" }
psql -f /db/01_schema.sql
psql -f /db/02_seed.sql
