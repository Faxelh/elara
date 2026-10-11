"""Génère l'icône d'Elara (1024x1024, sans transparence) pendant la compilation."""
from PIL import Image, ImageDraw, ImageFilter

S = 1024
SORTIE = "Elara/Assets.xcassets/AppIcon.appiconset/icone.png"

a, b = (143, 102, 250), (56, 140, 250)
fond = Image.new("RGB", (S, S))
px = fond.load()
for y in range(S):
    for x in range(S):
        t = (x + y) / (2 * S)
        px[x, y] = tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

halo = Image.new("L", (S, S), 0)
ImageDraw.Draw(halo).ellipse((262, 262, 762, 762), fill=90)
halo = halo.filter(ImageFilter.GaussianBlur(120))
fond = Image.composite(Image.new("RGB", (S, S), (255, 255, 255)), fond, halo)

masque = Image.new("L", (S * 2, S * 2), 0)
ImageDraw.Draw(masque).polygon([(800, 600), (800, 1448), (1520, 1024)], fill=255)
masque = masque.filter(ImageFilter.GaussianBlur(14)).point(lambda v: 255 if v > 128 else 0)
masque = masque.resize((S, S), Image.LANCZOS)
fond.paste((255, 255, 255), mask=masque)

fond.save(SORTIE)
print("Icône générée :", SORTIE)
