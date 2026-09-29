. "$PSScriptRoot\env.ps1"
Set-Location "$PSScriptRoot\.."
. "$PSScriptRoot\lib_api.ps1"
Start-Transcript -Path evidencias\E4\reporte_e4.txt -Force | Out-Null
Add-Type -AssemblyName System.Drawing

function Sql($Consulta) { ((psql -t -A -c $Consulta) -join "").Trim() }
function Dyn($Id, $Ruta) {
  ((aws dynamodb get-item --table-name productos_atributos --key "producto_id={N=$Id}" --query $Ruta --output text 2>$null) -join "").Trim()
}
function S3Existe($Bucket, $Clave) { aws s3api head-object --bucket $Bucket --key $Clave *> $null; return ($LASTEXITCODE -eq 0) }
function Dimensiones($Ruta) {
  $im = [System.Drawing.Image]::FromFile((Resolve-Path $Ruta).Path)
  $d = "$($im.Width)x$($im.Height)"; $im.Dispose(); $d
}
function ApiFalla($Extra, $Puerto) {
  $clave = ((Get-Content .env | Where-Object { $_ -like "DB_PASSWORD=*" }) -replace "^DB_PASSWORD=","").Trim()
  docker rm -f lomax-api-falla *> $null
  $opcDocker = @("run","-d","--name","lomax-api-falla","--network","lomax-catalogo_default","-p","${Puerto}:8000",
    "-e","AWS_ENDPOINT_URL=http://floci:4566","-e","AWS_DEFAULT_REGION=us-east-1",
    "-e","AWS_ACCESS_KEY_ID=test","-e","AWS_SECRET_ACCESS_KEY=test",
    "-e","DB_HOST=floci","-e","DB_PORT=7001","-e","DB_PASSWORD=$clave") + $Extra + @("lomax-backend:dev")
  docker @opcDocker | Out-Null
  for ($n = 0; $n -lt 20; $n++) {
    Start-Sleep -Seconds 1
    if ((& curl.exe -s -o NUL -w "%{http_code}" "http://localhost:$Puerto/health") -eq "200") { break }
  }
}

# archivos de prueba
$g = New-Object byte[] (6MB); $g[0] = 0xFF; $g[1] = 0xD8; $g[2] = 0xFF
[IO.File]::WriteAllBytes((Join-Path $PWD "pruebas\grande.jpg"), $g)
$k = New-Object byte[] 200; $k[0] = 0xFF; $k[1] = 0xD8; $k[2] = 0xFF
[IO.File]::WriteAllBytes((Join-Path $PWD "pruebas\corrupta.jpg"), $k)

$cod = "TST-" + (Get-Date -Format "HHmmss")
$modelo = @{ codigo = $cod; nombre = "Teclado de Prueba API"; descripcion = "Producto de prueba E4"
             precio = 19.99; categoria_id = 1; atributos = @{ conexion = "USB"; distribucion = "ES" } }

"=== A. GET /categorias ==="
$r = Api GET "/categorias"
Check "200 y 3 categorias" ($r.Status -eq 200 -and (Lista $r.Json).Count -eq 3) $r.Texto
Check "coincide con RDS" ((Lista $r.Json).Count -eq [int](Sql "SELECT count(*) FROM categorias"))

"=== B. Entradas invalidas: no deben dejar registros ==="
$n0 = [int](Sql "SELECT count(*) FROM productos")
$caso = $modelo.Clone(); $caso.codigo = "TEC-001"
$r = Api POST "/productos" $caso;  Check "codigo duplicado -> 409" ($r.Status -eq 409) $r.Texto
$caso = $modelo.Clone(); $caso.codigo = "TST-INV"; $caso.precio = -5
$r = Api POST "/productos" $caso;  Check "precio negativo -> 400" ($r.Status -eq 400) $r.Texto
$caso = $modelo.Clone(); $caso.codigo = "TST-INV"; $caso.categoria_id = 99
$r = Api POST "/productos" $caso;  Check "categoria inexistente -> 400" ($r.Status -eq 400) $r.Texto
$caso = $modelo.Clone(); $caso.codigo = "TST-INV"; $caso.atributos = @{ conexion = "USB" }
$r = Api POST "/productos" $caso;  Check "atributos incompletos -> 400" ($r.Status -eq 400) $r.Texto
$caso = $modelo.Clone(); $caso.codigo = "TST-INV"; $caso.nombre = ""
$r = Api POST "/productos" $caso;  Check "nombre vacio -> 400" ($r.Status -eq 400) $r.Texto
$r = Api POST "/productos" @{};    Check "cuerpo sin campos -> 400" ($r.Status -eq 400) $r.Texto
$n1 = [int](Sql "SELECT count(*) FROM productos")
Check "RDS sin registros parciales ($n0 -> $n1)" ($n1 -eq $n0)
Check "no existe TST-INV en RDS" ((Sql "SELECT count(*) FROM productos WHERE codigo='TST-INV'") -eq "0")

