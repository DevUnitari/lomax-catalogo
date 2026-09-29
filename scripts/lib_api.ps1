$Base = "http://localhost:8000"
$script:ok = 0
$script:fallos = 0

function Api {
  param($Metodo, $Ruta, $Cuerpo = $null, $Archivo = $null, $BaseUrl = $Base)
  $salida = "evidencias\E4\_resp.txt"
  $opc = @("-s","-o",$salida,"-w","%{http_code}","-X",$Metodo,"$BaseUrl$Ruta")
  if ($null -ne $Cuerpo) {
    ($Cuerpo | ConvertTo-Json -Depth 6 -Compress) | Set-Content -Encoding ascii evidencias\E4\_body.json
    $opc += @("-H","Content-Type: application/json","--data-binary","@evidencias\E4\_body.json")
  }
  if ($Archivo) { $opc += @("-F","archivo=@$Archivo") }
  $codigo = [int](& curl.exe @opc)
  $texto = Get-Content $salida -Raw
  $datos = $null
  try { $datos = $texto | ConvertFrom-Json } catch {}
  [pscustomobject]@{ Status = $codigo; Texto = $texto; Json = $datos }
}

function Check($Nombre, $Condicion, $Detalle = "") {
  if ($Condicion) { $script:ok++; "  [PASS] $Nombre" }
  else { $script:fallos++; "  [FAIL] $Nombre  $Detalle" }
}

function Lista($x) {
  if ($null -eq $x) { return @() }
  $l = @($x)
  if ($l.Count -eq 1 -and $l[0] -is [System.Array]) { $l = $l[0] }
  return $l
}
