import java.lang.reflect.*;
import java.util.HashSet;
import java.util.Set;

/** Read each journal entry and each unlock list through the MIDlet's normal UI methods. */
final class CampaignProbe {
    private static Class<?> game,record;
    private static Object get(String n, Class<?> t) throws Exception {
        return MarketProbe.field(game,null,n,t);
    }
    private static void questText(String field, int id, Class<?> strings, int slot) throws Exception {
        String expected=id>0 ? (String)MarketProbe.method(strings,"c",String.class,int.class).invoke(null,id) : "";
        String actual=((String[])get(field,String[].class))[slot];
        if (!expected.equals(actual) || (id>0 && actual.length()==0)) throw new AssertionError(field+" text "+id);
    }

    // The stable IDs are taken from the APK tables used by cGame.WA.
    private static int androidMatch(int group,int item,int action,boolean special) {
        if(group==2990 && item>=2000 && item<=2061 && special) return 3;
        boolean neighbor=group==9999 && item>=99990 && item<=99999;
        if(action==29 && (group==item || neighbor)) return 2;
        if(group==item || neighbor) return 1;
        boolean matches;
        switch(group) {
            case 2999: matches=item>=2000 && item<2999;break;
            case 2993: matches=(item>=2000 && item<=2003) || item==2064 || item==2065;break;
            case 2998: matches=item>=2004 && item<=2015;break;
            case 2997: matches=item>=2016 && item<=2027;break;
            case 2996: matches=(item>=2028 && item<=2039) || item==2066 || item==2067;break;
            case 2995: matches=item>=2040 && item<=2051;break;
            case 2994: matches=item>=2052 && item<=2063;break;
            case 3999: matches=item>=3012 && item<=3021;break;
            case 2992: matches=(item>=2068 && item<=2072) || item==2075;break;
            case 2989: matches=item==3022 || item==3023;break;
            default: matches=false;
        }
        return matches?1:0;
    }

    private static void verifyActions(int[][] quests,Object[] tables) throws Exception {
        Method match=MarketProbe.method(game,"a",int.class,boolean.class,int.class,int.class,
                int.class,int.class,boolean.class);
        Set<Integer> items=new HashSet<Integer>();
        for(int type:new int[]{0,1,2,3,4,7,8,11,12,22}) {
            int[][] catalog=(int[][])MarketProbe.field(record,tables[type],"a",int[][].class);
            for(int[] row:catalog) items.add(row[1]);
        }
        for(int[] q:quests) for(int p=19;p<=29;p+=5) if(q[p+1]>0) items.add(q[p]);
        int objectives=0,checks=0;
        for(int[] q:quests) for(int p=19;p<=29;p+=5) {
            if(q[p+1]==0) continue;
            objectives++;
            int group=q[p],action=q[p+2];
            for(int item:items) {
                for(int special=0;special<2;special++) {
                    int actual=(Integer)match.invoke(null,false,group,item,action,action,special!=0);
                    if(actual!=androidMatch(group,item,action,special!=0))
                        throw new AssertionError("Quest "+q[1]+" item "+item+" group "+group+" action "+action);
                    checks++;
                }
            }
            if((Integer)match.invoke(null,true,group,group,action,action,true)!=0 ||
                    (Integer)match.invoke(null,false,group,group,action,action+1,true)!=0)
                throw new AssertionError("Closed or wrong action matched "+q[1]);
        }
        System.out.println("CAMPAIGN nonemptyObjectives="+objectives+" itemActionChecks="+checks);
    }

    // Concrete representatives of the Android animal, crop and neighbor groups.
    // All other objective IDs refer directly to items, rooms or progression events.
    private static int representative(int id) {
        switch(id) {
            case 2990: return 2000;
            case 2999: case 2998: return 2004;
            case 2997: return 2016;
            case 2996: return 2028;
            case 2995: return 2040;
            case 2994: return 2052;
            case 2992: return 2070;
            case 2989: return 3022;
            case 9999: return 99990;
            default: return id;
        }
    }

    private static Object[] farmCrates(Class<?> actor) throws Exception {
        Object[] pool=(Object[])Array.newInstance(actor,64);
        int count=(Integer)MarketProbe.method(actor,"a",int.class,int.class,int.class,pool.getClass(),int.class)
                .invoke(null,0,22,pool,pool.length);
        return java.util.Arrays.copyOf(pool,count);
    }

    private static void expectCrates(Class<?> actor,int... contents) throws Exception {
        Object[] crates=farmCrates(actor);
        int[] actual=new int[crates.length];
        Field item=MarketProbe.variable(actor,"J",int.class);
        for(int i=0;i<crates.length;i++) actual[i]=item.getInt(crates[i]);
        java.util.Arrays.sort(actual);
        java.util.Arrays.sort(contents);
        if(!java.util.Arrays.equals(actual,contents))
            throw new AssertionError("Farm search contents "+java.util.Arrays.toString(actual)+
                    " expected "+java.util.Arrays.toString(contents));
    }

