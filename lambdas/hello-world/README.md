# hello-world

Saluda al `name` del evento (`{"name": "AWS"}`) con el `GREETING` de sus variables de entorno y
dice qué versión publicada respondió. Código en [`src/app.py`](src/app.py) (handler
`app.handler`), tests en [`tests/`](tests/) y evento del smoke test en [`event.json`](event.json).
Se despliega como `lfs-hello-world-<entorno>`: directo en `dev`, con canary del 10 % en `prod`.
