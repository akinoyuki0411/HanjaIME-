"""Developer-only native typography icon export; Mac builds use the exported assets.
Usage: python3 scripts/make_icons.py GUREUM_CHECKOUT NotoSansCJKkr-Medium.otf
"""
import json,sys
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
repo,font_path=map(Path,sys.argv[1:3])
assets=Path(__file__).resolve().parent.parent/'Assets'; assets.mkdir(exist_ok=True)
font=TTFont(font_path); glyphs=font.getGlyphSet(); pen=SVGPathPen(glyphs)
glyphs[font.getBestCmap()[ord('漢')]].draw(pen)
svg='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">\n<rect x="72" y="72" width="880" height="880" rx="196" fill="#203c58"/>\n'
svg+='<path fill="#fff6e5" transform="translate(177 730) scale(.67 -.67)" d="'+pen.getCommands()+'"/>\n</svg>\n'
(assets/'HanjaIME.svg').write_text(svg)
def icon(size,menu=False,glyph='漢'):
 if menu:
  scale=8; width=round(size*22/18)
  image=Image.new('RGBA',(width*scale,size*scale)); draw=ImageDraw.Draw(image)
  draw.rounded_rectangle((scale,2*scale,(width-1)*scale,(size-2)*scale),
   radius=4*scale,fill='#eeeeee',outline='#727272',width=max(1,scale//2))
  face=ImageFont.truetype(str(font_path),round(size*.64*scale))
  box=draw.textbbox((0,0),glyph,font=face)
  draw.text(((width*scale-(box[2]-box[0]))/2-box[0],
   (size*scale-(box[3]-box[1]))/2-box[1]),glyph,font=face,fill='#202020')
  return image.resize((width,size),Image.Resampling.LANCZOS)
 n=max(1024,size*4); image=Image.new('RGBA',(n,n)); draw=ImageDraw.Draw(image)
 m=n*(.015 if menu else .07)
 draw.rounded_rectangle((m,m,n-m,n-m),radius=n*.19,fill='#203c58')
 face=ImageFont.truetype(str(font_path),int(n*(.91 if menu else .72)))
 box=draw.textbbox((0,0),glyph,font=face)
 draw.text(((n-(box[2]-box[0]))/2-box[0],(n-(box[3]-box[1]))/2-box[1]),glyph,font=face,fill='#fff6e5')
 return image.resize((size,size),Image.Resampling.LANCZOS)
cat=repo/'OSX/Assets.xcassets/AppIcon.appiconset'
for item in json.loads((cat/'Contents.json').read_text())['images']:
 size=int(item['size'].split('x')[0])*int(item['scale'][0]); icon(size).save(cat/item['filename'])
for suffix,size in [('',18),('@2x',36)]:
 icon(size,True).save(repo/'OSX/Icons'/('HanjaIME'+suffix+'.png'))
# Carbon, asset catalog, and older preferences windows can use different aliases.
for name in ['han','han2','han3','han390','han3final','hanroman','eng','qwerty']:
 cat=repo/'OSX/Assets.xcassets'/(name+'.imageset')
 for item in json.loads((cat/'Contents.json').read_text())['images']:
  if 'filename' in item:
   icon(18*int(item['scale'][0]),True,'A' if name in ['eng','qwerty'] else '漢').save(cat/item['filename'])
icon(256).save(assets/'HanjaIME-preview.png')
print('Exported 漢 app/menu icons, all asset aliases and editable vector outline.')
