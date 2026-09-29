. "$PSScriptRoot\env.ps1"
$map = @{ 'Teclados'='TECLADO'; 'Monitores'='MONITOR'; 'Televisores'='TELEVISOR' }
$rds = psql -t -A -F "," -c "SELECT p.producto_id, c.nombre FROM productos p JOIN categorias c USING (categoria_id) ORDER BY 1;"
$dyn = (aws dynamodb scan --table-name productos_atributos --output json | ConvertFrom-Json).Items
$bad = 0
foreach ($line in $rds) {
  $id, $cat = $line -split ","
  $item = $dyn | Where-Object { $_.producto_id.N -eq $id }
  if (-not $item)                        { "FALTA en DynamoDB: $id"; $bad++ }
  elseif ($item.tipo.S -ne $map[$cat])   { "TIPO NO COINCIDE id=$id RDS=$cat Dynamo=$($item.tipo.S)"; $bad++ }
  else                                   { "OK id=$id  $cat -> $($item.tipo.S)" }
}
"Discrepancias: $bad  (RDS=$($rds.Count), Dynamo=$($dyn.Count))"
