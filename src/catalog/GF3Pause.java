import java.util.Vector;
import javax.microedition.lcdui.Font;
import javax.microedition.lcdui.Graphics;
import javax.microedition.lcdui.Image;
import javax.microedition.lcdui.game.Sprite;

/** Local actions and captions for Android's pause and settings controls. */
final class GF3Pause {
    private static final int PANEL=15, COOKIE=151, TERMS=153, LANG_TITLE=155;
    private static final int LANGUAGE=156, SELECTED=157, LANG_NAME=158, BACK=159;
    private static final int CONTACT=161;
    private static boolean choosingLanguage;
    private static long messageStarts,messageUntil;
    private static Image message;

    private static void button(int i,boolean on) {
        a.a(PANEL,i,on);
        a.b(PANEL,i,on);
    }
    private static void label(int i,String text,boolean on) {
        a.captions[PANEL][i]=text;
        a.a(PANEL,i,on);
    }
    private static void hits() {
        a.gf();
        a.H(PANEL);
    }
    private static void policies(boolean on) {
        button(COOKIE,on);
        button(TERMS,on);
        label(COOKIE+1,GF3PauseWords.cookies,on);
        label(TERMS+1,GF3PauseWords.terms,on);
        button(2,on);
        label(3,GF3PauseWords.support,on);
        a.a(PANEL,10,on);
        // These two side buttons are disabled by the Android retail build.
        button(16,false);
        button(17,false);
    }
    static void open() {
        a.gf3PauseOpen();
        policies(true);
        hits();
    }
    static void leave() {
        a.gf3PauseLeave();
        policies(false);
    }
    static void options() {
        a.gf3PauseOptions();
        button(28,true);
        button(32,GF3Zoom.onePointer());
        label(33,GF3Zoom.choice(),GF3Zoom.onePointer());
        hits();
    }
    static void closeOptions() {
        a.gf3PauseCloseOptions();
        button(28,false);
        button(32,false);
        a.a(PANEL,33,false);
    }
    private static void language(boolean show) {
        choosingLanguage=show;
        if(show) {
            closeOptions();
            a.l(false);
        }
        label(LANG_TITLE,GF3PauseWords.language,show);
        button(LANGUAGE,show);
        a.a(PANEL,SELECTED,show);
        a.b(PANEL,SELECTED,false);
        a.a(PANEL,LANG_NAME,show);
        a.b(PANEL,LANG_NAME,false);
        button(BACK,show);
        label(BACK+1,GF3PauseWords.back,show);
        if(show) hits();
        else {a.l(true);options();}
    }
    private static Image makeMessage() {
        // The Android game delegates this message to a short system Toast.
        // Use the MIDP system font instead of the farm's decorative font.
        Font font=Font.getFont(Font.FACE_SYSTEM,Font.STYLE_PLAIN,Font.SIZE_MEDIUM);
        String words=GF3PauseWords.offline;
        Vector<String> lines=new Vector<String>();
        int start=0,width=0;
        while(start<words.length()) {
            int end=words.indexOf(' ',start),last=start;
            while(end!=-1 && font.stringWidth(words.substring(start,end))<=556) {
                last=end;end=words.indexOf(' ',end+1);
            }
            if(end==-1 && font.stringWidth(words.substring(start))<=556)last=words.length();
            if(last==start)last=end==-1?words.length():end;
            String line=words.substring(start,last);lines.addElement(line);
            width=Math.max(width,font.stringWidth(line));start=last+1;
        }
        int w=width+32,h=font.getHeight()*lines.size()+20;
        Image rgb=Image.createImage(w,h);Graphics text=rgb.getGraphics();
        text.setColor(0xff00ff);text.fillRect(0,0,w,h);
        text.setColor(0x383838);text.fillRoundRect(0,0,w,h,14,14);
        text.setFont(font);text.setColor(0xffffff);
        for(int i=0;i<lines.size();i++)
            text.drawString(lines.elementAt(i),16,10+i*font.getHeight(),Graphics.TOP|Graphics.LEFT);
        int[] pixels=new int[w*h];
        rgb.getRGB(pixels,0,w,0,0,w,h);
        for(int i=0;i<pixels.length;i++)if((pixels[i]&0xffffff)==0xff00ff)pixels[i]=0;
        return Image.createRGBImage(pixels,w,h,true);
    }
    static void input(int id) {
        if((id>>>16)==PANEL) {
            int i=id&65535;
            if(i==32 && a.N && GF3Zoom.onePointer()) {
                GF3FarmAudio.original(60);
                GF3Zoom.toggle();
                label(33,GF3Zoom.choice(),true);
                return;
            }
            if(((i==2 || i==9 || i==COOKIE || i==TERMS) && a.J) || (i==CONTACT && a.L)) {
                GF3FarmAudio.original(60);
                messageStarts=System.currentTimeMillis()+1000L;
                messageUntil=messageStarts+2000L;
                return;
            }
            if(i==26 && a.N) {
                a.gf3PauseInput(id);
                button(CONTACT,true);
                label(CONTACT+1,GF3PauseWords.contact,true);
                hits();
                return;
            }
            if(i==48 && a.L) {
                button(CONTACT,false);
                label(CONTACT+1,GF3PauseWords.contact,false);
            }
            if((i==54 || i==55) && a.L) {
                GF3FarmAudio.original(60);
                int pages=GF3PauseWords.pages.length;
                a.et=(a.et-1+(i==54?pages-1:1))%pages+1;
                a.gE();
                return;
            }
            if(i==28 && a.N) {
                GF3FarmAudio.original(60);
                language(true);
                return;
            }
            if(choosingLanguage && (i==LANGUAGE || i==BACK)) {
                GF3FarmAudio.original(i==BACK?56:60);
                if(i==BACK) language(false);
                return;
            }
        }
        a.gf3PauseInput(id);
    }
    private static void reset() {
        choosingLanguage=false;
        for(int i=COOKIE;i<=CONTACT+1;i++) {
            a.a(PANEL,i,false);
            a.b(PANEL,i,false);
        }
        messageUntil=0;
    }
    static String heading(int unused){return GF3PauseWords.headings[a.et-1];}
    static String body(int unused){return GF3PauseWords.pages[a.et-1];}
    static boolean phase(int phase) {
        if(phase==0 || phase==5) {
            // Native phase zero restores templates; its pause initializer
            // will enable the existing controls before we clear extra rows.
            if(phase==5) reset();
            boolean handled=a.gf3PausePhase(phase);
            if(phase==0) {reset();policies(true);hits();}
            return handled;
        }
        boolean handled=a.gf3PausePhase(phase);
        if(phase==3 && messageUntil!=0) {
            long now=System.currentTimeMillis();
            if(now>=messageUntil) messageUntil=0;
            else if(now>=messageStarts) {
                if(message==null)message=makeMessage();
                int w=message.getWidth(),h=message.getHeight();
                g.screen.drawRegion(message,0,0,w,h,Sprite.TRANS_ROT90,48,(800-w)/2,Graphics.TOP|Graphics.LEFT);
            }
        }
        return handled;
    }
}
