. "$PSScriptRoot\env.ps1"
Set-Location "$PSScriptRoot\.."

docker run --rm -v "${PWD}/lambda:/w" python:3.12-slim sh -c "pip install -q --no-cache-dir --disable-pip-version-check --root-user-action=ignore --target /tmp/pkg pillow && python /w/build_zip.py"
if ($LASTEXITCODE -ne 0) { throw "fallo el empaquetado" }

aws lambda get-function --function-name miniaturas *> $null
if ($LASTEXITCODE -ne 0) {
  aws lambda create-function --function-name miniaturas --runtime python3.12 `
    --handler handler.lambda_handler --role arn:aws:iam::000000000000:role/lomax-lambda-role `
    --zip-file fileb://lambda/thumbnailer.zip --timeout 60 --memory-size 512 `
    --environment file://lambda/env.json | Out-Null
  "Funcion creada"
} else {
  aws lambda update-function-code --function-name miniaturas --zip-file fileb://lambda/thumbnailer.zip | Out-Null
  Start-Sleep -Seconds 3
  aws lambda update-function-configuration --function-name miniaturas --environment file://lambda/env.json | Out-Null
  "Funcion actualizada"
}
aws lambda get-function-configuration --function-name miniaturas --query "{Estado:State,Actualizacion:LastUpdateStatus,Runtime:Runtime,Bytes:CodeSize}" --output json