    private static void collectCrate(Class<?> actor,Class<?> strings,int wanted) throws Exception {
        for(Object crate:farmCrates(actor)) {
            if(MarketProbe.variable(actor,"J",int.class).getInt(crate)!=wanted) continue;
            int name=MarketProbe.variable(actor,"p",int.class).getInt(crate);
            Method text=MarketProbe.method(strings,"c",String.class,int.class);
            // The farm's hit test selects an actor. Show that actor's native
            // result dialog, then let its OK handler award it and remove decoys.
            MarketProbe.variable(game,"h",actor).set(null,crate);
            MarketProbe.method(game,"a",void.class,String.class,int.class,int.class)
                    .invoke(null,(String)text.invoke(null,154)+(String)text.invoke(null,name),7,0);
            MarketProbe.method(game,"as",void.class).invoke(null);
            if(get("h",actor)!=null) throw new AssertionError("Crate dialog failed to collect "+wanted);
            return;
        }
        throw new AssertionError("Missing farm search item "+wanted);
    }

    private static void verifySearches(ClassLoader loader,Class<?> strings,int[][] quests) throws Exception {
        Class<?> actor=Class.forName("f",true,loader);
        MarketProbe.method(game,"hf",void.class).invoke(null);
        MarketProbe.method(game,"X",void.class,int.class).invoke(null,13);
        Method load=MarketProbe.method(game,"f",void.class,int.class,int.class,boolean.class);
        Method page=MarketProbe.method(game,"N",boolean.class,int.class);
        Method go=MarketProbe.method(game,"ay",void.class);
        Field selected=MarketProbe.variable(game,"fE",int.class);
        int[] ledger=(int[])get("cc",int[].class),status=(int[])get("cb",int[].class);
        if(quests[62][1]!=9061 || quests[68][1]!=9068 || quests[62][15]!=quests[68][15] ||
                quests[quests[62][15]][1]!=9049) throw new AssertionError("Search quest prerequisites");
        ledger[quests[62][15]]=9049;
        load.invoke(null,62,0,true);
        load.invoke(null,68,1,true);
        page.invoke(null,0);
        selected.setInt(null,0);
        page.invoke(null,1);
        expectCrates(actor);
        go.invoke(null);
        expectCrates(actor,-1,-1,-1,25013,25014,25015);
        selected.setInt(null,1);
        page.invoke(null,1);
        go.invoke(null);
        expectCrates(actor,-1,-1,-1,25013,25014,25015);
        collectCrate(actor,strings,25013);
        collectCrate(actor,strings,25014);
        go.invoke(null);
        expectCrates(actor,-1,-1,-1,25015);
        collectCrate(actor,strings,25015);
        expectCrates(actor);
        if(ledger[62]!=9061 || status[0]!=3 || status[1]!=2)
            throw new AssertionError("First search did not complete independently");
        selected.setInt(null,1);
        go.invoke(null);
        int[] pearls=new int[20];
        java.util.Arrays.fill(pearls,0,10,-1);
        java.util.Arrays.fill(pearls,10,20,25016);
        expectCrates(actor,pearls);
        go.invoke(null);
        expectCrates(actor,pearls);
        for(int i=0;i<10;i++) collectCrate(actor,strings,25016);
        expectCrates(actor);
        if(ledger[68]!=9068 || status[1]!=3) throw new AssertionError("Second search did not complete");
        System.out.println("CAMPAIGN searches=9061,9068 farmBatches=6,6,4,0,20,20,0 collected=3,10 completed=2");
    }

