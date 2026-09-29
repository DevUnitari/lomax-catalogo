. "$PSScriptRoot\env.ps1"
foreach ($b in "lomax-originales","lomax-miniaturas") {
  aws s3api head-bucket --bucket $b *> $null
  if ($LASTEXITCODE -ne 0) { aws s3api create-bucket --bucket $b | Out-Null; "creado $b" }
  else { "ya existe $b" }
}
aws s3api list-buckets --query "Buckets[].Name" --output text
