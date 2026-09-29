import os, json, urllib.request

def lambda_handler(event, context):
    candidatos = []
    if os.environ.get("AWS_ENDPOINT_URL"):
        candidatos.append(os.environ["AWS_ENDPOINT_URL"])
    candidatos += ["http://floci:4566", "http://host.docker.internal:4566"]
    resultado = {}
    for url in candidatos:
        try:
            r = urllib.request.urlopen(url + "/", timeout=3)
            resultado[url] = f"HTTP {r.status}"
        except urllib.error.HTTPError as e:
            resultado[url] = f"HTTP {e.code} (alcanzable)"
        except Exception as e:
            resultado[url] = f"FALLA: {type(e).__name__}"
    env = {k: v for k, v in os.environ.items() if k.startswith("AWS_") and "SECRET" not in k and "TOKEN" not in k}
    return {"conectividad": resultado, "env": env, "event": event}
