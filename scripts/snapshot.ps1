. "$PSScriptRoot\env.ps1"
"--- RDS: conteo y hash de datos ---"
psql -t -A -c "SELECT count(*), md5(string_agg(producto_id||codigo||precio::text, ',' ORDER BY producto_id)) FROM productos;"
"--- DynamoDB: conteo ---"
aws dynamodb scan --table-name productos_atributos --select COUNT --query Count --output text
"--- get-item 1 y 8 ---"
aws dynamodb get-item --table-name productos_atributos --key "producto_id={N=1}" --output json
aws dynamodb get-item --table-name productos_atributos --key "producto_id={N=8}" --output json
