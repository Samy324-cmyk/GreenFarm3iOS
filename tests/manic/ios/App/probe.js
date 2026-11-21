// Observe the original Spanish text and XP counter from the LCD. Inputs come
// from XCTest through the iPhone touchscreen, independently of this observer.
(() => {
    const checks = window.__farmRestored ? [
        ["farm",428,742,25,30,0xf5f8fc,"6ec9d62138e5d32f3c0f0d35cf7ea6dadb0656bf75ad33bd2d539a2f026c1cc0"],
    ] : [
        ["letter",125,293,56,370,0x482c50,"dbfc99decd849acd08d1879753426ae6b3e508be48558fccc69b197576bfd006"],
        ["inheritance",80,294,98,369,0x482c50,"0d39f63d3178a7869f9caa2ecfd0b736719a4625a77f663ea6576aa5415a4b2d"],
        ["wheat",129,294,48,372,0x482c50,"ad4222aa91a393a148af032d8b95c5b368117183198e2471ae34776af2a6db28"],
        ["harvested",437,386,17,31,0xffffff,"615a60f43769abb670e0d8a655f2dd87a9e9fa34be9f157962a33441630cbf01"]
    ];
    let step = 0;
    let route, routeIndex = 0;
    const stageNames = {diario:"journal", walt:"walt", mision:"mision", aviso:"aviso",
                        "cerrar-aviso":"cerrar-aviso", mansion:"blueprint", cocina:"kitchen"};
    const art = new Map();

    function report(lcd, stage) {
        window.webkit.messageHandlers.farmCheck.postMessage({stage,png:lcd.toDataURL().split(",")[1]});
    }

    function journalOpen(lcd) {
        // Input rectangles move during the sliding animation. The last pose
        // has Walt's whole blue portrait under the location used by XCTest.
        const w = 272, h = 76;
        const rgba = lcd.getContext("2d").getImageData(18,18,w,h).data;
        const bins = new Uint32Array(16);
        const expected = [918,1107,927,1292,533,503,306,832,330,256,277,353,769,480,664,669];
        for (let y=0; y<h; y++) for (let x=0; x<w; x++) {
            const p = (y*w+x)*4, r = rgba[p], g = rgba[p+1], b = rgba[p+2];
            if (b>130 && b>r*1.4 && b>g*1.1) bins[Math.floor(y*4/h)*4+Math.floor(x*4/w)]++;
        }
        return expected.every((n,i) => Math.abs(n-bins[i]) <= Math.max(6,n*.1));
    }

    async function checkRoute(lcd) {
        if (!route) {
            const response = await fetch("/scenes.json");
            if (!response.ok) throw Error("Missing farm route");
            const steps = await response.json();
            const finish = steps.findIndex(step => step.name === "cocina");
            if (finish < 0) throw Error("Farm route does not reach the kitchen");
            route = steps.slice(0, finish + 1);
        }
        const goal = route[routeIndex];
        if (!gf3Scenes.matches(goal) || goal.name === "diario" && !journalOpen(lcd)) return;
        if (goal.region) {
            if (!art.has(goal.name)) {
                const response = await fetch("/screens/" + goal.name + ".png");
                if (!response.ok) throw Error("Missing screen reference " + goal.name);
                const bytes = new Uint8Array(await response.arrayBuffer());
                let binary = "";
                for (let i = 0; i < bytes.length; i += 16384)
                    binary += String.fromCharCode(...bytes.subarray(i, i + 16384));
                art.set(goal.name, btoa(binary));
            }
            const pixels = await gf3Scenes.compare(goal.name, goal.region, art.get(goal.name));
            if (pixels.ratio > (goal.maxDifference ?? 0.025)) return;
        }
        // The state machine also checks each actual button between Walt's
        // cards. Let XCTest send the next touch only once its screen exists.
        report(lcd, stageNames[goal.name] || "menu-" + goal.name);
        routeIndex++;
    }
    function measureTouch(lcd) {
        const ctx = lcd.getContext("2d"), present = ctx.drawImage;
        const game = CLASSES.getClass("a"), actor = CLASSES.getClass("f");
        const offset = (klass,name,type) => klass.getFieldByName(J2ME.toUTF8(name),J2ME.toUTF8(type),false).byteOffset;
        const rt = Array.from(J2ME.RuntimeTemplate.all).find(r=>r.staticObjectAddresses[game.id]);
        const cameraSlot = (rt.staticObjectAddresses[game.id]+offset(game,"c","Lf;"))>>>2;
        const x = offset(actor,"r","I"), y = offset(actor,"s","I");
        function position() {
            const camera=i32[cameraSlot];
            return [i32[(camera+x)>>>2],i32[(camera+y)>>>2]];
        }
        let drag=null;
        const gestures=[];
        document.addEventListener("touchstart",()=>{
            drag={start:performance.now(),frames:[],first:position()};
        },true);
        ctx.drawImage=function(...args) {
            const result=present.apply(this,args);
            if(drag) drag.frames.push(performance.now());
            return result;
        };
        document.addEventListener("touchend",()=>{
            if(!drag)return;
            drag.finish=performance.now();
            drag.last=position();
            if(drag.frames.length>1)gestures.push(drag);
            drag=null;
            if(gestures.length!==3)return;
            const gaps=gestures.flatMap(g=>g.frames.slice(1).map((t,i)=>t-g.frames[i])).sort((a,b)=>a-b);
            const dt=gestures.reduce((sum,g)=>sum+g.frames[g.frames.length-1]-g.frames[0],0);
            const travel=gestures.reduce((sum,g)=>sum+Math.abs(g.last[0]-g.first[0])+Math.abs(g.last[1]-g.first[1]),0);
            const metrics={gestures, cameraPixels:travel, presentedFps:gaps.length*1000/dt,
                           p95Ms:gaps[Math.floor(.95*(gaps.length-1))],maxGapMs:gaps[gaps.length-1]};
            if(travel>20 && gaps.length>10) window.webkit.messageHandlers.farmCheck.postMessage({
                stage:"pan",png:lcd.toDataURL().split(",")[1],metrics
            });
        },true);
    }
    async function sample() {
        const lcd = document.getElementById("canvas");
        const restoredRoute = window.__farmRestored && !window.__panTest;
        if (lcd && lcd.width === 480 && lcd.height === 800 && restoredRoute && step === checks.length) {
            await checkRoute(lcd);
        } else if (step < checks.length && lcd && lcd.width === 480 && lcd.height === 800) {
            const [stage,x,y,w,h,color,expected] = checks[step];
            const pixels = lcd.getContext("2d").getImageData(x,y,w,h).data;
            const mask = new Uint8Array(w*h);
            for (let i=0;i<mask.length;i++) {
                const k=i*4;
                mask[i]=((pixels[k]<<16 | pixels[k+1]<<8 | pixels[k+2])===color) ? 1 : 0;
            }
            const digest = new Uint8Array(await crypto.subtle.digest("SHA-256",mask));
            const hex = Array.from(digest,b=>b.toString(16).padStart(2,"0")).join("");
            if (hex===expected) {
                step++;
                if(window.__panTest && stage==="farm") {
                    measureTouch(lcd);
                    step=checks.length;
                }
                report(lcd, stage);
            }
        }
        if (step < checks.length || restoredRoute && (!route || routeIndex < route.length))
            setTimeout(observe, 250);
    }

    function observe() {
        sample().catch(error => window.webkit.messageHandlers.farmCheck.postMessage({
            stage:"observer-error", detail:String(error)
        }));
    }
    setTimeout(observe,1000);
})();
