from PIL import Image, ImageDraw
def make(path, size, color, fmt):
    im = Image.new("RGB", size, color)
    d = ImageDraw.Draw(im)
    for i in range(0, size[0], 100):
        d.line([(i,0),(i,size[1])], fill=(255,255,255), width=3)
    d.text((20,20), f"{size[0]}x{size[1]}", fill=(255,255,255))
    im.save(path, fmt)
make("/p/original_1200x800.jpg", (1200,800), (30,90,160), "JPEG")
make("/p/original_800x800.png",  (800,800),  (160,60,60), "PNG")
open("/p/invalido.jpg","w").write("esto no es una imagen")
