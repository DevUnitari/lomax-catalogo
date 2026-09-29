from PIL import Image, ImageDraw, ImageFont

PRODUCTOS = [
 (1,"TEC-001","Teclado Mecanico Redragon Kumara"),(2,"TEC-002","Teclado Logitech K380"),
 (3,"TEC-003","Teclado Corsair K70"),(4,"TEC-004","Teclado Razer BlackWidow"),
 (5,"TEC-005","Teclado HP 150"),(6,"TEC-006","Teclado Keychron K2"),
 (7,"TEC-007","Teclado Microsoft Ergonomic"),(8,"MON-001","Monitor Samsung 24 Full HD"),
 (9,"MON-002","Monitor LG UltraGear 27"),(10,"MON-003","Monitor Dell P2422H"),
 (11,"MON-004","Monitor AOC 32 QHD"),(12,"MON-005","Monitor ASUS ProArt 27"),
 (13,"MON-006","Monitor Acer 22 HD"),(14,"MON-007","Monitor BenQ 27 2K"),
 (15,"TV-001","Televisor Samsung 43 4K"),(16,"TV-002","Televisor LG 50 4K"),
 (17,"TV-003","Televisor Sony 55 4K"),(18,"TV-004","Televisor TCL 32 HD"),
 (19,"TV-005","Televisor Hisense 65 4K"),(20,"TV-006","Televisor Philips 43 FHD"),
]
PNG = {6, 12, 18}
FONDOS = {"TEC": (38, 70, 120), "MON": (30, 100, 90), "TV": (110, 55, 95)}
W, H = 1200, 800

def fuente(t): return ImageFont.load_default(size=t)

def dibujo(d, pref):
    blanco = (235, 240, 245)
    if pref == "TEC":
        for fila in range(4):
            for col in range(11):
                x, y = 150 + col * 82, 250 + fila * 82
                d.rounded_rectangle([x, y, x + 70, y + 70], 8, fill=blanco)
        d.rounded_rectangle([300, 590, 900, 660], 8, fill=blanco)
    elif pref == "MON":
        d.rounded_rectangle([250, 170, 950, 560], 16, outline=blanco, width=14)
        d.rectangle([560, 560, 640, 640], fill=blanco)
        d.rounded_rectangle([450, 640, 750, 665], 10, fill=blanco)
    else:
        d.rounded_rectangle([150, 190, 1050, 610], 12, outline=blanco, width=14)
        d.rectangle([200, 240, 1000, 560], fill=(20, 20, 30))
        d.polygon([(300, 610), (340, 610), (300, 660)], fill=blanco)
        d.polygon([(860, 610), (900, 610), (900, 660)], fill=blanco)

for pid, codigo, nombre in PRODUCTOS:
    pref = codigo.split("-")[0]
    base = FONDOS[pref]
    im = Image.new("RGB", (W, H), base)
    d = ImageDraw.Draw(im)
    for y in range(H):
        f = y / H
        d.line([(0, y), (W, y)], fill=tuple(int(c * (1 - 0.35 * f)) for c in base))
    dibujo(d, pref)
    d.text((60, 40), codigo, font=fuente(64), fill=(255, 255, 255))
    d.text((60, 700), nombre, font=fuente(48), fill=(255, 255, 255))
    if pid in PNG:
        im.save(f"/f/{pid}.png", "PNG")
    else:
        im.save(f"/f/{pid}.jpg", "JPEG", quality=88)
print("generadas:", len(PRODUCTOS))
