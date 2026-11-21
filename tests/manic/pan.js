() => {
  const st = {enabled:false,frames:[],calls:{},frameHashes:[],samples:[],drag:[]};
  function wrapNative(match,label) {
    const name=Object.keys(Native).find(x=>x.includes(match));
    if(!name) return;
    const native=Native[name];
    Native[name]=function(...args){
      if(!st.enabled)return native.apply(this,args);
      const t=performance.now();
      try{return native.apply(this,args);}
      finally{
        const data=st.calls[label]||(st.calls[label]=[0,0,0]);
        data[0]++;data[1]+=performance.now()-t;
        if(label==="getRGB")data[2]+=args[6]*args[7];
        if(label==="drawRGB")data[2]+=args[6]*args[7];
      }
    };
  }
  wrapNative('ImageData.getRGB.','getRGB');
  wrapNative('Graphics.drawRGB.','drawRGB');
  wrapNative('DisplayDevice.refresh0.','refresh');
  const waitName=Object.keys(Native).find(x=>x.includes('NativeEventMonitor.waitForNativeEvent.'));
  if(waitName) {
    const original=Native[waitName];
    Native[waitName]=function(...args) {
      const depth=original.apply(this,args);
      if(st.enabled && typeof depth==='number')st.queues.push(depth);
      return depth;
    };
  }
  window.attachScreen=()=>{
    const canvas=document.getElementById('canvas'),ctx=canvas.getContext('2d');
    if(ctx.__observed)return;
    ctx.__observed=true;
    const small=document.createElement('canvas');small.width=120;small.height=200;
    const sample=small.getContext('2d',{willReadFrequently:true});
    const factor=Math.min(canvas.width/480,canvas.height/800);
    const width=Math.floor(480*factor),height=Math.floor(800*factor);
    const left=Math.floor((canvas.width-width)/2),top=Math.floor((canvas.height-height)/2);
    const thumbnail=()=>{
      sample.drawImage(canvas,left,top,width,height,0,0,120,200);
      return sample.getImageData(0,0,120,200).data;
    };
    const game=CLASSES.getClass("a"),actor=CLASSES.getClass("f"),perf=CLASSES.getClass("GF3Presentation");
    const field=(cls,key,type)=>cls.getFieldByName(J2ME.toUTF8(key),J2ME.toUTF8(type),false).byteOffset;
    const rt=[...J2ME.RuntimeTemplate.all].find(r=>r.staticObjectAddresses[game.id]);
    const camera=(rt.staticObjectAddresses[game.id]+field(game,"c","Lf;"))>>>2;
    const dx=field(actor,"r","I"),dy=field(actor,"s","I");
    const counters=["ticks","presentations","interpolated"].map(n=>(rt.staticObjectAddresses[perf.id]+field(perf,n,"I"))>>>2);
    window.farmCamera=()=>{
      const pos=i32[camera];
      return [i32[(pos+dx)>>>2],i32[(pos+dy)>>>2],...counters.map(i=>i32[i])];
    };
    const initialCamera=farmCamera(),reference=thumbnail();
    // Two textured buildings stand on fixed world coordinates: the manor and
    // the produce stand. Confirm that their pixels move with the actual camera.
    const landmarks=[[244,600,70,84],[265,332,59,55]];
    const compareLandmarks=(data,cam)=>{
      const dx=Math.round((cam[1]-initialCamera[1])/4);
      const dy=Math.round((initialCamera[0]-cam[0])/4);
      let best=0;
      // The LCD may be presenting an intermediate camera pose between ticks.
      for(let j=dy-3;j<=dy+3;j++)for(let i=dx-3;i<=dx+3;i++) {
        let worst=1;
        for(const [left,top,w,h] of landmarks) {
          let good=0,n=0;
          for(let y=Math.ceil(top/4);y<(top+h)/4;y++)
            for(let x=Math.ceil(left/4);x<(left+w)/4;x++){
              if(x+i<0||x+i>=120||y+j<0||y+j>=200)continue;
              const src=(y*120+x)*4,dst=((y+j)*120+x+i)*4;
              let diff=0;
              for(let c=0;c<3;c++)diff=Math.max(diff,Math.abs(reference[src+c]-data[dst+c]));
              if(diff<=44)good++;
              n++;
            }
          worst=Math.min(worst,n>12?good/n:0);
        }
        best=Math.max(best,worst);
      }
      return best;
    };
    // Calibrate the visual check against the loss of each complete landmark.
    // This stays in the thumbnail and never writes into the game's LCD.
    st.missingLandmarkScores=landmarks.map(([left,top,w,h])=>{
      const absent=reference.slice();
      for(let y=Math.ceil(top/4);y<(top+h)/4;y++) for(let x=Math.ceil(left/4);x<(left+w)/4;x++){
        const i=(y*120+x)*4;
        absent[i]=255;absent[i+1]=0;absent[i+2]=255;
      }
      const score=compareLandmarks(absent,initialCamera);
      if(score>=.65)throw Error('Cannot distinguish a missing farm landmark at '+left+','+top);
      return score;
    });
    const draw=ctx.drawImage;
    ctx.drawImage=function(...args) {
      const v=draw.apply(this,args);
      if(st.enabled) {
        const time=performance.now();
        st.frames.push(time);
        st.camera.push(farmCamera());
        if(st.visual) {
          const bytes=thumbnail();
          let hash=2166136261;
          for(let i=0;i<bytes.length;i+=4) {
            hash=Math.imul(hash^bytes[i],16777619);hash=Math.imul(hash^bytes[i+1],16777619);hash=Math.imul(hash^bytes[i+2],16777619);
          }
          st.frameHashes.push(hash);
          if(st.samples.length===0 || time-st.samples.at(-1)[0]>220)
            st.samples.push([time,small.toDataURL('image/png').split(',')[1],
                             compareLandmarks(bytes,st.camera.at(-1))]);
        }
      }
      return v;
    };
  };
  window.sendPoint=(kind,x,y)=>{
    const canvas=document.querySelector('#canvas'),rect=canvas.getBoundingClientRect();
    const scale=Math.min(canvas.width/480,canvas.height/800);
    const u=(canvas.width-480*scale)/2+x*scale,v=(canvas.height-800*scale)/2+y*scale;
    const cx=rect.left+u/canvas.width*rect.width,cy=rect.top+v/canvas.height*rect.height;
    const touch={identifier:2,target:canvas,clientX:cx,clientY:cy,pageX:cx+scrollX,pageY:cy+scrollY};
    const ev=new Event(kind,{bubbles:true,cancelable:true});
    Object.defineProperties(ev,{touches:{value:kind==='touchend'?[]:[touch]},
      targetTouches:{value:kind==='touchend'?[]:[touch]},changedTouches:{value:[touch]}});
    canvas.dispatchEvent(ev);
    if(st.enabled)st.drag.push([performance.now(),kind,x,y]);
  };
  window.measurePan=async({duration,visual,pan})=>{
    st.frames=[];st.calls={};st.frameHashes=[];st.samples=[];st.drag=[];st.queues=[];st.camera=[];
    st.visual=visual;st.enabled=true;st.start=performance.now();
    if(pan) {
      const leg=850;
      sendPoint('touchstart',100,580);
      await new Promise(r=>setTimeout(r,90));
      const start=performance.now();
      await new Promise(done=>{
        function update() {
          const elapsed=performance.now()-start;
          if(elapsed>=duration){sendPoint('touchend',100,580);done();return;}
          const half=elapsed/leg,index=Math.floor(half);
          const t=index%2===0?half-index:1-(half-index);
          sendPoint('touchmove',100+100*t,580-110*t);
          setTimeout(update,12);
        }
        update();
      });
    } else await new Promise(r=>setTimeout(r,duration));
    st.end=performance.now();st.enabled=false;
    return JSON.parse(JSON.stringify(st));
  };
}
