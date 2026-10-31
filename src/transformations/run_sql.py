"""Run team SQL with explicit logical namespaces; dry runs never authenticate."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time

def statements(path):
    text=Path(path).read_text(encoding='utf-8')
    result=[];current=[];quote=None;line_comment=False;block=0;i=0
    while i<len(text):
        c=text[i];n=text[i+1] if i+1<len(text) else ''
        if line_comment:
            if c=='\n':line_comment=False;current.append('\n')
        elif block:
            if c=='/' and n=='*':block+=1;i+=1
            elif c=='*' and n=='/':block-=1;i+=1;current.append(' ')
        elif quote:
            current.append(c)
            if quote=='$$':
                if c=='$' and n=='$':current.append(n);i+=1;quote=None
            elif c=='\\' and n:
                current.append(n);i+=1
            elif c==quote:
                if n==quote:current.append(n);i+=1
                else:quote=None
        elif c=='$' and n=='$':quote='$$';current.extend(['$','$']);i+=1
        elif c in "'\"`":quote=c;current.append(c)
        elif c=='-' and n=='-':line_comment=True;i+=1
        elif c=='/' and n=='*':block=1;i+=1
        elif c==';':
            if ''.join(current).strip():result.append(''.join(current).strip())
            current=[]
        else:current.append(c)
        i+=1
    if quote or block:raise ValueError('Unterminated SQL quote/comment')
    if ''.join(current).strip():result.append(''.join(current).strip())
    return result

def render(sql,variables):
    for name,value in variables.items():
        if name in ('catalog','source_silver_schema','source_gold_schema','source','target'):
            if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*){0,2}',value):raise ValueError('Unsafe namespace: '+name)
        elif name=='generation_id':
            if not re.fullmatch(r'[A-Za-z0-9_-]{1,100}',value):raise ValueError('Unsafe generation ID')
        else:raise ValueError('Unknown SQL variable: '+name)
        sql=sql.replace('${'+name+'}',value)
    if re.search(r'\$\{[^}]+\}',sql):raise ValueError('Unresolved SQL variable; provide --var name=value')
    return sql

def api(method,path,body=None,profile=None):
    cmd=['databricks','api',method,path]
    if body is not None:cmd+=['--json',json.dumps(body)]
    if profile:cmd+=['--profile',profile]
    return json.loads(subprocess.run(cmd,capture_output=True,text=True,check=True,timeout=90).stdout)

def execute(sql,profile=None,timeout_s=1200):
    warehouse=os.environ.get('DATABRICKS_WAREHOUSE_ID')
    if not warehouse:raise ValueError('Set DATABRICKS_WAREHOUSE_ID for live SQL execution')
    deadline=time.monotonic()+timeout_s
    r=api('post','/api/2.0/sql/statements',{'warehouse_id':warehouse,'statement':sql,'wait_timeout':'50s','on_wait_timeout':'CONTINUE'},profile)
    while r['status']['state'] in ('PENDING','RUNNING'):
        if time.monotonic()>=deadline:raise TimeoutError('SQL execution deadline exceeded; inspect the remote statement before retrying')
        time.sleep(10)
        r=api('get','/api/2.0/sql/statements/'+r['statement_id'],profile=profile)
    if r['status']['state']!='SUCCEEDED':raise RuntimeError(r['status'].get('error',{}).get('message',r['status']['state']))
    return r.get('result',{}).get('data_array') or []

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('paths',nargs='+');parser.add_argument('--dry-run',action='store_true')
    parser.add_argument('--var',action='append',default=[]);parser.add_argument('--profile')
    args=parser.parse_args()
    variables={'catalog':'applebees_semantic'}
    for value in args.var:
        key,sep,item=value.partition('=')
        if not sep:raise ValueError('Use --var name=value')
        variables[key]=item
    tasks=[]
    for path in args.paths:
        for sql in statements(path):
            probe={**variables}
            if '${generation_id}' in sql:probe.setdefault('generation_id','DRY_RUN_GENERATION')
            render(sql,probe)
            tasks.append((path,sql))
    if any('${generation_id}' in sql for _,sql in tasks) and 'generation_id' not in variables:
        if args.dry_run:variables['generation_id']='DRY_RUN_GENERATION'
        else:
            namespace=variables.get('source_gold_schema')
            if not namespace:raise ValueError('Set source_gold_schema or generation_id')
            result=execute(f'SELECT generation_id FROM {namespace}.gold_publication WHERE slot=1',args.profile)
            if len(result)!=1:raise ValueError('Exactly one published generation required')
            variables['generation_id']=result[0][0]
    for index,(path,sql) in enumerate(tasks,1):
        prepared=render(sql,variables)
        if not args.dry_run:execute(prepared,args.profile)
        print(('DRY' if args.dry_run else 'OK'),path,index,' '.join(prepared.split())[:85])

if __name__=='__main__':main()