    private static void verifyProgression(int[][] quests) throws Exception {
        // Reinitialize only the journal in this disposable profile. Feed the
        // events normally sent by farm activities to the unmodified dispatcher.
        // The native scheduler decides which quests can enter each journal slot.
        MarketProbe.method(game,"hf",void.class).invoke(null);
        Method level=MarketProbe.method(game,"X",void.class,int.class);
        Method schedule=MarketProbe.method(game,"u",boolean.class);
        Method page=MarketProbe.method(game,"N",boolean.class,int.class);
        Method event=MarketProbe.method(game,"a",int.class,int.class,int.class,int.class,boolean.class);
        Method dismiss=MarketProbe.method(game,"aS",void.class,int.class);
        Field selection=MarketProbe.variable(game,"fE",int.class);
        int[] ledger=(int[])get("cc",int[].class),rows=(int[])get("bE",int[].class);
        int[] status=(int[])get("cb",int[].class);
        Set<Integer> finished=new HashSet<Integer>(),actions=new HashSet<Integer>();
        MarketProbe.variable(game,"C",int.class).setInt(null,10); // native tutorial timing (no notification delay)
        page.invoke(null,0);
        for(int playerLevel=1;playerLevel<=50;playerLevel++) {
            level.invoke(null,playerLevel);
            for(;;) {
                schedule.invoke(null);
                if(rows[0]<0) break;
                int[] quest=quests[rows[0]];
                if(quest[14]>playerLevel || !finished.add(quest[1]))
                    throw new AssertionError("Unexpected scheduled quest "+quest[1]+" at level "+playerLevel);
                for(int col=15;col<=17;col++) {
                    int dependency=quest[col];
                    if(dependency>=0 && !finished.contains(quests[dependency][1]))
                        throw new AssertionError("Missing prerequisite for "+quest[1]);
                }
                selection.setInt(null,0);
                page.invoke(null,1);
                if(status[0]!=2) throw new AssertionError("Journal failed to open "+quest[1]);
                for(int col=19;col<=29;col+=5) {
                    if(quest[col+1]==0) continue;
                    int item=quest[col],action=quest[col+2];
                    actions.add(action);
                    event.invoke(null,representative(item),quest[col+1],action,item==2990);
                }
                if(status[0]!=3 || ledger[quest[0]]!=quest[1])
                    throw new AssertionError("Events failed to finish quest "+quest[1]+" at level "+playerLevel);
                if(finished.size()==quests.length) {
                    MarketProbe.method(game,"ax",void.class).invoke(null);
                    if((Integer)get("A",int.class)!=4 || rows[0]!=-1)
                        throw new AssertionError("Last payout failed to select the campaign ending");
                    System.out.println("CAMPAIGN finalQuest="+quest[1]+" outcome=4");
                } else dismiss.invoke(null,0);
            }
        }
        if(finished.size()!=quests.length || !(Boolean)MarketProbe.method(game,"v",boolean.class).invoke(null))
            throw new AssertionError("Campaign ended with "+finished.size()+" entries");
        System.out.println("CAMPAIGN scheduledAndCompleted="+finished.size()+" eventTypes="+actions.size()+" maxLevel=50");
    }
    static void check(ClassLoader loader) throws Exception {
        game=Class.forName("a",true,loader);
        record=Class.forName("h",true,loader);
        Class<?> strings=Class.forName("g",true,loader);
        Object[] tables=(Object[])MarketProbe.field(record,null,"a",Array.newInstance(record,0).getClass());
        int[][] quests=(int[][])MarketProbe.field(record,tables[6],"a",int[][].class);
        int[][] cards=(int[][])MarketProbe.field(record,tables[10],"a",int[][].class);
        int[] economy=(int[])get("d",int[].class);
        if (quests.length!=304 || cards.length!=297 || economy[27]!=99000000 || economy[28]!=100000)
            throw new AssertionError("Campaign dimensions or economy limits");
        Method load=MarketProbe.method(game,"f",void.class,int.class,int.class,boolean.class);
        Method decode=MarketProbe.method(game,"p",int.class,int.class);
        for(int[] q:quests) {
            load.invoke(null,q[0],0,true);
            questText("i",q[3],strings,0);
            questText("j",q[5],strings,0);
            questText("k",q[6],strings,0);
            questText("l",q[18],strings,0);
            questText("m",q[23],strings,0);
            questText("n",q[28],strings,0);
            if (((int[])get("bD",int[].class))[0]!=q[1] ||
                ((int[])get("bF",int[].class))[0]!=q[14]) throw new AssertionError("Quest ID/level "+q[1]);
            for(int obj=0;obj<3;obj++) {
                String name=new String[]{"bJ","bO","bT"}[obj];
                int value=(Integer)decode.invoke(null,((int[])get(name,int[].class))[0]);
                if(value!=q[20+5*obj]) throw new AssertionError("Quest "+q[1]+" objective "+obj);
            }
        }
        System.out.println("CAMPAIGN journal=304 objectiveSlots=912");
        verifyActions(quests,tables);
        Method visit=MarketProbe.method(game,"y",boolean.class,int.class);
        Method setLevel=MarketProbe.method(game,"X",void.class,int.class);
        int checked=0;
        for(int level=1;level<=50;level++) {
            setLevel.invoke(null,level);
            visit.invoke(null,1);
            int[] visible=(int[])get("aO",int[].class),frames=(int[])get("aP",int[].class);
            int[] palettes=(int[])get("aQ",int[].class);
            int pos=(Integer)get("en",int.class)>0 ? 1 : 0;
            for(int[] row:cards) {
                if (row[2]!=level || row[1]==3 || row[1]==7) continue;
                if(visible[pos]!=row[3] || frames[pos]!=row[4] || palettes[pos]!=row[5])
                    throw new AssertionError("Unlock row "+row[0]);
                checked++; pos++;
            }
            if(pos!=(Integer)get("em",int.class)) throw new AssertionError("Unlock count "+level);
        }
        System.out.println("CAMPAIGN levelScreens=50 unlockCards="+checked);
        synchronized(Class.forName("GF3Presentation",false,loader)) {
            verifySearches(loader,strings,quests);
            verifyProgression(quests);
        }
        System.out.println("CAMPAIGN_OK");
    }
}
