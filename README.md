# Lambda Functions

Guía de iniciación a **AWS Lambda** y ejemplos desplegables con la AWS CLI.

## ¿Qué es Lambda?

Lambda es el servicio de cómputo *serverless* de AWS: subes tu código (una
función con un *handler*), AWS lo ejecuta bajo demanda en respuesta a un
evento (invocación directa, API Gateway, S3, EventBridge, SQS...) y solo
pagas por el tiempo de ejecución. No hay servidores que gestionar, parchear
ni escalar manualmente.

## Conceptos clave

| Concepto            | Descripción                                                                                     |
| -------------------- | ------------------------------------------------------------------------------------------------ |
| **Function**         | Unidad de despliegue: código + configuración (runtime, memoria, timeout, rol IAM...)             |
| **Handler**          | Función de entrada que Lambda invoca: `archivo.metodo` (p. ej. `lambda_function.lambda_handler`) |
| **Runtime**          | Entorno de ejecución: `python3.13`, `nodejs22.x`, `java21`, `go` (via `provided.al2023`), etc.    |
| **Execution role**   | Rol IAM que la función asume para acceder a otros servicios (logs, S3, DynamoDB...)               |
| **Trigger / evento** | Lo que dispara la invocación: API Gateway, S3, EventBridge, SQS, invocación directa (CLI/SDK)      |
| **Layer**            | Paquete de dependencias/librerías compartido entre funciones, separado del código                 |
| **Cold start**       | Latencia extra en la primera invocación (o tras inactividad) mientras se inicializa el entorno    |
| **Memoria / CPU**    | La CPU asignada es proporcional a la memoria configurada (128 MB – 10 240 MB)                     |
| **Timeout**          | Máximo 900 s (15 min) por invocación                                                              |
| **Concurrencia**     | Nº de invocaciones simultáneas; se puede reservar o limitar por función                            |

## Prerrequisitos

```bash
# AWS CLI configurado
aws configure

# Verificar identidad
aws sts get-caller-identity

# Comprobar versión (v2 recomendado)
aws --version
```

Permisos IAM mínimos para desplegar desde estos ejemplos: `lambda:*`,
`iam:CreateRole` / `iam:AttachRolePolicy` (solo la primera vez, para crear
el rol de ejecución) y `logs:*` (para consultar CloudWatch Logs).

## Ciclo de vida de una función (con AWS CLI)

```bash
# 1. Empaquetar el código
zip function.zip lambda_function.py

# 2. Crear el rol de ejecución (una sola vez)
aws iam create-role \
  --role-name lambda-basic-role \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'

aws iam attach-role-policy \
  --role-name lambda-basic-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# 3. Crear la función
aws lambda create-function \
  --function-name mi-funcion \
  --runtime python3.13 \
  --architectures arm64 \
  --handler lambda_function.lambda_handler \
  --role arn:aws:iam::<ACCOUNT_ID>:role/lambda-basic-role \
  --zip-file fileb://function.zip

# 4. Invocarla
aws lambda invoke --function-name mi-funcion --payload '{}' --cli-binary-format raw-in-base64-out out.json
cat out.json

# 5. Actualizar el código tras un cambio
zip function.zip lambda_function.py
aws lambda update-function-code --function-name mi-funcion --zip-file fileb://function.zip

# 6. Ver logs (CloudWatch Logs, grupo /aws/lambda/<function-name>)
aws logs tail /aws/lambda/mi-funcion --follow

# 7. Borrar la función
aws lambda delete-function --function-name mi-funcion
```

## Estructura del repo

```
lambda-functions/
├── scripts/            → deploy.sh / invoke.sh / undeploy.sh, comunes a todas las lambdas
│                          ver scripts/README.md
└── lambdas/
    └── hello-world/    → código + config.env de cada función
                           ver lambdas/hello-world/README.md
```

Los scripts de `scripts/` son genéricos: reciben la carpeta de la función
como argumento (`./scripts/deploy.sh lambdas/<nombre>`) y no hay que
tocarlos al añadir una función nueva — basta con crear
`lambdas/<nombre>/lambda_function.py` (y opcionalmente `config.env`,
`event.json`, `requirements.txt`). Detalle completo en
[`scripts/README.md`](scripts/README.md).

## Funciones incluidas

| Función                                              | Runtime     | Descripción                                       |
| ----------------------------------------------------- | ----------- | -------------------------------------------------- |
| [`lambdas/hello-world/`](lambdas/hello-world/README.md) | Python 3.13 | Función mínima — plantilla de partida |

```bash
./scripts/deploy.sh   lambdas/hello-world
./scripts/invoke.sh   lambdas/hello-world
./scripts/undeploy.sh lambdas/hello-world --with-role
```

## Runtimes soportados (activos)

`python3.13`, `python3.12`, `nodejs22.x`, `nodejs20.x`, `java21`, `java17`,
`dotnet8`, `ruby3.3`, `go` / cualquier lenguaje vía `provided.al2023`
(runtime personalizado, p. ej. Rust).

## Free tier

1 000 000 de invocaciones/mes y 400 000 GB-segundos de cómputo gratis, cada
mes, indefinidamente (no solo los primeros 12 meses).

## Buenas prácticas

- **Handler puro**: inicializa clientes SDK (boto3, etc.) *fuera* del
  handler para reutilizarlos entre invocaciones (evita reconexiones en
  cada llamada).
- **Timeout ajustado**: no dejes el timeout por defecto de 3 s si tu
  función hace llamadas de red; tampoco lo dispares a 900 s "por si acaso".
- **Menos permisos**: el rol de ejecución debe tener solo los permisos que
  la función necesita (principio de mínimo privilegio).
- **Variables de entorno** para configuración (no hardcodear ARNs, nombres
  de tabla, etc.).
- **Logs estructurados**: usa `json.dumps(...)` en los `print`/`logger`
  para poder consultarlos con CloudWatch Logs Insights.
- **Layers** para dependencias pesadas o compartidas entre varias
  funciones, en vez de empaquetarlas en cada `.zip`.