"=== C. POST /productos valido ==="
$r = Api POST "/productos" $modelo
Check "201 y PENDIENTE" ($r.Status -eq 201 -and $r.Json.estado -eq "PENDIENTE") $r.Texto
$id = $r.Json.producto_id
"producto_id creado: $id  codigo: $cod"
Check "RDS: fila PENDIENTE" ((Sql "SELECT estado||'|'||codigo FROM productos WHERE producto_id=$id") -eq "PENDIENTE|$cod")
Check "DynamoDB: atributo conexion=USB" ((Dyn $id "Item.atributos.M.conexion.S") -eq "USB")
Check "DynamoDB: estado PENDIENTE" ((Dyn $id "Item.estado_procesamiento.S") -eq "PENDIENTE")

"=== D. Consultas de un producto pendiente ==="
$r = Api GET "/productos/$id"
Check "detalle 200 y PENDIENTE" ($r.Status -eq 200 -and $r.Json.estado -eq "PENDIENTE") $r.Texto
$r = Api GET "/productos/999999";        Check "detalle inexistente -> 404" ($r.Status -eq 404)
$r = Api GET "/productos/$id/imagen";    Check "imagen no disponible -> 404" ($r.Status -eq 404)

"=== E. Reprocesar sin original ==="
$r = Api POST "/productos/$id/reprocesar";     Check "sin original -> 409" ($r.Status -eq 409) $r.Texto
$r = Api POST "/productos/999999/reprocesar";  Check "producto inexistente -> 404" ($r.Status -eq 404)

"=== F. Fallo de servicio dependiente: 502 (S3) y 503 (RDS), producto sigue PENDIENTE ==="
ApiFalla @("-e","BUCKET_ORIGINALES=bucket-inexistente") 8001
$r = Api POST "/productos/$id/imagen" -Archivo "fotos\1.jpg" -BaseUrl "http://localhost:8001"
"Respuesta 502: $($r.Texto)"
Check "S3 caido -> 502 con paso_fallido=s3" ($r.Status -eq 502 -and $r.Json.paso_fallido -eq "s3")
Check "RDS: sigue PENDIENTE" ((Sql "SELECT estado FROM productos WHERE producto_id=$id") -eq "PENDIENTE")
ApiFalla @("-e","DB_HOST=host-inexistente") 8001
$r = Api POST "/productos/$id/imagen" -Archivo "fotos\1.jpg" -BaseUrl "http://localhost:8001"
"Respuesta 503: $($r.Texto)"
Check "RDS caida -> 503 con paso_fallido=rds" ($r.Status -eq 503 -and $r.Json.paso_fallido -eq "rds")
docker rm -f lomax-api-falla | Out-Null

"=== G. Imagenes invalidas sobre el producto 3 ==="
$r = Api POST "/productos/3/imagen" -Archivo "pruebas\invalido.jpg"
Check "texto con extension .jpg -> 415" ($r.Status -eq 415) $r.Texto
$r = Api POST "/productos/3/imagen" -Archivo "pruebas\grande.jpg"
Check "6 MB -> 413" ($r.Status -eq 413) $r.Texto
$r = Api POST "/productos/3/imagen" -Archivo "pruebas\corrupta.jpg"
"Respuesta imagen corrupta: $($r.Texto)"
Check "firma JPEG pero corrupta -> 400" ($r.Status -eq 400 -and $r.Json.paso_fallido -eq "imagen") $r.Texto
Check "RDS: producto 3 PENDIENTE" ((Sql "SELECT estado FROM productos WHERE producto_id=3") -eq "PENDIENTE")
Check "DynamoDB: estado ERROR" ((Dyn 3 "Item.estado_procesamiento.S") -eq "ERROR")
Check "S3: sin miniatura para el 3" (-not (S3Existe "lomax-miniaturas" "miniaturas/3.jpg"))
$r = Api POST "/productos/999999/imagen" -Archivo "fotos\3.jpg"
Check "producto inexistente -> 404" ($r.Status -eq 404)

