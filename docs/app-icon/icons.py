# Three original icon concepts, each in light / dark / tinted (iOS 18 appearances).
P = {
 'light':  dict(bg=('#EEF4FD', '#B7D2F7'), main='#2C66B8', main2='#4F86D3', green='#9FDBBE', pink='#F2B8CD', dot='#FFFFFF', paper='#FFFFFF', ink='#243247'),
 'dark':   dict(bg=None,                   main='#4C8CE2', main2='#7EB0F0', green='#5FCB92', pink='#E79BB8', dot='#0F141B', paper='#E7ECF3', ink='#0F141B'),
 'tinted': dict(bg=('#000000', '#000000'), main='#FFFFFF', main2='#D0D0D0', green='#9A9A9A', pink='#6E6E6E', dot='#000000', paper='#FFFFFF', ink='#000000'),
}
def frame(p, body):
    bg = ''
    if p['bg']:
        a, b = p['bg']
        bg = f'<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{a}"/><stop offset="1" stop-color="{b}"/></linearGradient></defs><rect width="1024" height="1024" fill="url(#g)"/>'
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">{bg}{body}</svg>'

def wallet(p):   # A: a wallet with two cards tucked in
    return frame(p, f'''
<rect x="250" y="250" width="470" height="250" rx="54" fill="{p['pink']}" transform="rotate(-13 485 375)"/>
<rect x="290" y="265" width="470" height="250" rx="54" fill="{p['green']}" transform="rotate(-4 525 390)"/>
<rect x="192" y="380" width="640" height="430" rx="104" fill="{p['main']}"/>
<rect x="592" y="508" width="240" height="174" rx="87" fill="{p['main2']}"/>
<circle cx="680" cy="595" r="30" fill="{p['dot']}"/>''')

def sprout(p):   # B: a coin with a sprouting leaf (savings that grow)
    return frame(p, f'''
<path d="M512 452 C512 380 512 330 512 290" stroke="{p['green']}" stroke-width="34" stroke-linecap="round" fill="none"/>
<path d="M512 330 C430 330 372 280 360 196 C446 196 506 246 512 330 Z" fill="{p['green']}"/>
<path d="M512 300 C590 300 650 252 664 168 C578 168 518 216 512 300 Z" fill="{p['pink']}"/>
<circle cx="512" cy="646" r="236" fill="{p['main']}"/>
<circle cx="512" cy="646" r="170" fill="none" stroke="{p['main2']}" stroke-width="26"/>
<rect x="474" y="560" width="76" height="172" rx="38" fill="{p['main2']}"/>''')

def bars(p):     # C: three rounded bars rising, the last one with a dot (plan → progress)
    return frame(p, f'''
<rect x="214" y="532" width="164" height="282" rx="82" fill="{p['pink']}"/>
<rect x="430" y="404" width="164" height="410" rx="82" fill="{p['green']}"/>
<rect x="646" y="270" width="164" height="544" rx="82" fill="{p['main']}"/>
<circle cx="728" cy="352" r="38" fill="{p['dot']}"/>''')

CONCEPTS = {'A-wallet': wallet, 'B-sprout': sprout, 'C-bars': bars}
if __name__ == '__main__':
    import os
    os.makedirs('svg', exist_ok=True)
    for name, fn in CONCEPTS.items():
        for mode, p in P.items():
            open(f'svg/{name}-{mode}.svg', 'w').write(fn(p))
    print('ok')
