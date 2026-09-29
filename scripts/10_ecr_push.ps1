. "$PSScriptRoot\env.ps1"
Set-Location "$PSScriptRoot\.."
Start-Transcript -Path evidencias\E6\push.txt -Force | Out-Null

$sha = (git rev-parse --short HEAD).Trim()
$registro = ((aws ecr describe-repositories --repository-names lomax-backend --query "repositories[0].repositoryUri" --output text) -join "").Split("/")[0]
"Commit de entrega: $sha"
"Registro         : $registro"
"Cambios sin commitear (vacio = imagen corresponde al commit):"
git status --porcelain

"=== Login ==="
aws ecr get-login-password | docker login --username AWS --password-stdin $registro 2>&1 | ForEach-Object { "$_" }

foreach ($n in "backend","frontend","proxy") {
  $ref = "$registro/lomax-$($n):$sha"
  "=== $n -> $ref ==="
  docker tag "lomax-$($n):dev" $ref
  docker push $ref 2>&1 | ForEach-Object { "$_" }
}

"=== ecr describe-images ==="
foreach ($n in "backend","frontend","proxy") {
  "--- lomax-$n"
  aws ecr describe-images --repository-name "lomax-$n" --query "imageDetails[].[imageTags[0],imageDigest,imageSizeInBytes]" --output text
}
"=== ecr list-images ==="
foreach ($n in "backend","frontend","proxy") {
  aws ecr list-images --repository-name "lomax-$n" --output json
}

Stop-Transcript | Out-Null
