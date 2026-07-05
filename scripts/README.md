# scripts/

Herramientas de despliegue comunes a **todas** las funciones bajo
[`../lambdas/`](../lambdas/). Cada función solo aporta su código y, si
quiere personalizar los defaults, un `config.env` — los scripts no cambian.

```
deploy.sh    Crea el rol IAM + la función (o actualiza código/config si ya existe)
invoke.sh    Invoca la función con un payload JSON y muestra la respuesta
undeploy.sh  Borra la función (y, con --with-role, el rol IAM)
```

Los tres se invocan igual: `./scripts/<script>.sh <lambda-dir> [--flags]`,
por ejemplo:

```bash
./scripts/deploy.sh   lambdas/hello-world
./scripts/invoke.sh   lambdas/hello-world
./scripts/undeploy.sh lambdas/hello-world --with-role
```

Usa `--help` en cualquiera de ellos para ver todas las opciones.

## Precedencia de configuración

Para cada opción (región, nombre de función, memoria, variables de
entorno...) se resuelve en este orden, de menor a mayor prioridad:

1. **Default del script** (razonable para casos simples: `eu-west-1`,
   `python3.13`, `arm64`, 128 MB, timeout 10s...)
2. **`<lambda-dir>/config.env`** — defaults propios de esa función
3. **Flag `--clave valor`** en la línea de comandos — máxima prioridad,
   para overrides puntuales sin tocar `config.env`

`FUNCTION_NAME` por defecto es el nombre del directorio de la lambda
(`lambdas/mi-funcion` → `mi-funcion`), y `ROLE_NAME` por defecto es
`<function-name>-role` — así cada función nueva tiene un rol propio salvo
que se indique lo contrario.

## `config.env` (opcional, por función)

Fichero de shell con asignaciones `VARIABLE=valor` que se cargan con
`source` antes de aplicar los flags. Todas las claves son opcionales:

```bash
FUNCTION_NAME=mi-funcion
RUNTIME=python3.13
ARCHITECTURE=arm64
HANDLER=lambda_function.lambda_handler
MEMORY_SIZE=128
TIMEOUT=10
ROLE_NAME=mi-funcion-role
LAMBDA_ENV_VARS="CLAVE1=valor1,CLAVE2=valor2"
```

`LAMBDA_ENV_VARS` se traduce directamente al `--environment
Variables={...}` de la AWS CLI, tanto si viene de `config.env` como del
flag `--env-vars`.

## Empaquetado

`deploy.sh` copia a un directorio temporal todo el contenido de
`<lambda-dir>` **excepto** `config.env`, `README.md`, `event.json` y
`requirements.txt` (código y otros assets que la función necesite en
tiempo de ejecución sí se incluyen). Si existe `requirements.txt`, sus
dependencias se instalan con `pip3 install --target` en ese mismo
directorio antes de comprimirlo — útil para funciones con dependencias
(p. ej. `requests`, `pydantic`). Para dependencias con extensiones nativas
que deban compilarse para Amazon Linux, empaqueta con Docker o una Lambda
layer en vez de confiar en este mecanismo.

## Añadir una nueva función

```bash
mkdir lambdas/mi-funcion
# crea lambdas/mi-funcion/lambda_function.py con un lambda_handler(event, context)
# opcional: event.json, config.env, requirements.txt

./scripts/deploy.sh lambdas/mi-funcion
```

No hace falta tocar nada en `scripts/` — son genéricos para cualquier
función que siga esta estructura de carpetas.
