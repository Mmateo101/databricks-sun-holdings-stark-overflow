(async function () {
  const root=document.getElementById('employee-model-dashboard');
  const el=id=>root.querySelector('#emd-'+id);
  try {
    if(!window.d3)throw new Error('The chart library could not load.');
    const data=JSON.parse(el('data').textContent),d3=window.d3;
    if(data.data_kind!=='synthetic')throw new Error('The public demo accepts synthetic data only.');
    const pct=x=>x==null?'Unavailable':(100*x).toFixed(1)+'%';
    const num=x=>new Intl.NumberFormat('en-US',{maximumFractionDigits:0}).format(x);
    const money=x=>new Intl.NumberFormat('en-US',{maximumFractionDigits:2}).format(x);
    const base=Date.UTC(2026,0,1),day=w=>new Date(base+w*7*86400000);
    const date=w=>d3.utcFormat('%b %d')(day(w));
    const status=['Training only','Activity evidence','Recorded-scope zero','Prior only: partial calendar','Prior only: attribution/amount coverage','Prior only: incomplete opportunity proxy'];
    const employees=data.employees.map(([id,location,history])=>({id,location,history,
      last:[...history].reverse().find(r=>r[7]===1||r[7]===2)}));
    const map=new Map(employees.map(e=>[String(e.id),e]));
    let state={restaurant:'all',employee:'3',base:.05,memory:1,odds:2,dispersion:1};
    let saved;try{saved=JSON.parse(localStorage.getItem('stark-demo-state')||'null');}catch{}
    if(saved?.dashboard==='employee-model-v1')state={...state,...saved};
    if(!map.has(String(state.employee)))state.employee=String(employees[0].id);
    let cohort=employees,ready=false,pending=false;
    const reduced=window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    function remember(){try{localStorage.setItem('stark-demo-state',JSON.stringify({dashboard:'employee-model-v1',...state}));}catch{}}
    const restaurants=[...new Set(employees.map(e=>e.location))].sort((a,b)=>a-b);
    for(const id of restaurants){const o=document.createElement('option');o.value=id;o.textContent='Restaurant '+id;el('restaurant').append(o);}
    if(state.restaurant!=='all'&&!restaurants.includes(Number(state.restaurant)))state.restaurant='all';
    function controls(){
      el('restaurant').value=state.restaurant;
      cohort=employees.filter(e=>state.restaurant==='all'||e.location===Number(state.restaurant));
      if(!cohort.some(e=>String(e.id)===String(state.employee)))state.employee=String(cohort[0].id);
      el('employee').replaceChildren(...cohort.map(e=>{const o=document.createElement('option');o.value=e.id;o.textContent=e.id+' · restaurant '+e.location;return o;}));
      el('employee').value=state.employee;
      for(const name of ['base','memory','odds','dispersion'])el(name).value=state[name];
    }
    function wrapLabel(node,value,width){
      node.text(null);const words=value.split(' '),lines=[];let current='';
      for(const word of words){const next=current?current+' '+word:word;
        node.text(next);if(node.node().getComputedTextLength()>width&&current){lines.push(current);current=word;}else current=next;
      }
      lines.push(current);node.text(null);
      lines.forEach((line,i)=>node.append('tspan').attr('x',node.attr('x')).attr('dy',i?14:0).text(line));
    }
    function frame(id,title,xlabel,ylabel,left=76,height=270){
      const div=el(id),width=div.getBoundingClientRect().width;
      if(width<100)return null;
      const margin={left,right:18,top:18,bottom:66};
      const w=width-margin.left-margin.right,h=height-margin.top-margin.bottom;
      const svg=d3.select(div).selectAll('svg').data([id]).join('svg').attr('viewBox',`0 0 ${width} ${height}`)
        .attr('width',width).attr('height',height).attr('role','img').attr('aria-label',title);
      svg.selectAll('title').data([title]).join('title').text(title);
      const group=svg.selectAll('g.plot').data([id]).join('g').attr('class','plot').attr('transform',`translate(${margin.left},${margin.top})`);
      group.selectAll('rect.frame').data([id]).join('rect').attr('class','frame').attr('data-chart-frame','')
        .attr('width',w).attr('height',h).attr('fill','none').attr('stroke','var(--border)').attr('stroke-width',1);
      const clip='emd-clip-'+id;
      svg.selectAll('defs').data([id]).join('defs').selectAll('clipPath').data([id]).join('clipPath').attr('id',clip)
        .selectAll('rect').data([id]).join('rect').attr('width',w).attr('height',h);
      const marks=group.selectAll('g.marks').data([id]).join('g').attr('class','marks').attr('clip-path',`url(#${clip})`);
      const xAxis=group.selectAll('g.xaxis').data([id]).join('g').attr('class','xaxis').attr('transform',`translate(0,${h})`);
      const yAxis=group.selectAll('g.yaxis').data([id]).join('g').attr('class','yaxis');
      const xl=svg.selectAll('text.xlabel').data([id]).join('text').attr('class','xlabel axis-title').attr('data-axis','x')
        .attr('x',margin.left+w/2).attr('y',height-31).attr('text-anchor','middle');
      wrapLabel(xl,xlabel,w+12);
      svg.selectAll('text.ylabel').data([id]).join('text').attr('class','ylabel axis-title').attr('data-axis','y')
        .attr('transform',`translate(16,${margin.top+h/2}) rotate(-90)`).attr('text-anchor','middle').text(ylabel);
      const duration=ready&&!reduced?220:0;
      function move(selection){return selection.interrupt().transition().duration(duration);}
      function axes(x,y,xf,yf,band=false){
        xAxis.call(d3.axisBottom(x).ticks(width<450?3:5).tickFormat(xf).tickSizeOuter(0));
        yAxis.call((band?d3.axisLeft(y):d3.axisLeft(y).ticks(4)).tickFormat(yf).tickSizeOuter(0));
        xAxis.selectAll('text').each(function(d,i,n){d3.select(this).attr('text-anchor',i===0?'start':i===n.length-1?'end':'middle');});
      }
      return {svg,group,marks,xAxis,yAxis,w,h,width,height,move,axes};
    }
    function nearestOverlay(chart,rows,x,label,click){
      chart.group.selectAll('rect.overlay').data([rows]).join('rect').attr('class','overlay').attr('data-chart-hit','')
        .attr('width',chart.w).attr('height',chart.h).attr('fill','transparent')
        .on('pointermove',function(event){if(!rows.length)return;const [mx]=d3.pointer(event,this);
          const index=d3.bisector(r=>r[0]).center(rows,+x.invert(mx));const row=rows[index];
          d3.select(this).attr('data-tooltip',label(row));
        }).on('click',function(event){if(!click||!rows.length)return;const [mx]=d3.pointer(event,this);click(rows[d3.bisector(r=>r[0]).center(rows,+x.invert(mx))]);});
    }
    function drawHistogram(){
      const rows=cohort.filter(e=>e.last),values=rows.map(e=>e.last[3]);
      const c=frame('histogram','Last informed employee reference probability distribution','Reference probability (%)','Employees');if(!c)return;
      const bins=d3.bin().domain([0,1]).thresholds(Array.from({length:19},(_,i)=>(i+1)/20))(values);
      const x=d3.scaleLinear().domain(d3.extent([0,1,...values])).range([3,c.w-3]);
      const y=d3.scaleLinear().domain([0,Math.max(1,d3.max(bins,b=>b.length))*1.1]).range([c.h-2,3]);
      c.axes(x,y,d3.format('.0%'),d3.format('~s'));
      const bars=c.marks.selectAll('rect.bar').data(bins,b=>b.x0).join('rect').attr('class','bar').attr('fill','var(--viz-series-1)')
        .attr('data-tooltip',b=>`${pct(b.x0)}–${pct(b.x1)}: ${num(b.length)} employees; latest informed week`);
      c.move(bars).attr('x',b=>x(b.x0)+1).attr('y',b=>y(b.length)).attr('width',b=>Math.max(1,x(b.x1)-x(b.x0)-2)).attr('height',b=>Math.max(0,y(0)-y(b.length)));
    }
    function drawScatter(){
      const rows=cohort.filter(e=>e.last);
      const c=frame('scatter','Employee reference output against assumption sensitivity width','Reference probability (%)','Sensitivity width (pp)');if(!c)return;
      const x=d3.scaleLinear().domain([0,1]).range([5,c.w-5]),y=d3.scaleLinear().domain([0,1]).range([c.h-5,5]);
      c.axes(x,y,d3.format('.0%'),v=>Math.round(v*100));
      const dots=c.marks.selectAll('circle.dot').data(rows,e=>e.id).join('circle').attr('class','dot')
        .attr('fill','var(--viz-series-1)').attr('opacity',e=>String(e.id)===String(state.employee)?1:.28);
      c.move(dots).attr('cx',e=>x(e.last[3])).attr('cy',e=>y(e.last[5]-e.last[4])).attr('r',e=>String(e.id)===String(state.employee)?5:2.7);
      const tree=d3.Delaunay.from(rows,e=>x(e.last[3]),e=>y(e.last[5]-e.last[4]));let closest=null;
      c.group.selectAll('rect.overlay').data([rows]).join('rect').attr('class','overlay').attr('data-chart-hit','')
        .attr('width',c.w).attr('height',c.h).attr('fill','transparent').on('pointermove',function(event){
          if(!rows.length)return;const [mx,my]=d3.pointer(event,this);closest=rows[tree.find(mx,my)];
          d3.select(this).attr('data-tooltip',`Employee ${closest.id} · restaurant ${closest.location}\n${date(closest.last[0])}: reference ${pct(closest.last[3])}\nSensitivity ${pct(closest.last[4])}–${pct(closest.last[5])}; click to inspect`);
        }).on('click',()=>{if(!closest)return;state.employee=String(closest.id);el('employee').value=state.employee;remember();renderAll();el('tab-person').click();});
    }
    function drawTimeline(e){
      const c=frame('timeline',`Employee ${e.id} weekly probability and assumption sensitivity`,'Week start · 2026','Assumed probability (%)',76,300);if(!c)return;
      const rows=e.history,first=rows[0][0],last=rows[rows.length-1][0];
      const full=d3.range(first,last+1).map(w=>rows.find(r=>r[0]===w)||[w,0,0,null,null,null,null,-1]);
      const x=d3.scaleLinear().domain(d3.extent(full,r=>r[0])).range([5,c.w-5]);
      const y=d3.scaleLinear().domain([0,1]).range([c.h-4,4]);
      const ticks=[...new Set(x.ticks(c.width<450?3:6).map(Math.round))];
      c.xAxis.call(d3.axisBottom(x).tickValues(ticks).tickFormat(date).tickSizeOuter(0));c.yAxis.call(d3.axisLeft(y).ticks(4).tickFormat(d3.format('.0%')).tickSizeOuter(0));
      c.xAxis.selectAll('text').attr('text-anchor',(d,i,n)=>i===0?'start':i===n.length-1?'end':'middle');
      const area=d3.area().defined(r=>r[3]!=null).x(r=>x(r[0])).y0(r=>y(r[4])).y1(r=>y(r[5]));
      const line=d3.line().defined(r=>r[3]!=null).x(r=>x(r[0])).y(r=>y(r[3]));
      c.marks.selectAll('path.band').data([full]).join('path').attr('class','band').attr('fill','var(--viz-series-1)').attr('opacity',.12).attr('d',area);
      c.marks.selectAll('path.estimate').data([full]).join('path').attr('class','estimate').attr('fill','none').attr('stroke','var(--viz-series-1)').attr('stroke-width',1.7).attr('d',line);
      const points=c.marks.selectAll('path.point').data(rows.filter(r=>r[3]!=null),r=>r[0]).join('path').attr('class','point')
        .attr('fill',r=>r[7]>=3?'var(--viz-series-2)':'var(--viz-series-1)')
        .attr('d',r=>d3.symbol().type(r[7]>=3?d3.symbolSquare:d3.symbolCircle).size(32)());
      c.move(points).attr('transform',r=>`translate(${x(r[0])},${y(r[3])})`);
      nearestOverlay(c,rows,x,r=>`${date(r[0])} · ${status[r[7]]}\nReference ${pct(r[3])}; prior ${pct(r[6])}\nSensitivity ${pct(r[4])}–${pct(r[5])}\nActivity ${r[1]}/${r[2]} eligible checks`);
    }
    function drawActivity(e){
      const c=frame('activity',`Employee ${e.id} observed weekly discount frequency`,'Week start · 2026','Discount activity (%)',76,230);if(!c)return;
      const span=e.history[e.history.length-1][0]-e.history[0][0];
      const step=e.history.length>1?Math.min(28,(c.w-12)/(span+1)*.55):18;
      const x=d3.scaleLinear().domain(d3.extent(e.history,r=>r[0])).range([step/2+2,c.w-step/2-2]);
      const max=d3.max(e.history,r=>r[2]?r[1]/r[2]:0)||.1;
      const y=d3.scaleLinear().domain([0,Math.min(1,max*1.18)]).range([c.h-2,4]);
      c.axes(x,y,v=>date(Math.round(v)),d3.format('.0%'));
      const bars=c.marks.selectAll('rect.bar').data(e.history.filter(r=>r[2]>0),r=>r[0]).join('rect').attr('class','bar').attr('fill','var(--viz-series-1)');
      c.move(bars).attr('x',r=>Math.max(1,x(r[0])-step/2)).attr('y',r=>y(r[1]/r[2])).attr('width',step).attr('height',r=>y(0)-y(r[1]/r[2]));
      nearestOverlay(c,e.history,x,r=>`${date(r[0])}: ${r[1]}/${r[2]} eligible checks (${r[2]?pct(r[1]/r[2]):'Unavailable'})\nRecorded positive amount ${money(r[8])}; full-comp actor checks ${num(r[9])}\n${status[r[7]]}`);
    }
    function horizontal(id,title,rows,xlabel,ylabel){
      const c=frame(id,title,xlabel,ylabel,146,260);if(!c)return;
      const extent=d3.extent([0,...rows.map(r=>r.value)]),span=extent[1]-extent[0]||1;
      const x=d3.scaleLinear().domain([extent[0]<0?extent[0]-.05*span:0,extent[1]>0?extent[1]+.08*span:0]).range([2,c.w-2]);
      const y=d3.scaleBand().domain(rows.map(r=>r.name)).range([2,c.h-2]).padding(.28);
      c.axes(x,y,id==='coverage'?d3.format('~s'):d3.format('.1f'),x=>x,true);
      const bars=c.marks.selectAll('rect.bar').data(rows,r=>r.name).join('rect').attr('class','bar').attr('fill',r=>`var(--viz-series-${r.series})`).attr('opacity',.24)
        .attr('data-tooltip',r=>r.name+': '+r.label);
      c.move(bars).attr('x',r=>Math.min(x(0),x(r.value))).attr('y',r=>y(r.name)).attr('height',y.bandwidth()).attr('width',r=>Math.abs(x(r.value)-x(0)));
      c.group.selectAll('text.value').data(rows,r=>r.name).join('text').attr('class','value').attr('x',r=>r.value<0?x(r.value)+5:Math.min(c.w-4,x(r.value)+6))
        .attr('y',r=>y(r.name)+y.bandwidth()/2+4).attr('text-anchor',r=>r.value>=0&&x(r.value)>c.w-55?'end':'start').text(r=>r.label);
    }
    function drawScenario(){
      const chosen=data.grid.find(s=>s[1]===Number(state.base)&&s[2]===Number(state.memory)&&s[3]===Number(state.odds)&&s[4]===Number(state.dispersion));
      const rows=data.scenarios.filter(r=>r[1]===chosen[0]);
      const h=Number(state.memory),memory=h===0?0:2**(-1/h),baseRate=Number(state.base);
      el('transition').textContent=`Scenario ${chosen[0]} · onset ${pct(baseRate*(1-memory))} · persistence ${pct(baseRate+(1-baseRate)*memory)}`;
      el('scenario-mean').textContent='Last observed-week mean output '+pct(rows[rows.length-1][2]);
      const c=frame('scenarios','Global mean output under the selected hypothetical scenario','Week start · 2026','Mean model output (%)',76,270);if(!c)return;
      const x=d3.scaleLinear().domain(d3.extent(rows,r=>r[0])).range([5,c.w-5]),y=d3.scaleLinear().domain([0,1]).range([c.h-4,4]);
      const ticks=[...new Set(x.ticks(c.width<450?3:6).map(Math.round))];
      c.xAxis.call(d3.axisBottom(x).tickValues(ticks).tickFormat(date).tickSizeOuter(0));c.yAxis.call(d3.axisLeft(y).ticks(4).tickFormat(d3.format('.0%')).tickSizeOuter(0));
      c.xAxis.selectAll('text').attr('text-anchor',(d,i,n)=>i===0?'start':i===n.length-1?'end':'middle');
      const line=d3.line().x(r=>x(r[0])).y(r=>y(r[2]));
      const path=c.marks.selectAll('path.line').data([rows]).join('path').attr('class','line').attr('fill','none').attr('stroke','var(--viz-series-1)').attr('stroke-width',1.7);
      c.move(path).attr('d',line);
      const dots=c.marks.selectAll('circle.point').data(rows,r=>r[0]).join('circle').attr('class','point').attr('r',3.5).attr('fill','var(--viz-series-1)');
      c.move(dots).attr('cx',r=>x(r[0])).attr('cy',r=>y(r[2]));
      nearestOverlay(c,rows,x,r=>`${date(r[0])}: mean output ${pct(r[2])}\n${num(r[3])} informed employee-weeks; scenario ${chosen[0]}\nNot a measured fraud prevalence`);
    }
    function renderAll(){
      const informed=cohort.filter(e=>e.last),widths=informed.map(e=>e.last[5]-e.last[4]);
      el('observed').textContent=num(cohort.length);el('informed').textContent=num(informed.length);
      el('informed-share').textContent=pct(informed.length/cohort.length)+' of observed employees';
      el('width').textContent=widths.length?(100*d3.median(widths)).toFixed(1)+' pp':'Unavailable';
      el('population-denominator').textContent=num(informed.length)+' informed employees';
      el('snapshot').textContent=`Directory: ${num(data.directory)} IDs · ${num(data.noObservations)} without model observations`;
      const e=map.get(String(state.employee));el('person-title').textContent=`Employee ${e.id} · restaurant ${e.location}`;
      el('person-score').textContent='Last informed reference: '+(e.last?pct(e.last[3])+' ('+date(e.last[0])+')':'Unavailable');
      el('person-amount').textContent='Recorded positive discount amount: '+money(d3.sum(e.history,r=>r[8]));
      el('person-coverage').textContent=`${e.history.length} observed weeks · ${e.history.filter(r=>r[7]===1||r[7]===2).length} informed`;
      el('person-comp').textContent='Full-comp actor checks: '+num(d3.sum(e.history,r=>r[9]));
      el('heldout').textContent=num(data.diagnostic.heldout_rows)+' held-out count observations';
      drawHistogram();drawScatter();drawTimeline(e);drawActivity(e);
      const counts=[0,0,0,0];for(const person of employees)for(const r of person.history)counts[r[7]===0?0:r[7]===1?1:r[7]===2?2:3]++;
      horizontal('coverage','Observed week coverage and usable evidence',[
        {name:'Activity evidence',value:counts[1],label:num(counts[1]),series:1},
        {name:'Supported zero',value:counts[2],label:num(counts[2]),series:3},
        {name:'Prior only',value:counts[3],label:num(counts[3]),series:2},
        {name:'Training only',value:counts[0],label:num(counts[0]),series:4}], 'Employee-weeks','Evidence scope');
      horizontal('predictive','Held-out mean log predictive scores for count models',[
        {name:'Beta-binomial',value:data.diagnostic.bb_mean_log_score,label:data.diagnostic.bb_mean_log_score.toFixed(3),series:1},
        {name:'Binomial',value:data.diagnostic.binomial_mean_log_score,label:data.diagnostic.binomial_mean_log_score.toFixed(3),series:2}], 'Mean log score (higher better)','Count model');
      drawScenario();ready=true;
      root.dataset.ready='true';root.dataset.employee=state.employee;root.dataset.cohort=cohort.length;
    }
    function schedule(){if(pending)return;pending=true;requestAnimationFrame(()=>{pending=false;renderAll();});}
    const tip=document.createElement('div');tip.className='chart-tooltip';tip.setAttribute('role','tooltip');tip.hidden=true;root.append(tip);
    root.addEventListener('pointermove',event=>{const target=event.target.closest('[data-tooltip]');if(!target||!target.getAttribute('data-tooltip')){tip.hidden=true;return;}tip.textContent=target.getAttribute('data-tooltip');tip.hidden=false;const bounds=root.getBoundingClientRect();tip.style.left=Math.max(0,Math.min(event.clientX-bounds.left+12,root.clientWidth-tip.offsetWidth))+'px';tip.style.top=(event.clientY-bounds.top+18)+'px';});
    root.addEventListener('pointerleave',()=>{tip.hidden=true;});
    controls();
    el('restaurant').addEventListener('change',()=>{state.restaurant=el('restaurant').value;controls();remember();schedule();});
    el('employee').addEventListener('change',()=>{state.employee=el('employee').value;remember();schedule();});
    for(const name of ['base','memory','odds','dispersion'])el(name).addEventListener('change',()=>{state[name]=Number(el(name).value);remember();schedule();});
    root.querySelectorAll('[role=tab]').forEach(button=>button.addEventListener('click',()=>{
      root.querySelectorAll('[role=tab]').forEach(tab=>{const active=tab===button;tab.classList.toggle('active',active);tab.setAttribute('aria-selected',String(active));root.querySelector('#'+tab.getAttribute('aria-controls')).hidden=!active;});
      requestAnimationFrame(schedule);
    }));
    el('loading').hidden=true;el('content').hidden=false;
    new ResizeObserver(schedule).observe(root);renderAll();
  } catch(error) {
    el('loading').textContent='Unable to display model charts: '+error.message;
    el('loading').setAttribute('role','alert');root.dataset.error=error.message;
  }
})();
