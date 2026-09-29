. "$PSScriptRoot\env.ps1"
Set-Location "$PSScriptRoot\.."
. "$PSScriptRoot\lib_api.ps1"
$env:KUBECONFIG = "$HOME\.kube\lomax-k3s.yaml"
Start-Transcript -Path evidencias\E7\escalado_recuperacion.txt -Force | Out-Null

function Pods { kubectl -n lomax get pods -o custom-columns="POD:.metadata.name,IMAGEN:.spec.containers[0].image,UID:.metadata.uid,LISTO:.status.containerStatuses[0].ready" }
function UidsApi { (kubectl -n lomax get pods -l app=api -o jsonpath='{.items[*].metadata.uid}') -split "\s+" }
function ListosApi { [int](kubectl -n lomax get deploy api -o jsonpath='{.status.readyReplicas}') }

"=== 1. Pods e imagenes de ECR ==="
Pods
kubectl -n lomax get events --field-selector reason=Pulled -o custom-columns="POD:.involvedObject.name,MENSAJE:.message"
$imgs = (kubectl -n lomax get pods -o jsonpath='{.items[*].spec.containers[*].image}') -split "\s+"
Check "todas las imagenes salen de ECR" (@($imgs | Where-Object { $_ -notlike "000000000000.dkr.ecr.us-east-1.localhost:4566/*" }).Count -eq 0)
$r = Api GET "/productos"
Check "catalogo via proxy en EKS: $(@(Lista $r.Json).Count) productos" (@(Lista $r.Json).Count -ge 21)

"=== 2. Escalar api de 1 a 3 replicas ==="
kubectl -n lomax scale deploy/api --replicas=3
kubectl -n lomax rollout status deploy/api --timeout=180s
kubectl -n lomax get deploy api
Pods
Check "api con 3 replicas Ready" ((ListosApi) -eq 3)
$ids = 1..30 | ForEach-Object { (curl.exe -s -i "$Base/health" | Select-String -Pattern "^x-instance-id:").Line.Split(":")[1].Trim() }
"Solicitudes atendidas por cada Pod (30 solicitudes):"
$ids | Group-Object | ForEach-Object { "  $($_.Name) : $($_.Count)" }
Check "las solicitudes las atendieron 3 pods distintos" (@($ids | Sort-Object -Unique).Count -eq 3)
"Logs por Pod:"
kubectl -n lomax logs -l app=api --tail=2 --prefix

"=== 3. Eliminar un Pod ==="
$victima = (kubectl -n lomax get pods -l app=api -o jsonpath='{.items[0].metadata.name}')
$uidAntes = (kubectl -n lomax get pod $victima -o jsonpath='{.metadata.uid}')
"Pod eliminado: $victima   UID antes: $uidAntes"
kubectl -n lomax delete pod $victima
Start-Sleep -Seconds 5
for ($i = 0; $i -lt 40; $i++) { if ((ListosApi) -eq 3) { break }; Start-Sleep -Seconds 3 }
Pods
"UIDs de api despues: $((UidsApi) -join ', ')"
Check "el UID eliminado ya no existe (hay reemplazo)" ((UidsApi) -notcontains $uidAntes)
Check "replicas recuperadas: 3 Ready" ((ListosApi) -eq 3)
$r = Api GET "/productos"
Check "catalogo funciona tras el reemplazo ($(@(Lista $r.Json).Count) productos)" (@(Lista $r.Json).Count -ge 21)

"RESULTADO: PASS=$($script:ok)  FAIL=$($script:fallos)"
Stop-Transcript | Out-Null
