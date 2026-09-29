. "$PSScriptRoot\env.ps1"
Set-Location "$PSScriptRoot\.."
Start-Transcript -Path evidencias\E3\pruebas_lambda.txt -Force | Out-Null
Add-Type -AssemblyName System.Drawing
$Orig = "lomax-originales"
$Mini = "lomax-miniaturas"

function Dimensiones($Ruta) {
  $img = [System.Drawing.Image]::FromFile((Resolve-Path $Ruta).Path)
  $r = "$($img.Width)x$($img.Height)"
  $img.Dispose()
  $r
}
function Invocar($Producto, $Clave) {
  $json = @{ producto_id = $Producto; bucket = $Orig; key = $Clave } | ConvertTo-Json -Compress
  Set-Content -Encoding ascii lambda\_payload.json $json
  $salida = "evidencias\E3\invoke_$Producto.json"
  $meta = aws lambda invoke --function-name miniaturas --payload fileb://lambda/_payload.json --cli-read-timeout 300 --output json $salida | ConvertFrom-Json
  "producto $Producto -> StatusCode=$($meta.StatusCode) FunctionError=[$($meta.FunctionError)]"
  Get-Content $salida
}
function ListarMiniaturas {
  aws s3api list-objects-v2 --bucket $Mini --prefix miniaturas/ --query "Contents[].[Key,Size,ETag]" --output text
}

"=== 1. Subir originales ==="
aws s3api put-object --bucket $Orig --key originales/1.jpg --body pruebas\original_1200x800.jpg --content-type image/jpeg | Out-Null
aws s3api put-object --bucket $Orig --key originales/2.png --body pruebas\original_800x800.png --content-type image/png | Out-Null
aws s3api put-object --bucket $Orig --key originales/3.jpg --body pruebas\invalido.jpg --content-type image/jpeg | Out-Null

"=== 2. Invocar la funcion ==="
Invocar 1 "originales/1.jpg"
Invocar 2 "originales/2.png"
Invocar 3 "originales/3.jpg"

"=== 3. Listado de buckets ==="
aws s3api list-objects-v2 --bucket $Orig --prefix originales/ --query "Contents[].[Key,Size]" --output text
ListarMiniaturas

"=== 4. Descarga y dimensiones ==="
aws s3api get-object --bucket $Mini --key miniaturas/1.jpg evidencias\E3\miniatura_1.jpg | Out-Null
aws s3api get-object --bucket $Mini --key miniaturas/2.jpg evidencias\E3\miniatura_2.jpg | Out-Null
Copy-Item pruebas\original_1200x800.jpg evidencias\E3\original_1.jpg -Force
"original 1    : $(Dimensiones evidencias\E3\original_1.jpg)   (esperado 1200x800)"
"miniatura 1   : $(Dimensiones evidencias\E3\miniatura_1.jpg)   (esperado 300x200)"
"miniatura 2   : $(Dimensiones evidencias\E3\miniatura_2.jpg)   (esperado 300x300)"

"=== 5. Referencias en DynamoDB ==="
aws dynamodb get-item --table-name productos_atributos --key "producto_id={N=1}" --output json
aws dynamodb get-item --table-name productos_atributos --key "producto_id={N=3}" --output json

"=== 6. Repetir invocacion del producto 1 (idempotencia) ==="
$antes = (ListarMiniaturas) -join " | "
Invocar 1 "originales/1.jpg"
$despues = (ListarMiniaturas) -join " | "
"antes  : $antes"
"despues: $despues"
if ($antes -eq $despues) { "IDEMPOTENTE: SI (misma clave, mismo contenido, sin objetos extra)" } else { "IDEMPOTENTE: NO" }

"=== 7. Archivo invalido: no existe miniatura para el producto 3 ==="
aws s3api head-object --bucket $Mini --key miniaturas/3.jpg 2>&1 | ForEach-Object { "$_" }

Stop-Transcript | Out-Null
