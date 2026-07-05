# hello-world

Función Lambda mínima en Python. Recibe un `name` en el evento y devuelve
un saludo — sirve como plantilla de partida para nuevas funciones.

## Archivos

| Archivo               | Rol                                                        |
| ---------------------- | ------------------------------------------------------------ |
| `lambda_function.py`  | Código de la función (handler)                              |
| `event.json`          | Payload de prueba por defecto para `scripts/invoke.sh`      |
| `config.env`          | Defaults de despliegue (nombre, runtime, memoria, env vars…) |

Los scripts de despliegue (`deploy.sh`, `invoke.sh`, `undeploy.sh`) son
comunes a todas las lambdas del repo y viven en
[`../../scripts/`](../../scripts/README.md) — aquí solo está el código y la
configuración propios de esta función.

## Variables de entorno de la función

| Variable    | Default (en `config.env`) | Descripción                              |
| ------------ | --------------------------- | ------------------------------------------ |
| `GREETING`  | `Hello`                     | Palabra de saludo usada en la respuesta    |
| `LOG_LEVEL` | `INFO`                      | Nivel de logging                           |

## Uso rápido

Desde la raíz del repo:

```bash
./scripts/deploy.sh   lambdas/hello-world
./scripts/invoke.sh   lambdas/hello-world
./scripts/undeploy.sh lambdas/hello-world --with-role
```

Sobrescribir algún default puntualmente:

```bash
./scripts/deploy.sh lambdas/hello-world --memory-size 256 --env-vars "GREETING=Hola,LOG_LEVEL=DEBUG"
```

Ver logs:

```bash
aws logs tail /aws/lambda/lambda-hello-world --follow --region eu-west-1
```
