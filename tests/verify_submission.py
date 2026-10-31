"""Verify the public source/demo boundary; does not claim live cloud execution."""
import ast
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'src/transformations'))
from run_sql import statements,render

class Payload(HTMLParser):
    def __init__(self):super().__init__();self.active=False;self.parts=[]
    def handle_starttag(self,tag,attrs):
        if tag=='script' and dict(attrs).get('id')=='emd-data':self.active=True
    def handle_endtag(self,tag):
        if tag=='script':self.active=False
    def handle_data(self,data):
        if self.active:self.parts.append(data)

def verify():
    listed=subprocess.run(['git','ls-files','--cached','--others','--exclude-standard'],cwd=ROOT,capture_output=True,text=True,check=True).stdout.splitlines()
    files=[ROOT/p for p in set(listed) if (ROOT/p).is_file()]
    forbidden=[r'[aA]\d{8}@',r'\bdbc-[a-z0-9-]+',r'[A-Za-z]:[/\\]Users[/\\]',r'[?]k=[A-Za-z0-9_-]{16,}',r'completed model run\s+\d{10,}',r'fraud_model_dev_[A-Za-z0-9_]+']
    problems=[]
    for p in files:
        rel=p.relative_to(ROOT).as_posix()
        if p.suffix.lower() in ('.csv','.tsv','.parquet','.xlsx','.jsonl','.pem','.key') or p.name.startswith('.env'):
            problems.append('Forbidden public export/credential type: '+rel)
        if p.suffix.lower()=='.png':
            if not rel.startswith('docs/images/synthetic-'):problems.append('Unapproved image: '+rel)
            continue
        try:text=p.read_text(encoding='utf-8')
        except UnicodeDecodeError:problems.append('Unexpected binary: '+rel);continue
        if any(re.search(pattern,text) for pattern in forbidden):problems.append('Personal identifier/access-link pattern: '+rel)
        if p.suffix=='.py':
            try:ast.parse(text,filename=rel)
            except SyntaxError as error:problems.append(f'Python syntax: {rel}:{error.lineno}')
        if p.suffix=='.md':
            for target in re.findall(r'!?\[[^\]]*\]\(([^)]+)\)',text):
                if target.startswith(('https:','http:','#','mailto:')):continue
                path=target.split('#')[0].strip('<>')
                if path and not (p.parent/path).exists():problems.append('Broken document link: '+rel+' -> '+path)
    parser=Payload();parser.feed((ROOT/'demo/model-demo.html').read_text(encoding='utf-8'))
    data=json.loads(''.join(parser.parts))
    assert data['data_kind']=='synthetic' and data['seed']=='stark-overflow-public-demo-v1'
    assert {r[0] for r in data['employees']}==set(range(1,31))
    assert {r[1] for r in data['employees']}=={1,2,3} and len(data['grid'])==108
    for _,_,history in data['employees']:
        for r in history:
            assert 0<=r[0]<16 and 0<=r[1]<=r[2] and (r[3] is None or 0<=r[4]<=r[3]<=r[5]<=1)
    variables={'catalog':'demo','source_silver_schema':'source.silver','source_gold_schema':'source.gold',
      'generation_id':'synthetic-generation','source':'demo.gold.fraud_employee_day','target':'demo.gold.fraud_employee_week'}
    for folder in ('src/transformations/gold/semantic','src/transformations/gold'):
        for p in (ROOT/folder).glob('*.sql'):
            for statement in statements(p):render(statement,variables)
    for p in (ROOT/'resources/jobs').glob('*.yml'):
        for relative in re.findall(r'notebook_path:\s*(\S+)',p.read_text(encoding='utf-8')):
            assert (p.parent/relative).resolve().is_relative_to(ROOT) and (p.parent/relative).is_file()
    if problems:raise AssertionError('\n'.join(problems))
    result={'status':'passed','scope':'public source/demo portability and disclosure checks; not live cloud execution',
      'files_checked':len(files),'synthetic_employees':30,'scenarios':108,
      'checks':['public file boundary','no personal workspace/access-link patterns','Python syntax','local documentation links',
       'synthetic-only dashboard payload','scenario bounds','semantic SQL substitutions','Job notebook paths']}
    (ROOT/'evidence').mkdir(exist_ok=True)
    (ROOT/'evidence/verification.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps(result,indent=2))

if __name__=='__main__':verify()
