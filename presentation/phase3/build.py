"""Builds dist/index.html: template.html + data.json + redes.json + GSAP + fonts + logos, all inlined (one file, deployable as-is).
python export_data.py   # refresh data.json from Databricks (read-only); redes.json comes from the Bayesian networks notebook
python build.py
"""
import base64, json
from pathlib import Path

HERE = Path(__file__).parent
b64 = lambda p: base64.b64encode(Path(p).read_bytes()).decode()
for f in ('data.json', 'redes.json'):
    if not (HERE / f).exists():
        raise SystemExit(f'{f} is missing: see README.md (it is generated from Databricks and never committed)')
data = json.loads((HERE / 'data.json').read_text(encoding='utf-8'))
data['redes'] = json.loads((HERE / 'redes.json').read_text(encoding='utf-8'))
html = (HERE / 'template.html').read_text(encoding='utf-8')
fonts = {'Fraunces': [('fraunces-latin-600-normal', 600, 'normal'), ('fraunces-latin-700-normal', 700, 'normal'), ('fraunces-latin-400-italic', 400, 'italic')],
         'Nunito': [('nunito-latin-400-normal', 400, 'normal'), ('nunito-latin-700-normal', 700, 'normal'), ('nunito-latin-800-normal', 800, 'normal')],
         'Caveat': [('caveat-latin-700-normal', 700, 'normal')]}
css = ''.join(f"@font-face{{font-family:'{fam}';src:url(data:font/woff2;base64,{b64(HERE / 'assets/fonts' / (f + '.woff2'))}) format('woff2');font-weight:{w};font-style:{s};font-display:block}}"
              for fam, lst in fonts.items() for f, w, s in lst)
html = html.replace('/*__FONTS__*/', css)
html = html.replace('/*__GSAP__*/', (HERE / 'assets/gsap.min.js').read_text(encoding='utf-8'))
html = html.replace('/*__DATA__*/null', json.dumps(data, ensure_ascii=False))
for k, p in {'sun': 'sun_holdings.png', 'dbx': 'databricks.png', 'tec': 'tec.png'}.items():
    html = html.replace(f'__LOGO_{k}__', 'data:image/png;base64,' + b64(HERE / 'assets/logos' / p))
(HERE / 'dist').mkdir(exist_ok=True)
(HERE / 'dist' / 'index.html').write_text(html, encoding='utf-8')
print('dist/index.html', round(len(html) / 1024), 'KB')
