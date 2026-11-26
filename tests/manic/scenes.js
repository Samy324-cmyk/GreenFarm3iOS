/* Read the game's current screen and deliver normal touchscreen presses to Manic. */
window.gf3Scenes = (() => {
  function state() {
    try {
      const game=CLASSES.getClass("a");
      const rt=[...J2ME.RuntimeTemplate.all].find(runtime=>runtime.staticObjectAddresses[game.id]);
      if (!rt) return {};
      function field(type,name,signature) {
        const c=CLASSES.getClass(type);
        const f=c.getFieldByName(J2ME.toUTF8(name),J2ME.toUTF8(signature),true);
        const base=rt.staticObjectAddresses[c.id];
        return base ? i32[(base+f.byteOffset)>>2] : 0;
      }
      const array=address=>address ? J2ME.getArrayFromAddr(address) : [];
      const top=field("a","a","I");
      const screen=array(field("a","a","[I"))[top];
      const hits=Array.from(array(field("a","i","[[I"))).map(array)
                        .filter(r=>r[2]>0 && r[3]>0 && r[5]>0);
      return {screen,room:field("a","G","I"),tab:field("GF3MarketFront","tab","I"),
              shelf:field("GF3MarketFront","shelf","I"),offerCount:field("GF3MarketFront","offerCount","I"),
              offerIds:Array.from(array(field("GF3MarketFront","offerIds","[I"))),
              offerBills:Array.from(array(field("GF3MarketFront","offerBills","[I"))),
              hits:hits.map(r=>Array.from(r))};
    } catch (error) { return {}; }  // MIDlet classes may still be loading.
  }
  function matches(goal) {
    const s=state();
    return ["screen","room","tab","shelf"].every(k=>!(k in goal)||s[k]===goal[k]) &&
           (!goal.button || s.hits?.some(r=>r[5]===goal.button));
  }
  function viewport(canvas) {
    const w=canvas.width,h=canvas.height;
    const dw=Math.min(w,Math.floor(h*480/800)),dh=Math.min(h,Math.floor(w*800/480));
    return {dw,dh,left:(w-dw)>>1,top:(h-dh)>>1};
  }
  async function press(step) {
    const canvas=document.getElementById("canvas"), box=canvas.getBoundingClientRect();
    const {dw,dh,left,top}=viewport(canvas);
    let point=step.tap;
    if (step.pressButton) {
      const r=state().hits.find(r=>r[5]===step.pressButton);
      if (!r) throw Error("Botón ausente "+step.pressButton);
      point=[479-r[1]-Math.floor(r[3]/2),r[0]+Math.floor(r[2]/2)];
    }
    const x=left+Math.floor(point[0]*dw/480),y=top+Math.floor(point[1]*dh/800);
    const contact={identifier:1,target:canvas,clientX:box.left+(x+0.5)*box.width/canvas.width,
                   clientY:box.top+(y+0.5)*box.height/canvas.height};
    function dispatch(start) {
      const ev=new Event(start?"touchstart":"touchend",{bubbles:true,cancelable:true});
      Object.defineProperties(ev,{touches:{value:start?[contact]:[]},
          changedTouches:{value:[contact]},targetTouches:{value:start?[contact]:[]}});
      canvas.dispatchEvent(ev);
    }
    dispatch(true);
    await new Promise(done=>setTimeout(done,180));
    dispatch(false);
  }
  const references=new Map();
  async function compare(name,region,base64) {
    let ref=references.get(name);
    if (!ref) {
      const im=new Image();
      await new Promise((ok,fail)=>{im.onload=ok;im.onerror=fail;im.src="data:image/png;base64,"+base64;});
      const tmp=document.createElement("canvas");tmp.width=im.width;tmp.height=im.height;
      const ctx=tmp.getContext("2d");ctx.drawImage(im,0,0);
      ref=ctx.getImageData(0,0,tmp.width,tmp.height);
      references.set(name,ref);
    }
    const c=document.getElementById("canvas"), {dw,dh,left,top}=viewport(c);
    const screen=c.getContext("2d").getImageData(0,0,c.width,c.height).data;
    const [x0,y0,x1,y1]=region;
    if (ref.width!==x1-x0 || ref.height!==y1-y0) throw Error("Referencia incorrecta de "+name);
    let count=0,different=0;
    for (let row=0;row<dh;row++) {
      const x=Math.floor(row*800/dh);
      if (x<x0 || x>=x1) continue;
      for (let col=0;col<dw;col++) {
        const y=479-Math.floor(col*480/dw);
        if (y<y0 || y>=y1) continue;
        const src=4*((y-y0)*ref.width+x-x0),dst=4*((row+top)*c.width+col+left);
        if (Math.max(Math.abs(ref.data[src]-screen[dst]),Math.abs(ref.data[src+1]-screen[dst+1]),
                     Math.abs(ref.data[src+2]-screen[dst+2]))>4) different++;
        count++;
      }
    }
    return {count,different,ratio:count ? different/count : 1};
  }
  return {state,matches,press,compare};
})();
