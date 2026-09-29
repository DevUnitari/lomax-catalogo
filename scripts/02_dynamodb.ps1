. "$PSScriptRoot\env.ps1"
Set-Location "$PSScriptRoot\.."
$Tabla = "productos_atributos"

aws dynamodb describe-table --table-name $Tabla *> $null
if ($LASTEXITCODE -ne 0) {
  aws dynamodb create-table --table-name $Tabla `
    --attribute-definitions AttributeName=producto_id,AttributeType=N `
    --key-schema AttributeName=producto_id,KeyType=HASH `
    --billing-mode PAY_PER_REQUEST | Out-Null
  "Tabla creada"
} else { "Tabla ya existe" }

function Guardar($item) {
  $item | ConvertTo-Json -Depth 10 -Compress | Set-Content -Encoding ascii scripts\_item.json
  $out = aws dynamodb put-item --table-name $Tabla --item file://scripts/_item.json `
         --condition-expression "attribute_not_exists(producto_id)" 2>&1 | Out-String
  if ($LASTEXITCODE -eq 0) { "OK" }
  elseif ($out -match "ConditionalCheckFailed") { "ya existia" }
  else { throw $out }
}

# id, conexion, distribucion
$teclados = @(
  @(1,'USB','US'), @(2,'Bluetooth','US'), @(3,'USB','US'), @(4,'USB','US'),
  @(5,'USB','ES'), @(6,'Bluetooth','US'), @(7,'USB','ES')
)
# id, tipo, pulgadas, resolucion
$pantallas = @(
  @(8,'MONITOR',24,'1920x1080'),   @(9,'MONITOR',27,'2560x1440'),
  @(10,'MONITOR',24,'1920x1080'),  @(11,'MONITOR',32,'2560x1440'),
  @(12,'MONITOR',27,'3840x2160'),  @(13,'MONITOR',22,'1366x768'),
  @(14,'MONITOR',27,'2560x1440'),  @(15,'TELEVISOR',43,'3840x2160'),
  @(16,'TELEVISOR',50,'3840x2160'),@(17,'TELEVISOR',55,'3840x2160'),
  @(18,'TELEVISOR',32,'1366x768'), @(19,'TELEVISOR',65,'3840x2160'),
  @(20,'TELEVISOR',43,'1920x1080')
)

foreach ($teclado in $teclados) {
  Write-Host -NoNewline "producto $($teclado[0]): "
  Guardar @{
    producto_id = @{N="$($teclado[0])"}; tipo = @{S='TECLADO'}
    atributos = @{M=@{conexion=@{S=$teclado[1]}; distribucion=@{S=$teclado[2]}}}
    imagen_original_key = @{NULL=$true}; miniatura_key = @{NULL=$true}
    estado_procesamiento = @{S='PENDIENTE'}
  }
}
foreach ($pantalla in $pantallas) {
  Write-Host -NoNewline "producto $($pantalla[0]): "
  Guardar @{
    producto_id = @{N="$($pantalla[0])"}; tipo = @{S=$pantalla[1]}
    atributos = @{M=@{pulgadas=@{N="$($pantalla[2])"}; resolucion=@{S=$pantalla[3]}}}
    imagen_original_key = @{NULL=$true}; miniatura_key = @{NULL=$true}
    estado_procesamiento = @{S='PENDIENTE'}
  }
}
