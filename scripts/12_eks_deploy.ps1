param([string]$Tag = "f1e5c46")
. "$PSScriptRoot\env.ps1"
Set-Location "$PSScriptRoot\.."
$env:KUBECONFIG = "$HOME\.kube\lomax-k3s.yaml"
Start-Transcript -Path evidencias\E7\despliegue.txt -Force | Out-Null

$flociIp = ((docker inspect lomax-catalogo-floci-1 | ConvertFrom-Json).NetworkSettings.Networks.'lomax-catalogo_default'.IPAddress)
$clave = ((Get-Content .env | Where-Object { $_ -like "DB_PASSWORD=*" }) -replace "^DB_PASSWORD=","").Trim()
"Tag: $Tag   IP de floci: $flociIp   contexto: $(kubectl config current-context)"

kubectl create namespace lomax --dry-run=client -o yaml | kubectl apply -f -
kubectl -n lomax create secret generic lomax-secret --from-literal=DB_PASSWORD=$clave --dry-run=client -o yaml | kubectl apply -f -
(Get-Content k8s\lomax.yaml -Raw).Replace("__TAG__", $Tag).Replace("__FLOCI_IP__", $flociIp) | kubectl apply -f -

foreach ($d in "api","frontend","proxy") { kubectl -n lomax rollout status deploy/$d --timeout=180s }
kubectl -n lomax get pods -o wide
Stop-Transcript | Out-Null
