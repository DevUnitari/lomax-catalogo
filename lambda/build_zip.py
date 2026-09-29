import os
import zipfile

SRC = "/tmp/pkg"
OUT = "/w/thumbnailer.zip"
if os.path.exists(OUT):
    os.remove(OUT)
with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
    for raiz, dirs, archivos in os.walk(SRC):
        dirs[:] = [d for d in dirs if d != "__pycache__"]
        for a in archivos:
            ruta = os.path.join(raiz, a)
            z.write(ruta, os.path.relpath(ruta, SRC))
    z.write("/w/thumbnail_handler.py", "handler.py")
print("zip listo, bytes:", os.path.getsize(OUT))
