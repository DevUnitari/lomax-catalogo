# Lomax SA - Catalogo de productos tecnologicos sobre FLOCI

Plataforma que registra productos, muestra el catalogo y consulta el detalle. Corre sobre FLOCI (emulador local de AWS): RDS, DynamoDB, S3, Lambda, ECR y EKS. Alcance: solo registrar, listar y ver detalle.

## Arquitectura

    Usuario -> proxy nginx (:8080) -> frontend (nginx, HTML/JS estatico)
                                   -> /api -> API FastAPI (:8000)
    API -> FLOCI (:4566): RDS PostgreSQL (:7001), DynamoDB, S3 (2 buckets), Lambda
    Imagenes propias (frontend, backend, proxy) -> ECR de FLOCI -> EKS (k3s dentro de FLOCI)

Diagrama: docs/arquitectura.png (ver estado en la tabla de evidencias).

Recorrido de un producto:
1. POST /productos crea la fila en RDS como PENDIENTE y los atributos en DynamoDB.
2. POST /productos/{id}/imagen guarda el original en S3 e invoca Lambda de forma sincrona.
3. Lambda genera la miniatura (maximo 300x300, proporcional) y actualiza DynamoDB.
4. La API verifica atributos y miniatura y solo entonces pasa el producto a PUBLICADO.
5. Si algo falla, el producto sigue PENDIENTE y se puede reintentar con /reprocesar.

## Requisitos

Windows, PowerShell 5.1, Docker Desktop, AWS CLI v2 (perfil `floci`, credenciales test/test, region us-east-1), kubectl y git.

## Estructura

    docker-compose.yml       floci, api, frontend y proxy
    .env.example             variables (copiar a .env y poner DB_PASSWORD)
    db/                      esquema y datos iniciales de RDS
    lambda/                  funcion de miniaturas
    backend/                 API FastAPI y Dockerfile
    frontend/                vistas (HTML/JS) y theme.css
    proxy/                   nginx.conf y Dockerfile
    k8s/lomax.yaml           manifiestos de EKS
    scripts/                 scripts numerados por etapa
    evidencias/E1..E7        evidencias por etapa
    docs/                    tablero y documentacion

## Como reproducir

Los scripts son reejecutables. Se ejecutan desde la raiz del proyecto.

    copy .env.example .env          (editar DB_PASSWORD)
    docker compose up -d floci

| Etapa | Comandos |
|---|---|
| 2. RDS y DynamoDB | scripts\01_rds.ps1, 02_dynamodb.ps1, 03_verificar_ids.ps1 |
| 3. S3 y Lambda | scripts\04_buckets.ps1, 05_lambda.ps1, 06_probar_lambda.ps1 |
| 4. API | docker compose up -d --build ; scripts\07_probar_api.ps1 ; scripts\08_cargar_fotos.ps1 |
| 5. Frontend | docker compose up -d --build ; scripts\09_verificar_e5.ps1 ; abrir http://localhost:8080 |
| 6. ECR | scripts\10_ecr_push.ps1 ; scripts\11_ecr_pull_run.ps1 |
| 7. EKS | ver abajo ; scripts\12_eks_deploy.ps1 ; scripts\13_eks_escalado.ps1 ; scripts\14_eks_persistencia.ps1 |

Nota: no se ejecuto la reproduccion completa desde un entorno vacio; cada etapa se verifico en secuencia sobre el mismo entorno.

### Cluster EKS (comandos ejecutados a mano)

    $subs = ((aws ec2 describe-subnets --query "Subnets[0:2].SubnetId" --output text) -split "\s+") -join ","
    aws eks create-cluster --name lomax-cluster --role-arn arn:aws:iam::000000000000:role/eks-role --resources-vpc-config "subnetIds=$subs"
    aws eks describe-cluster --name lomax-cluster --query cluster.status --output text
    docker exec floci-eks-lomax-cluster cat /etc/rancher/k3s/k3s.yaml | Set-Content -Encoding ascii $HOME\.kube\lomax-k3s.yaml
    (Get-Content $HOME\.kube\lomax-k3s.yaml) -replace 'https://127.0.0.1:6443','https://127.0.0.1:6500' | Set-Content -Encoding ascii $HOME\.kube\lomax-k3s.yaml
    $env:KUBECONFIG = "$HOME\.kube\lomax-k3s.yaml"
    docker compose stop api frontend proxy
    Start-Process kubectl -ArgumentList "-n lomax port-forward svc/proxy 8080:80" -WindowStyle Hidden

