$env:AWS_ENDPOINT_URL = "http://localhost:4566"
$env:AWS_DEFAULT_REGION = "us-east-1"
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"

function psql {
  docker run --rm --network lomax-catalogo_default `
    -e PGPASSWORD=postgres123 `
    -v "${PWD}/db:/db" `
    postgres:16 psql -h floci -p 7001 -U postgres -d postgres -v ON_ERROR_STOP=1 @args
}
