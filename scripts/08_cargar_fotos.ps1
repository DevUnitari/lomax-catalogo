. "$PSScriptRoot\env.ps1"
Set-Location "$PSScriptRoot\.."
. "$PSScriptRoot\lib_api.ps1"
Start-Transcript -Path evidencias\E4\carga_fotos.txt -Force | Out-Null

function Sql($Consulta) { ((psql -t -A -c $Consulta) -join "").Trim() }

$ids = @((psql -t -A -c "SELECT producto_id FROM productos WHERE codigo NOT LIKE 'TST%' ORDER BY producto_id") | Where-Object { $_.Trim() -ne "" } | ForEach-Object { [int]$_.Trim() })
"Productos a cargar: $($ids.Count)"

for ($i = 1; $i -le $ids.Count; $i++) {
  $id = $ids[$i - 1]
  $foto = "fotos\$i.jpg"
  if (-not (Test-Path $foto)) { $foto = "fotos\$i.png" }
  $r = Api POST "/productos/$id/imagen" -Archivo $foto
  "HTTP $($r.Status) producto_id=$id foto=$foto estado=$($r.Json.estado)"
}

"=== Conteos finales ==="
"RDS PUBLICADO         : " + (Sql "SELECT count(*) FROM productos WHERE estado='PUBLICADO'")
'{":e":{"S":"LISTA"}}' | Set-Content -Encoding ascii evidencias\E4\_vals.json
"DynamoDB LISTA        : " + ((aws dynamodb scan --table-name productos_atributos --filter-expression "estado_procesamiento = :e" --expression-attribute-values file://evidencias/E4/_vals.json --select COUNT --query Count --output text) -join "")
"S3 originales/        : " + ((aws s3api list-objects-v2 --bucket lomax-originales --prefix originales/ --query "length(Contents)" --output text) -join "")
"S3 miniaturas/        : " + ((aws s3api list-objects-v2 --bucket lomax-miniaturas --prefix miniaturas/ --query "length(Contents)" --output text) -join "")
$r = Api GET "/productos"
"API GET /productos    : " + @(Lista $r.Json).Count

Stop-Transcript | Out-Null
