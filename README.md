# Lambda Functions

Funciones AWS Lambda en Python, una por carpeta en [`lambdas/`](lambdas/), probadas y desplegadas
con el reusable workflow de
[lamda-cicd-reusable-simplified](https://github.com/VanGoMu/lamda-cicd-reusable-simplified). No
hay scripts ni manifiestos: toda la configuración de cada función está en los `with:` de su job.

| Función | Qué hace |
|---|---|
| [`hello-world`](lambdas/hello-world/README.md) | saludo mínimo; plantilla de partida |

## Cómo se despliega

| Evento | Workflow | Resultado |
|---|---|---|
| pull request | [`ci.yml`](.github/workflows/ci.yml) | `ruff`, `pytest` y ZIP de cada función, sin AWS |
| push a `main` | [`deploy.yml`](.github/workflows/deploy.yml) | environment `dev`, despliegue directo |
| tag `v*` | `deploy.yml` | environment `prod`, canary del 10 % durante 5 minutos |
| manual | `deploy.yml` (`workflow_dispatch`) | el environment que se elija |

Cada función es un stack de CloudFormation `<nombre>-<entorno>` (`lfs-hello-world-prod`) con su
alias `live`. Una release a producción:

```bash
git tag v1.2.0 && git push origin v1.2.0
```

Volver a una release anterior es desplegar su tag otra vez; se publica como versión nueva y pasa
por el canary:

```bash
gh workflow run deploy.yml --ref v1.1.0 -f environment=prod
```

## Añadir una función

Copia una carpeta (`lambdas/hello-world` → `lambdas/<nueva>`) y un bloque de job en `ci.yml` y en
`deploy.yml`, cambiando `function-name` (empieza por `lfs-`), `source-dir`, `tests-dir` y
`smoke-event`. Las dependencias van en `lambdas/<nueva>/requirements.txt`, junto a `src/`.

## Environments `dev` y `prod`

Cada uno necesita cuatro variables, que son los outputs del
[bootstrap](https://github.com/VanGoMu/lamda-cicd-reusable-simplified#bootstrap-una-vez-por-entorno)
desplegado con `NamePrefix=lfs-`: `AWS_REGION`, `AWS_ROLE_ARN`, `CFN_ROLE_ARN` y
`ARTIFACT_BUCKET`. En `prod`, limita los despliegues a los tags `v*` y añade *required reviewers*.

## Otras opciones de la llamada

Exponer la función detrás de un listener de ALB que ya existe:

```yaml
      exposure: alb
      alb-listener-arn: arn:aws:elasticloadbalancing:eu-west-1:123456789012:listener/app/web/50dc6c495c0c9188/f2f7dc8efc522ab2
      alb-path: /hello*
      alb-priority: 110
```

O detrás de una HTTP API (v2) que ya existe, con stage `$default` en auto-deploy:

```yaml
      exposure: api-gateway
      api-id: a1b2c3d4e5
      api-route: GET /hello
```

Reservar concurrencia (Lambda exige dejar 100 sin reservar en la cuenta, así que en una cuenta
nueva, con 10 en total, falla):

```yaml
      reserved-concurrency: 5
```