El kubeconfig de `aws eks update-kubeconfig` no sirvio: el API de k3s rechazo el token, por eso se usa el kubeconfig propio de k3s. En el nodo se aplico un `registries.yaml` que apunta el registro ECR a http://floci:4566. Los Pods no resuelven el nombre `floci`, asi que el Deployment de la API usa `hostAliases` con la IP del contenedor floci (la inyecta scripts\12_eks_deploy.ps1).

## API

| Endpoint | Respuesta |
|---|---|
| GET /categorias | 200 |
| POST /productos | 201 (producto_id, PENDIENTE), 400, 409 codigo duplicado |
| POST /productos/{id}/imagen | 200 PUBLICADO, 404, 413 (mayor a 5 MB), 415 (no JPEG/PNG), 400 imagen corrupta, 502/503 |
| POST /productos/{id}/reprocesar | 200, 404, 409 sin original |
| GET /productos | 200, solo publicados, con atributos y miniatura |
| GET /productos/{id} | 200 o 404 |
| GET /productos/{id}/imagen | bytes de la miniatura o 404 |
| GET /health | 200 con identificador de instancia |

Los errores de servicios dependientes incluyen `paso_fallido` (s3, rds, dynamodb, lambda, imagen): 502 para S3, DynamoDB y Lambda; 503 para RDS. Cada respuesta lleva la cabecera `X-Instance-Id` (hostname del contenedor o nombre del Pod).

## Decisiones de diseno

- RDS guarda categorias y productos (integridad relacional: codigo unico, precio >= 0, categoria existente). DynamoDB guarda atributos variables por tipo de producto y datos de imagen. Comparten `producto_id` y no hay clave foranea entre servicios.
- Un producto solo es PUBLICADO con atributos y miniatura confirmados; un registro incompleto queda PENDIENTE.
- La clave de la miniatura depende solo del id (`miniaturas/<id>.jpg`), asi repetir la solicitud no crea objetos nuevos.
- Lambda no lanza excepcion por imagen invalida: responde ERROR y lo deja en DynamoDB. Los fallos de servicio si lanzan excepcion.
- El proxy es la unica entrada. En Compose y en EKS se usan las mismas imagenes de ECR, etiquetadas con el commit.
- La persistencia esta fuera de los Pods (RDS, DynamoDB y S3 de FLOCI, con volumen persistente).

## Limitaciones conocidas

- Si DynamoDB falla justo al registrar, el producto queda PENDIENTE sin atributos; la API responde 502 con `paso_fallido` y ningun endpoint completa esos atributos.
- Una imagen corrupta con firma JPEG valida sobrescribe el original anterior antes de que Lambda la rechace, y el producto vuelve a PENDIENTE.

## Evidencias

| Etapa | Carpeta | Contenido |
|---|---|---|
| E1 Diagrama | docs/ | PENDIENTE |
| E2 RDS y DynamoDB | evidencias/E2 | restricciones, get-item, persistencia tras reinicio |
| E3 S3 y Lambda | evidencias/E3 | invocaciones, miniatura 300x200, idempotencia, archivo invalido |
| E4 API | evidencias/E4 | reporte de pruebas de todos los endpoints |
| E5 Frontend | evidencias/E5 | reporte de verificacion (capturas: PENDIENTE) |
| E6 ECR | evidencias/E6 | push, describe-images, pull y digests |
| E7 EKS | evidencias/E7 | despliegue, escalado a 3 replicas, reemplazo de Pod, persistencia |

## Equipo

| Integrante | Cuenta de GitHub | Rol principal |
|---|---|---|
| REEMPLAZAR_NOMBRE_1 | REEMPLAZAR_CUENTA_1 | REEMPLAZAR_ROL_1 |

## Tablero

Tareas y responsables por etapa: docs/tablero.md. Tablero en GitHub Projects: REEMPLAZAR_ENLACE_TABLERO
