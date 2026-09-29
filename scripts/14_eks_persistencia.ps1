. "$PSScriptRoot\env.ps1"
Set-Location "$PSScriptRoot\.."
. "$PSScriptRoot\lib_api.ps1"
$env:KUBECONFIG = "$HOME\.kube\lomax-k3s.yaml"
Start-Transcript -Path evidencias\E7\producto_eks.txt -Force | Out-Null

function Verificar($id, $etapa) {
  "--- Verificacion $etapa (producto_id $id) ---"
  psql -c "SELECT producto_id, codigo, nombre, estado FROM productos WHERE producto_id=$id"
  Check "RDS ($etapa): PUBLICADO" ((Sql "SELECT estado FROM productos WHERE producto_id=$id") -eq "PUBLICADO")
  Check "DynamoDB ($etapa): LISTA" ((Dyn $id "Item.estado_procesamiento.S") -eq "LISTA")
  Check "DynamoDB ($etapa): atributo conexion=USB" ((Dyn $id "Item.atributos.M.conexion.S") -eq "USB")
  Check "S3 ($etapa): original y miniatura existen" ((S3Existe "lomax-originales" (Dyn $id "Item.imagen_original_key.S")) -and (S3Existe "lomax-miniaturas" "miniaturas/$id.jpg"))
  $s3 = "evidencias\E7\miniatura_$($id)_s3_$etapa.jpg"
  $ep = "evidencias\E7\miniatura_$($id)_endpoint_$etapa.jpg"
  aws s3api get-object --bucket lomax-miniaturas --key "miniaturas/$id.jpg" $s3 | Out-Null
  $meta = & curl.exe -s -o $ep -w "%{http_code} %{content_type}" "$Base/productos/$id/imagen"
  Check "endpoint ($etapa) 200 image/jpeg ($meta)" ($meta -eq "200 image/jpeg")
  Check "miniatura endpoint == S3 ($etapa)" ((Get-FileHash $s3 -Algorithm MD5).Hash -eq (Get-FileHash $ep -Algorithm MD5).Hash)
  $r = Api GET "/productos"
  $lista = @(Lista $r.Json)
  Check "catalogo ($etapa) incluye el producto $id" (@($lista | Where-Object { $_.producto_id -eq $id }).Count -eq 1)
  "productos en el catalogo ($etapa): $($lista.Count)"
}

$id = [int](Sql "SELECT producto_id FROM productos WHERE codigo='TEC-200'")
"Producto TEC-200 registrado desde la app en EKS: producto_id $id"
Check "TEC-200 existe" ($id -gt 0)

"=== A. Antes de recrear los Pods ==="
Verificar $id "antes"
"UIDs antes:"; kubectl -n lomax get pods -o custom-columns="POD:.metadata.name,UID:.metadata.uid"

"=== B. Recrear todos los Pods ==="
Get-Process kubectl -ErrorAction SilentlyContinue | Stop-Process -Force
kubectl -n lomax delete pods --all
foreach ($d in "api","frontend","proxy") { kubectl -n lomax rollout status deploy/$d --timeout=180s }
"UIDs despues:"; kubectl -n lomax get pods -o custom-columns="POD:.metadata.name,UID:.metadata.uid,LISTO:.status.containerStatuses[0].ready"
Start-Process kubectl -ArgumentList "-n lomax port-forward svc/proxy 8080:80" -WindowStyle Hidden
Start-Sleep -Seconds 6

"=== C. Despues de recrear los Pods ==="
Verificar $id "despues"

"RESULTADO: PASS=$($script:ok)  FAIL=$($script:fallos)"
Stop-Transcript | Out-Null