"=== H. Completar el registro pendiente 3 (sin crear otro producto) ==="
$total0 = [int](Sql "SELECT count(*) FROM productos")
$r = Api POST "/productos/3/imagen" -Archivo "fotos\3.jpg"
Check "200 y PUBLICADO" ($r.Status -eq 200 -and $r.Json.estado -eq "PUBLICADO") $r.Texto
Check "no se creo otro producto" ([int](Sql "SELECT count(*) FROM productos") -eq $total0)
Check "RDS: PUBLICADO" ((Sql "SELECT estado FROM productos WHERE producto_id=3") -eq "PUBLICADO")
Check "DynamoDB: LISTA y miniatura_key" ((Dyn 3 "Item.estado_procesamiento.S") -eq "LISTA" -and (Dyn 3 "Item.miniatura_key.S") -eq "miniaturas/3.jpg")
Check "S3: original y miniatura existen" ((S3Existe "lomax-originales" "originales/3.jpg") -and (S3Existe "lomax-miniaturas" "miniaturas/3.jpg"))

"=== I. GET /productos/3/imagen frente a S3 ==="
$img = "evidencias\E4\miniatura_3_endpoint.jpg"
$meta = & curl.exe -s -o $img -w "%{http_code} %{content_type}" "$Base/productos/3/imagen"
Check "200 y Content-Type image/jpeg ($meta)" ($meta -eq "200 image/jpeg")
aws s3api get-object --bucket lomax-miniaturas --key miniaturas/3.jpg evidencias\E4\miniatura_3_s3.jpg | Out-Null
$h1 = (Get-FileHash $img -Algorithm MD5).Hash
$h2 = (Get-FileHash evidencias\E4\miniatura_3_s3.jpg -Algorithm MD5).Hash
"MD5 endpoint: $h1"; "MD5 S3      : $h2"
Check "archivo del endpoint == archivo descargado de S3" ($h1 -eq $h2)
$dim = Dimensiones $img
Check "dimensiones $dim (esperado 300x200)" ($dim -eq "300x200")

"=== J. Reprocesar no duplica objetos ==="
$antes = (aws s3api list-objects-v2 --bucket lomax-miniaturas --prefix "miniaturas/3" --query "Contents[].[Key,ETag]" --output text) -join "|"
$r = Api POST "/productos/3/reprocesar"
Check "reprocesar -> 200 PUBLICADO" ($r.Status -eq 200 -and $r.Json.estado -eq "PUBLICADO") $r.Texto
$despues = (aws s3api list-objects-v2 --bucket lomax-miniaturas --prefix "miniaturas/3" --query "Contents[].[Key,ETag]" --output text) -join "|"
Check "miniaturas identicas antes y despues" ($antes -eq $despues) "$antes // $despues"
Check "un solo original del producto 3" ((aws s3api list-objects-v2 --bucket lomax-originales --prefix "originales/3." --query "length(Contents)" --output text) -eq "1")

"=== K. GET /productos solo publicados ==="
$r = Api GET "/productos"
$lista = @(Lista $r.Json)
Check "200" ($r.Status -eq 200)
Check "cantidad == PUBLICADOS en RDS ($($lista.Count))" ($lista.Count -eq [int](Sql "SELECT count(*) FROM productos WHERE estado='PUBLICADO'"))
Check "el pendiente de prueba no aparece" (-not ($lista | Where-Object { $_.producto_id -eq $id }))
$p3 = $lista | Where-Object { $_.producto_id -eq 3 }
Check "producto 3 con atributos y miniatura" ($p3.atributos.conexion -eq "USB" -and $p3.miniatura_key -eq "miniaturas/3.jpg")

"=== Limpieza del producto de prueba ==="
Sql "DELETE FROM productos WHERE producto_id=$id" | Out-Null
aws dynamodb delete-item --table-name productos_atributos --key "producto_id={N=$id}"
Check "producto de prueba eliminado" ((Sql "SELECT count(*) FROM productos WHERE producto_id=$id") -eq "0")

"RESULTADO: PASS=$($script:ok)  FAIL=$($script:fallos)"
Stop-Transcript | Out-Null

