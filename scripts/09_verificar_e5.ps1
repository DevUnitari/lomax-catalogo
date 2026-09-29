. "$PSScriptRoot\env.ps1"
Set-Location "$PSScriptRoot\.."
. "$PSScriptRoot\lib_api.ps1"
Start-Transcript -Path evidencias\E5\reporte_e5.txt -Force | Out-Null

$id = Sql "SELECT producto_id FROM productos WHERE codigo='TEC-100'"
"producto_id del registro valido (TEC-100): $id"

"=== A. Registro TEC-100 en RDS ==="
psql -c "SELECT producto_id, codigo, nombre, precio, categoria_id, estado FROM productos WHERE producto_id=$id"
Check "RDS: TEC-100 PUBLICADO" ((Sql "SELECT estado FROM productos WHERE producto_id=$id") -eq "PUBLICADO")

"=== B. Registro TEC-100 en DynamoDB (get-item) ==="
aws dynamodb get-item --table-name productos_atributos --key "producto_id={N=$id}" --output json
Check "DynamoDB: tipo TECLADO" ((Dyn $id "Item.tipo.S") -eq "TECLADO")
Check "DynamoDB: estado LISTA" ((Dyn $id "Item.estado_procesamiento.S") -eq "LISTA")
Check "DynamoDB: miniatura_key = miniaturas/$id.jpg" ((Dyn $id "Item.miniatura_key.S") -eq "miniaturas/$id.jpg")

"=== C. Objetos en S3 ==="
$claveOrig = Dyn $id "Item.imagen_original_key.S"
"clave del original: $claveOrig"
Check "S3: original existe" (S3Existe "lomax-originales" $claveOrig)
Check "S3: miniatura existe" (S3Existe "lomax-miniaturas" "miniaturas/$id.jpg")

"=== D. Miniatura: S3 frente al endpoint (via proxy) ==="
$s3 = "evidencias\E5\miniatura_$($id)_s3.jpg"
$ep = "evidencias\E5\miniatura_$($id)_endpoint.jpg"
aws s3api get-object --bucket lomax-miniaturas --key "miniaturas/$id.jpg" $s3 | Out-Null
$meta = & curl.exe -s -o $ep -w "%{http_code} %{content_type}" "$Base/productos/$id/imagen"
Check "endpoint 200 image/jpeg ($meta)" ($meta -eq "200 image/jpeg")
$h1 = (Get-FileHash $s3 -Algorithm MD5).Hash
$h2 = (Get-FileHash $ep -Algorithm MD5).Hash
"MD5 S3      : $h1"
"MD5 endpoint: $h2"
Check "archivo del endpoint == archivo descargado de S3" ($h1 -eq $h2)
$dim = Dimensiones $s3
$partes = $dim -split "x"
Check "dimensiones $dim (maximo 300x300)" ([int]$partes[0] -le 300 -and [int]$partes[1] -le 300)

"=== E. Solicitud y respuesta HTTP del detalle ==="
curl.exe -s -i "$Base/productos/$id"
""

"=== G. Duplicado y pendientes ==="
Check "RDS: TEC-001 sigue una sola vez" ((Sql "SELECT count(*) FROM productos WHERE codigo='TEC-001'") -eq "1")
Check "RDS: 0 productos PENDIENTE (nada incompleto)" ((Sql "SELECT count(*) FROM productos WHERE estado='PENDIENTE'") -eq "0")

"=== H. Conteos: catalogo frente a RDS, DynamoDB y S3 ==="
'{":e":{"S":"LISTA"}}' | Set-Content -Encoding ascii evidencias\E5\_vals.json
$nRds = [int](Sql "SELECT count(*) FROM productos WHERE estado='PUBLICADO'")
$nDyn = [int]((aws dynamodb scan --table-name productos_atributos --filter-expression "estado_procesamiento = :e" --expression-attribute-values file://evidencias/E5/_vals.json --select COUNT --query Count --output text) -join "")
$nOri = [int]((aws s3api list-objects-v2 --bucket lomax-originales --prefix originales/ --query "length(Contents)" --output text) -join "")
$nMin = [int]((aws s3api list-objects-v2 --bucket lomax-miniaturas --prefix miniaturas/ --query "length(Contents)" --output text) -join "")
$r = Api GET "/productos"
$nApi = @(Lista $r.Json).Count
"RDS PUBLICADO : $nRds"
"DynamoDB LISTA: $nDyn"
"S3 originales : $nOri"
"S3 miniaturas : $nMin"
"API /productos: $nApi"
Check "los cinco conteos coinciden" (($nRds -eq $nDyn) -and ($nDyn -eq $nOri) -and ($nOri -eq $nMin) -and ($nMin -eq $nApi))
Check "al menos 20 publicados ($nApi)" ($nApi -ge 20)

"RESULTADO: PASS=$($script:ok)  FAIL=$($script:fallos)"
Stop-Transcript | Out-Null

