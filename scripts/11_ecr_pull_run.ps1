param([string]$Tag = "f1e5c46")
. "$PSScriptRoot\env.ps1"
Set-Location "$PSScriptRoot\.."
. "$PSScriptRoot\lib_api.ps1"
Start-Transcript -Path evidencias\E6\pull_run.txt -Force | Out-Null

$registro = ((aws ecr describe-repositories --repository-names lomax-backend --query "repositories[0].repositoryUri" --output text) -join "").Split("/")[0]
$env:REGISTRO = $registro
$env:TAG = $Tag
"Registro: $registro   Tag: $Tag"

"=== 1. Detener servicios propios (floci y RDS siguen arriba) y borrar copias locales ==="
docker compose stop api frontend proxy 2>&1 | ForEach-Object { "$_" }
docker compose rm -f api frontend proxy 2>&1 | ForEach-Object { "$_" }
foreach ($n in "backend","frontend","proxy") {
  docker rmi "lomax-$($n):dev" "$registro/lomax-$($n):$Tag" 2>&1 | ForEach-Object { "$_" }
}
"Imagenes lomax locales tras borrar (debe estar vacio):"
docker images --format "{{.Repository}}:{{.Tag}}" | Where-Object { $_ -like "*lomax*" }

"=== 2. Login y pull por referencia remota ==="
aws ecr get-login-password | docker login --username AWS --password-stdin $registro 2>&1 | ForEach-Object { "$_" }
foreach ($n in "backend","frontend","proxy") {
  docker pull "$registro/lomax-$($n):$Tag" 2>&1 | ForEach-Object { "$_" }
}

"=== 3. Digest remoto (ECR) frente a digest descargado ==="
foreach ($n in "backend","frontend","proxy") {
  $ref = "$registro/lomax-$($n):$Tag"
  $remoto = ((aws ecr describe-images --repository-name "lomax-$n" --image-ids imageTag=$Tag --query "imageDetails[0].imageDigest" --output text) -join "").Trim()
  $descargado = ((docker inspect --format "{{index .RepoDigests 0}}" $ref) -join "").Trim()
  "lomax-$n remoto     : $remoto"
  "lomax-$n descargado : $descargado"
  Check "digest coincide: lomax-$n" ($descargado -like "*@$remoto")
}

"=== 4. Ejecutar las imagenes descargadas ==="
docker compose -f docker-compose.yml -f docker-compose.ecr.yml up -d --no-build 2>&1 | ForEach-Object { "$_" }
Start-Sleep -Seconds 10
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"

"=== 5. API y frontend funcionando con las imagenes de ECR ==="
curl.exe -s -i "$Base/health"
$f = & curl.exe -s -o NUL -w "%{http_code}" http://localhost:8080/
Check "frontend 200" ($f -eq "200")
$r = Api GET "/productos"
$n = @(Lista $r.Json).Count
Check "catalogo via proxy: $n productos (esperado >= 21)" ($n -ge 21)

"RESULTADO: PASS=$($script:ok)  FAIL=$($script:fallos)"
Stop-Transcript | Out-Null
